# Phase 0: kubectl 기반 클러스터 검증 가이드

**문서 버전**: 1.0
**작성일**: 2026-02-06
**대상 클러스터**: OCI ARM K3s
**대상 네임스페이스**: observer-prod
**전제 조건**: kubectl 접근 권한 (cluster-admin 또는 namespace-admin)

---

## 검증 흐름

```
Step 0 (클러스터 연결)
  │
  ▼
Step 1 (네임스페이스)
  │
  ▼
Step 2 (PVC 상태)
  │
  ▼
Step 3 (Secret 존재) ← CRITICAL
  │
  ▼
Step 4 (ConfigMap 확인)
  │
  ▼
Step 5 (Service 확인)
  │
  ▼
Step 6 (Pod 상태)
  │
  ▼
Step 7 (Health Check)
  │
  ▼
Step 8 (데이터 영속성)
  │
  ▼
Step 9 (24시간 안정성)
```

---

## Step 0: 클러스터 연결 확인

### 명령어

```bash
kubectl cluster-info
kubectl get nodes -o wide
```

### 정상 결과

```
Kubernetes control plane is running at https://<ip>:6443
NAME              STATUS   ROLES                  AGE   VERSION        OS-IMAGE
oracle-obs-arm    Ready    control-plane,master   Xd    v1.2x.x+k3s1  Ubuntu ...
```

- STATUS = `Ready`
- K3s 버전 확인

### 비정상 결과

| 증상 | 원인 | 조치 |
|------|------|------|
| `The connection to the server was refused` | kubeconfig 오류 또는 클러스터 다운 | kubeconfig 경로 확인: `/etc/rancher/k3s/k3s.yaml` |
| `Unable to connect to the server` | 네트워크 문제 | 서버 SSH 접속 후 `systemctl status k3s` 확인 |
| STATUS = `NotReady` | 노드 health 문제 | `kubectl describe node <name>` → Conditions 확인 |

---

## Step 1: 네임스페이스 확인

### 명령어

```bash
kubectl get namespace observer-prod
```

### 정상 결과

```
NAME            STATUS   AGE
observer-prod   Active   Xd
```

### 비정상 결과

| 증상 | 조치 |
|------|------|
| `namespaces "observer-prod" not found` | `kubectl create namespace observer-prod` |

---

## Step 2: PVC 상태 확인

### 명령어

```bash
kubectl get pvc -n observer-prod
```

### 정상 결과

```
NAME                    STATUS   VOLUME     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
observer-db-pvc         Bound    pvc-xxx    10Gi       RWO            local-path     Xd
observer-data-pvc       Bound    pvc-xxx    20Gi       RWO            local-path     Xd
observer-logs-pvc       Bound    pvc-xxx    5Gi        RWO            local-path     Xd
observer-universe-pvc   Bound    pvc-xxx    1Gi        RWO            local-path     Xd
```

- 4개 PVC 모두 STATUS = `Bound`

### 비정상 결과

| 증상 | 진단 | 조치 |
|------|------|------|
| STATUS = `Pending` | `kubectl describe pvc <name> -n observer-prod` | StorageClass 확인: `kubectl get sc` |
| PVC 없음 | kustomization.yaml에서 리소스 누락 | `kubectl apply -k infra/k8s/overlays/production` |
| local-path 없음 | K3s local-path-provisioner 미동작 | `kubectl get pods -n kube-system -l app=local-path-provisioner` |

### 추가: PVC 실제 저장 위치 확인 (서버에서)

```bash
# 서버 SSH 접속 후
ls -la /var/lib/rancher/k3s/storage/
```

정상: PVC ID에 해당하는 디렉토리 존재

---

## Step 3: Secret 확인 [CRITICAL]

### Step 3-1: SealedSecret Controller 상태

```bash
kubectl get pods -n sealed-secrets
```

정상: controller Pod `Running`

### Step 3-2: SealedSecret에서 생성된 Secret

```bash
kubectl get sealedsecrets -n observer-prod
kubectl get secrets -n observer-prod -l sealedsecrets.bitnami.com/sealed-secrets-key
```

정상: `obs-db-secret`, `obs-kis-secret`, `obs-kiwoom-secret` 모두 존재

### Step 3-3: observer-secrets 존재 확인 [CRITICAL]

```bash
kubectl get secret observer-secrets -n observer-prod
```

#### 정상 결과

```
NAME               TYPE     DATA   AGE
observer-secrets   Opaque   13+    Xd
```

#### 비정상 결과

```
Error from server (NotFound): secrets "observer-secrets" not found
```

**이 Secret이 없으면 Observer Pod과 PostgreSQL Pod 모두 시작 불가** (optional: false).

긴급 생성:

```bash
kubectl create secret generic observer-secrets \
  --from-literal=POSTGRES_USER=observer \
  --from-literal=POSTGRES_PASSWORD='<password>' \
  --from-literal=POSTGRES_DB=observer \
  --from-literal=DB_USER=observer \
  --from-literal=DB_PASSWORD='<password>' \
  --from-literal=PGHOST=postgres \
  --from-literal=PGPORT=5432 \
  --from-literal=PGDATABASE=observer \
  --from-literal=PGUSER=observer \
  --from-literal=PGPASSWORD='<password>' \
  --from-literal=KIS_APP_KEY='<key>' \
  --from-literal=KIS_APP_SECRET='<secret>' \
  --from-literal=KIS_HTS_ID='<id>' \
  -n observer-prod
```

### Step 3-4: observer-secrets 키 완전성 확인

```bash
kubectl get secret observer-secrets -n observer-prod -o json | \
  python3 -c "import sys,json; [print(k) for k in json.loads(sys.stdin.read())['data'].keys()]"
```

또는 (jq 사용):

```bash
kubectl get secret observer-secrets -n observer-prod -o json | jq -r '.data | keys[]'
```

#### 정상 결과 (최소 필수 키)

```
DB_PASSWORD
DB_USER
KIS_APP_KEY
KIS_APP_SECRET
KIS_HTS_ID
PGDATABASE
PGHOST
PGPASSWORD
PGPORT
PGUSER
POSTGRES_DB
POSTGRES_PASSWORD
POSTGRES_USER
```

#### 비정상 결과

누락된 키가 있으면 Pod 런타임 오류 발생. Secret 재생성 필요.

### Step 3-5: ghcr-secret 확인

```bash
kubectl get secret ghcr-secret -n observer-prod
```

정상: `TYPE = kubernetes.io/dockerconfigjson`

비정상: 없으면 ImagePullBackOff 발생.

---

## Step 4: ConfigMap 확인

### 명령어

```bash
kubectl get configmap observer-config -n observer-prod -o yaml
```

### 확인 항목

14개 data 키가 모두 존재하는지 확인:

```bash
kubectl get configmap observer-config -n observer-prod -o json | \
  python3 -c "import sys,json; [print(k) for k in sorted(json.loads(sys.stdin.read())['data'].keys())]"
```

#### 정상 결과

```
DB_HOST
DB_NAME
DB_PORT
KIS_TOKEN_CACHE_DIR
LOG_FORMAT
LOG_LEVEL
OBSERVER_CONFIG_DIR
OBSERVER_DATA_DIR
OBSERVER_LOG_DIR
OBSERVER_MAINTENANCE_LOG_DIR
OBSERVER_SNAPSHOT_DIR
OBSERVER_STANDALONE
OBSERVER_SYSTEM_LOG_DIR
PYTHONUNBUFFERED
SERVICE_PORT
```

#### 경로 교차 확인

```bash
# ConfigMap 경로 값이 Deployment volumeMount와 일치하는지 확인
kubectl get configmap observer-config -n observer-prod -o json | \
  python3 -c "
import sys,json
data = json.loads(sys.stdin.read())['data']
checks = {
    'OBSERVER_DATA_DIR': '/opt/platform/runtime/observer/data',
    'OBSERVER_LOG_DIR': '/opt/platform/runtime/observer/logs',
    'OBSERVER_CONFIG_DIR': '/opt/platform/runtime/observer/config',
    'OBSERVER_SNAPSHOT_DIR': '/opt/platform/runtime/observer/universe',
}
for k,v in checks.items():
    actual = data.get(k, 'MISSING')
    status = 'OK' if actual == v else 'MISMATCH'
    print(f'{status}: {k} = {actual} (expected: {v})')
"
```

---

## Step 5: Service 확인

### 명령어

```bash
kubectl get svc -n observer-prod
```

### 정상 결과

```
NAME               TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
observer           ClusterIP   10.x.x.x       <none>        8000/TCP   Xd
postgres           ClusterIP   10.x.x.x       <none>        5432/TCP   Xd
postgres-headless  ClusterIP   None            <none>        5432/TCP   Xd
```

### 비정상 결과

| 증상 | 조치 |
|------|------|
| Service 누락 | kustomization.yaml에서 서비스 리소스 확인 후 재적용 |
| PORT 불일치 | base YAML 확인: observer=8000, postgres=5432 |

---

## Step 6: Pod 상태 확인

### Step 6-1: Pod 목록

```bash
kubectl get pods -n observer-prod -o wide
```

#### 정상 결과 (Production: replicas=2)

```
NAME                        READY   STATUS    RESTARTS   AGE    NODE
observer-xxxxxxxxxx-xxxxx   1/1     Running   0          Xd     <node>
observer-xxxxxxxxxx-xxxxx   1/1     Running   0          Xd     <node>
postgres-0                  1/1     Running   0          Xd     <node>
```

#### 비정상 결과

| STATUS | 진단 | 조치 |
|--------|------|------|
| `CrashLoopBackOff` | `kubectl logs <pod> -n observer-prod --previous` | 로그에서 오류 원인 확인 |
| `ImagePullBackOff` | `kubectl describe pod <pod> -n observer-prod` | ghcr-secret 확인 (Step 3-5) |
| `Pending` | `kubectl describe pod <pod> -n observer-prod` | PVC Pending 또는 리소스 부족 |
| `ContainerCreating` (stuck) | `kubectl describe pod <pod> -n observer-prod` | 볼륨 마운트 문제 |
| READY = `0/1` | readinessProbe 실패 | /health 엔드포인트 확인 (Step 7) |

### Step 6-2: Pod 상세 이벤트

```bash
kubectl describe pod -l app=observer -n observer-prod | tail -30
kubectl describe pod -l app=postgres -n observer-prod | tail -30
```

정상: Events 섹션에 `Warning` 이벤트 없음

### Step 6-3: 컨테이너 로그

```bash
# Observer
kubectl logs -l app=observer -n observer-prod --tail=50

# PostgreSQL
kubectl logs -l app=postgres -n observer-prod --tail=30
```

정상:
- Observer: 애플리케이션 시작 로그, ERROR/CRITICAL 없음
- PostgreSQL: `database system is ready to accept connections`

### Step 6-4: 환경 변수 주입 확인

```bash
kubectl exec -it deploy/observer -n observer-prod -- env | sort
```

확인 항목:
- `OBSERVER_DATA_DIR`, `OBSERVER_LOG_DIR` 등 ConfigMap 키 존재
- `DB_PASSWORD`, `KIS_APP_KEY` 등 Secret 키 존재 (값 확인 불필요)
- `POD_NAME`, `TZ=Asia/Seoul` 존재

### Step 6-5: 볼륨 마운트 확인

```bash
kubectl exec -it deploy/observer -n observer-prod -- df -h | grep observer
```

#### 정상 결과

```
/dev/xxx    xxG   xxG   xxG   xx%  /opt/platform/runtime/observer/data
/dev/xxx    xxG   xxG   xxG   xx%  /opt/platform/runtime/observer/logs
/dev/xxx    xxG   xxG   xxG   xx%  /opt/platform/runtime/observer/universe
```

config은 hostPath이므로 별도 파일시스템이 아닐 수 있음.

### Step 6-6: 쓰기 권한 확인

```bash
# data 디렉토리
kubectl exec -it deploy/observer -n observer-prod -- \
  sh -c 'touch /opt/platform/runtime/observer/data/.write_test && echo "OK" && rm /opt/platform/runtime/observer/data/.write_test'

# logs 디렉토리
kubectl exec -it deploy/observer -n observer-prod -- \
  sh -c 'touch /opt/platform/runtime/observer/logs/.write_test && echo "OK" && rm /opt/platform/runtime/observer/logs/.write_test'
```

정상: `OK` 출력

비정상:
| 증상 | 원인 |
|------|------|
| `Permission denied` | fsGroup/runAsUser와 PVC 소유자 불일치 |
| `Read-only file system` | 해당 경로에 볼륨이 마운트되지 않음 |

---

## Step 7: Health Check

### Step 7-1: Pod 내부 헬스체크

```bash
kubectl exec -it deploy/observer -n observer-prod -- \
  python3 -c "import urllib.request; r=urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=5); print(r.status, r.read().decode())"
```

정상: `200 {"status": "ok", ...}`

### Step 7-2: Service 경유 헬스체크

```bash
kubectl run tmp-curl --rm -i -t --image=curlimages/curl -n observer-prod -- \
  curl -sf http://observer:8000/health
```

정상: HTTP 200, JSON 응답

### Step 7-3: Port-forward 헬스체크 (외부)

```bash
kubectl port-forward svc/observer 8000:8000 -n observer-prod &
curl -sf http://localhost:8000/health
kill %1
```

### Step 7-4: PostgreSQL 연결 확인

```bash
kubectl exec -it deploy/observer -n observer-prod -- \
  python3 -c "
import os, socket
s = socket.create_connection((os.getenv('DB_HOST','postgres'), int(os.getenv('DB_PORT','5432'))), timeout=5)
print('DB connection OK')
s.close()
"
```

정상: `DB connection OK`

비정상:
| 증상 | 원인 |
|------|------|
| `Connection refused` | postgres Pod 미실행 또는 Service 미생성 |
| `Name resolution failed` | postgres Service 미존재 |

---

## Step 8: 데이터 영속성 테스트

### Step 8-1: 재시작 전 데이터 기록

```bash
# JSONL 파일 목록 기록
kubectl exec -it deploy/observer -n observer-prod -- \
  find /opt/platform/runtime/observer/data -name "*.jsonl" 2>/dev/null | head -10

# 파일 수 기록
kubectl exec -it deploy/observer -n observer-prod -- \
  sh -c 'find /opt/platform/runtime/observer/data -name "*.jsonl" 2>/dev/null | wc -l'
```

### Step 8-2: Observer Pod 재시작

```bash
# Pod 삭제 (Deployment가 자동 재생성)
kubectl delete pod -l app=observer -n observer-prod
kubectl wait --for=condition=Ready pod -l app=observer -n observer-prod --timeout=300s
```

### Step 8-3: 재시작 후 데이터 확인

```bash
# 동일 명령어로 파일 목록 재확인
kubectl exec -it deploy/observer -n observer-prod -- \
  find /opt/platform/runtime/observer/data -name "*.jsonl" 2>/dev/null | head -10

kubectl exec -it deploy/observer -n observer-prod -- \
  sh -c 'find /opt/platform/runtime/observer/data -name "*.jsonl" 2>/dev/null | wc -l'
```

정상: 재시작 전후 파일 목록과 수 동일

비정상: 파일 누락 → PVC 마운트 오류 또는 emptyDir 사용 의심

### Step 8-4: PostgreSQL 데이터 영속성

```bash
# 재시작 전 테이블 수
kubectl exec -it postgres-0 -n observer-prod -- \
  psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT count(*) FROM pg_tables WHERE schemaname='public';"

# Pod 재시작
kubectl delete pod postgres-0 -n observer-prod
kubectl wait --for=condition=Ready pod postgres-0 -n observer-prod --timeout=300s

# 재시작 후 테이블 수 확인
kubectl exec -it postgres-0 -n observer-prod -- \
  psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT count(*) FROM pg_tables WHERE schemaname='public';"
```

정상: 테이블 수 동일

---

## Step 9: 24시간 안정성 모니터링

### Step 9-1: 기준선 기록

```bash
kubectl get pods -n observer-prod -o custom-columns=\
'NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,STARTED:.status.startTime'
```

타임스탬프와 RESTARTS 값 기록.

### Step 9-2: 24시간 후 확인

동일 명령어 실행.

| 확인 항목 | 정상 | 비정상 |
|-----------|------|--------|
| RESTARTS | 증가 없음 (0 유지) | 1 이상 증가 → 로그 확인 |
| STATUS | Running 유지 | 변경됨 → describe/events 확인 |

### Step 9-3: JSONL 생성 확인 (24시간 내)

```bash
kubectl exec -it deploy/observer -n observer-prod -- \
  find /opt/platform/runtime/observer/data -name "*.jsonl" -mmin -1440 2>/dev/null | wc -l
```

정상: 0보다 큰 값 (24시간 내 파일 생성됨)

---

## 안정성 검증 중단 기준

아래 조건 중 하나라도 해당되면, **검증을 중단하고 원인 분석을 우선** 수행한다. Phase 0 완료로 판정하지 않는다.

| # | 중단 조건 | 해당 Step | 조치 |
|---|----------|----------|------|
| 1 | `observer-secrets` Secret이 존재하지 않음 | Step 3-3 | 긴급 생성 절차 실행 후 Step 6부터 재검증 |
| 2 | 4개 PVC 중 하나라도 STATUS != `Bound` | Step 2 | `kubectl describe pvc`로 원인 파악. StorageClass/Provisioner 문제 해결 후 재검증 |
| 3 | Observer 또는 PostgreSQL Pod이 `CrashLoopBackOff` | Step 6 | 트러블슈팅 결정 트리 참조. 원인 해결 전까지 Step 7 이후 진행 불가 |
| 4 | Step 8 데이터 영속성 테스트에서 재시작 후 파일/테이블 손실 확인 | Step 8 | PVC 마운트 구조 재점검. emptyDir 사용 여부 확인 |
| 5 | Step 9에서 24시간 내 RESTARTS 3회 이상 증가 | Step 9 | `kubectl logs --previous`로 반복 크래시 원인 분석 |
| 6 | ConfigMap 경로 교차 확인에서 `MISMATCH` 발생 | Step 4 | PHASE_0_VERIFICATION_REPORT.md의 경로 계약 교차표 재검증 |

> **판정 원칙**: 중단 조건 해결 후, 해당 Step부터 재검증을 진행한다. 이전 Step의 결과가 유효하면 처음부터 재실행할 필요 없음.

---

## 빠른 상태 요약 (한 줄 명령어)

```bash
echo "=== PODS ===" && \
kubectl get pods -n observer-prod -o wide && \
echo "" && echo "=== PVC ===" && \
kubectl get pvc -n observer-prod && \
echo "" && echo "=== SECRETS ===" && \
kubectl get secrets -n observer-prod --no-headers | awk '{print $1, $2, $3}' && \
echo "" && echo "=== SERVICES ===" && \
kubectl get svc -n observer-prod && \
echo "" && echo "=== EVENTS (latest 5) ===" && \
kubectl get events -n observer-prod --sort-by='.lastTimestamp' 2>/dev/null | tail -5
```

---

## 트러블슈팅 결정 트리

### Pod CrashLoopBackOff

```
1. kubectl logs <pod> -n observer-prod --previous
   ├── PermissionError → fsGroup/볼륨 마운트 문제 (Step 6-6)
   ├── ModuleNotFoundError → 이미지 문제 (이미지 태그 확인)
   ├── DB connection error → Secret 누락 또는 postgres 미실행 (Step 3, 7-4)
   └── KeyError: 'KIS_APP_KEY' → observer-secrets에 API 키 누락 (Step 3-4)
```

### PVC Pending

```
1. kubectl describe pvc <name> -n observer-prod
   ├── "no persistent volumes available" → StorageClass 확인
   │   └── kubectl get sc → local-path 존재하는지 확인
   │       └── kubectl get pods -n kube-system -l app=local-path-provisioner
   └── "waiting for a volume to be created" → local-path-provisioner 로그 확인
```

### ImagePullBackOff

```
1. kubectl describe pod <pod> -n observer-prod | grep "Failed"
   ├── "unauthorized" → ghcr-secret 만료 또는 미생성 (Step 3-5)
   ├── "not found" → 이미지 태그 오류 (kustomization.yaml 확인)
   └── "timeout" → GHCR 네트워크 접근 문제
```

### observer-secrets Not Found

```
1. SealedSecret controller 동작 확인 (Step 3-1)
2. 중요: SealedSecret은 observer-secrets가 아닌 별도 이름의 Secret을 생성함
   (obs-db-secret, obs-kis-secret, obs-kiwoom-secret)
3. observer-secrets는 수동 생성 필요 → Step 3-3 긴급 생성 절차 참조
```
