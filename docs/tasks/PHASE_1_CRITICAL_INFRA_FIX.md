# Phase 1: Critical Infrastructure Fixes & Data Persistence

**우선순위**: CRITICAL
**예상 작업 시간**: 4-6시간
**작업자 역할**: DevOps Engineer / Platform Engineer
**시작 전 요구사항**: kubectl 접근 권한, ArgoCD 접근 권한, Git 커밋 권한

---

## 목적 (Objective)

Pod 재시작 시 JSONL 데이터 및 로그 파일 손실을 방지하고, 환경 변수 불일치로 인한 런타임 오류를 해결합니다.

### 해결할 문제
1. **observer-data-pvc 미마운트**: JSONL 수집 데이터가 Pod 재시작 시 휘발됨
2. **observer-logs-pvc 미마운트**: 로그 파일이 저장되지 않아 추적 불가
3. **ConfigMap 환경 변수 불완전**: 일부 경로 변수 누락으로 기본값으로 폴백

---

## Target Files

### 수정 대상 파일
```
d:\development\deployment\infra\k8s\base\
├── kustomization.yaml                    # PVC 리소스 활성화
├── deployments\observer.yaml             # hostPath → PVC 전환
└── configmaps\observer-config.yaml       # 누락 환경 변수 추가
```

### 참조 파일 (수정 불필요, 확인용)
```
d:\development\deployment\infra\k8s\base\pvc\
├── observer-data-pvc.yaml                # 이미 정의됨 (20Gi)
└── observer-logs-pvc.yaml                # 이미 정의됨 (5Gi)
```

---

## Action Steps

### Step 1: PVC 리소스 활성화

**파일**: `infra/k8s/base/kustomization.yaml`

**작업**: 주석 처리된 PVC 리소스를 활성화합니다.

**변경 내용**:
```yaml
# 변경 전
resources:
  - deployments/postgres.yaml
  - deployments/observer.yaml
  - services/postgres.yaml
  - services/observer-svc.yaml
  - configmaps/observer-config.yaml
  - pvc/observer-db-pvc.yaml
  # - pvc/observer-logs-pvc.yaml  # ← 주석 해제 필요
  # - pvc/observer-data-pvc.yaml  # ← 주석 해제 필요

# 변경 후
resources:
  - deployments/postgres.yaml
  - deployments/observer.yaml
  - services/postgres.yaml
  - services/observer-svc.yaml
  - configmaps/observer-config.yaml
  - pvc/observer-db-pvc.yaml
  - pvc/observer-logs-pvc.yaml
  - pvc/observer-data-pvc.yaml
```

**실행 명령**:
```bash
cd d:\development\deployment\infra\k8s\base
# 편집기로 kustomization.yaml 열기
code kustomization.yaml

# 또는 sed 명령으로 자동 수정 (Bash 환경)
sed -i 's/# - pvc\/observer-logs-pvc.yaml/- pvc\/observer-logs-pvc.yaml/' kustomization.yaml
sed -i 's/# - pvc\/observer-data-pvc.yaml/- pvc\/observer-data-pvc.yaml/' kustomization.yaml
```

---

### Step 2: Deployment 볼륨 마운트 전환 (hostPath → PVC)

**파일**: `infra/k8s/base/deployments/observer.yaml`

**작업**: volumes 섹션의 hostPath를 persistentVolumeClaim으로 교체합니다.

**변경 내용**:
```yaml
# 변경 전 (Lines 109-125)
volumes:
  - name: observer-data
    hostPath:
      path: /opt/platform/runtime/observer/data
      type: DirectoryOrCreate
  - name: observer-logs
    hostPath:
      path: /opt/platform/runtime/observer/logs
      type: DirectoryOrCreate
  - name: tmp-config-universe
    hostPath:
      path: /opt/platform/runtime/observer/universe
      type: DirectoryOrCreate
  - name: observer-config
    hostPath:
      path: /opt/platform/runtime/observer/config
      type: DirectoryOrCreate

# 변경 후
volumes:
  - name: observer-data
    persistentVolumeClaim:
      claimName: observer-data-pvc
  - name: observer-logs
    persistentVolumeClaim:
      claimName: observer-logs-pvc
  - name: tmp-config-universe
    emptyDir: {}  # 임시 데이터는 emptyDir 사용
  - name: observer-config
    hostPath:
      path: /opt/platform/runtime/observer/config
      type: DirectoryOrCreate
      # 또는 ConfigMap으로 관리 권장
```

**참고**: `observer-config`는 현재 hostPath 유지하되, 향후 ConfigMap + PVC 조합으로 전환 권장

**실행 명령**:
```bash
cd d:\development\deployment\infra\k8s\base\deployments
code observer.yaml

# 수동 편집 권장 (volumes 섹션 전체 교체)
```

---

### Step 3: ConfigMap 환경 변수 동기화

**파일**: `infra/k8s/base/configmaps/observer-config.yaml`

**작업**: 소스 코드에서 참조하는 환경 변수 중 누락된 항목을 추가합니다.

**변경 내용**:
```yaml
# 변경 전
apiVersion: v1
kind: ConfigMap
metadata:
  name: observer-config
data:
  LOG_LEVEL: "INFO"
  LOG_FORMAT: "json"
  SERVICE_PORT: "8000"
  DB_HOST: "postgres"
  DB_PORT: "5432"
  DB_NAME: "observer"
  OBSERVER_LOG_DIR: "/opt/platform/runtime/observer/logs"
  OBSERVER_DATA_DIR: "/opt/platform/runtime/observer/data"

# 변경 후 (추가된 항목)
apiVersion: v1
kind: ConfigMap
metadata:
  name: observer-config
data:
  LOG_LEVEL: "INFO"
  LOG_FORMAT: "json"
  SERVICE_PORT: "8000"
  DB_HOST: "postgres"
  DB_PORT: "5432"
  DB_NAME: "observer"
  # 기존 항목
  OBSERVER_LOG_DIR: "/opt/platform/runtime/observer/logs"
  OBSERVER_DATA_DIR: "/opt/platform/runtime/observer/data"
  # 추가된 항목
  OBSERVER_CONFIG_DIR: "/opt/platform/runtime/observer/config"
  OBSERVER_SYSTEM_LOG_DIR: "/opt/platform/runtime/observer/logs/system"
  OBSERVER_MAINTENANCE_LOG_DIR: "/opt/platform/runtime/observer/logs/maintenance"
  OBSERVER_SNAPSHOT_DIR: "/opt/platform/runtime/observer/universe"
  KIS_TOKEN_CACHE_DIR: "/opt/platform/runtime/observer/data/cache"
  # 운영 모드 설정
  OBSERVER_STANDALONE: "1"
  PYTHONUNBUFFERED: "1"
```

**실행 명령**:
```bash
cd d:\development\deployment\infra\k8s\base\configmaps
code observer-config.yaml

# 수동 편집으로 data 섹션에 항목 추가
```

---

### Step 4: Git Commit & Push

**작업**: 변경 사항을 deployment 레포지토리에 커밋합니다.

**실행 명령**:
```bash
cd d:\development\deployment

# 변경 파일 확인
git status

# 스테이징
git add infra/k8s/base/kustomization.yaml
git add infra/k8s/base/deployments/observer.yaml
git add infra/k8s/base/configmaps/observer-config.yaml

# 커밋
git commit -m "fix(k8s): enable PVC for observer data and logs

- Activate observer-data-pvc and observer-logs-pvc in kustomization
- Replace hostPath with PVC in observer deployment
- Add missing environment variables to ConfigMap

Refs: docs/SERVER_ANALYSIS_AND_REMEDIATION_PLAN.md Phase 1

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

# 푸시
git push origin master
```

---

### Step 5: ArgoCD Sync 확인

**작업**: ArgoCD가 변경 사항을 감지하고 자동 배포되는지 확인합니다.

**실행 명령** (ArgoCD CLI):
```bash
# ArgoCD 애플리케이션 상태 확인
argocd app get observer-prod

# 수동 동기화 (필요 시)
argocd app sync observer-prod

# 동기화 진행 상황 모니터링
argocd app wait observer-prod --health
```

**브라우저 확인**:
- ArgoCD UI 접속: `https://<argocd-server>`
- observer-prod 애플리케이션 선택
- Sync Status가 "Synced"인지 확인

---

## Verification (검증 체크리스트)

### 1. PVC 생성 확인

```bash
kubectl get pvc -n observer-prod

# 예상 출력:
# NAME                   STATUS   VOLUME                                     CAPACITY   ACCESS MODES
# observer-data-pvc      Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   20Gi       RWO
# observer-logs-pvc      Bound    pvc-yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy   5Gi        RWO
# observer-db-pvc        Bound    pvc-zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz   10Gi       RWO
```

**검증 기준**: 모든 PVC의 STATUS가 "Bound"여야 함

---

### 2. Pod 볼륨 마운트 확인

```bash
# Pod 이름 확인
kubectl get pods -n observer-prod

# Pod 내부 마운트 확인
kubectl exec -it -n observer-prod <observer-pod-name> -- df -h

# 예상 출력:
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/sda1        20G   1G   19G   5% /opt/platform/runtime/observer/data
# /dev/sdb1         5G 100M  4.9G   2% /opt/platform/runtime/observer/logs
```

**검증 기준**: `/opt/platform/runtime/observer/data`와 `/opt/platform/runtime/observer/logs`가 별도 파일시스템으로 마운트됨

---

### 3. 환경 변수 주입 확인

```bash
kubectl exec -it -n observer-prod <observer-pod-name> -- env | grep OBSERVER

# 예상 출력:
# OBSERVER_LOG_DIR=/opt/platform/runtime/observer/logs
# OBSERVER_DATA_DIR=/opt/platform/runtime/observer/data
# OBSERVER_CONFIG_DIR=/opt/platform/runtime/observer/config
# OBSERVER_SYSTEM_LOG_DIR=/opt/platform/runtime/observer/logs/system
# ...
```

**검증 기준**: 모든 `OBSERVER_*` 환경 변수가 설정되어 있어야 함

---

### 4. 데이터 영속성 테스트

**테스트 시나리오**: Pod를 재시작하고 데이터가 보존되는지 확인

```bash
# 1. 현재 데이터 파일 목록 확인
kubectl exec -it -n observer-prod <observer-pod-name> -- ls -la /opt/platform/runtime/observer/data/assets/

# 2. Pod 재시작
kubectl delete pod -n observer-prod <observer-pod-name>

# 3. 새 Pod가 Running 상태가 될 때까지 대기
kubectl wait --for=condition=Ready pod -l app=observer -n observer-prod --timeout=300s

# 4. 데이터 파일이 그대로 존재하는지 확인
kubectl exec -it -n observer-prod <new-pod-name> -- ls -la /opt/platform/runtime/observer/data/assets/
```

**검증 기준**: Pod 재시작 전후로 파일 목록이 동일해야 함

---

### 5. 애플리케이션 헬스 체크

```bash
# Pod 상태 확인
kubectl get pods -n observer-prod

# 로그 확인 (에러 없이 정상 시작되는지)
kubectl logs -n observer-prod <observer-pod-name> --tail=50

# 헬스 엔드포인트 확인
kubectl exec -it -n observer-prod <observer-pod-name> -- curl -f http://localhost:8000/health

# 예상 출력:
# {"status": "ok", "timestamp": "2026-02-04T10:00:00Z"}
```

**검증 기준**:
- Pod STATUS가 "Running"
- READY가 "1/1"
- `/health` 엔드포인트가 200 OK 반환

---

### 6. JSONL 파일 생성 테스트

**테스트 시나리오**: 실제로 JSONL 파일이 생성되는지 확인

```bash
# 1. 기존 JSONL 파일 개수 확인
kubectl exec -it -n observer-prod <observer-pod-name> -- \
  find /opt/platform/runtime/observer/data/assets/ -name "*.jsonl" | wc -l

# 2. 5분 대기 (데이터 수집 주기)
sleep 300

# 3. 새로운 JSONL 파일이 생성되었는지 확인
kubectl exec -it -n observer-pod-name> -- \
  find /opt/platform/runtime/observer/data/assets/ -name "*.jsonl" -mmin -5

# 4. 파일 내용 샘플 확인
kubectl exec -it -n observer-prod <observer-pod-name> -- \
  tail -n 5 /opt/platform/runtime/observer/data/assets/scalp_$(date +%Y%m%d)_*.jsonl
```

**검증 기준**: 새로운 JSONL 파일이 생성되고, 내용이 정상적으로 기록됨

---

## Rollback Plan (롤백 계획)

문제 발생 시 이전 상태로 복구하는 방법:

### 방법 1: Git Revert

```bash
cd d:\development\deployment

# 최근 커밋 확인
git log --oneline -5

# 해당 커밋 되돌리기
git revert <commit-hash>
git push origin master

# ArgoCD 자동 동기화 대기 (또는 수동 sync)
```

### 방법 2: ArgoCD History Rollback

```bash
# ArgoCD에서 이전 버전으로 롤백
argocd app rollback observer-prod <revision-number>
```

### 방법 3: 수동 Patch 적용

```bash
# PVC를 다시 주석 처리
kubectl patch -n observer-prod deployment observer --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/volumes/0", "value": {"name": "observer-data", "hostPath": {"path": "/opt/platform/runtime/observer/data", "type": "DirectoryOrCreate"}}}]'
```

---

## Troubleshooting (문제 해결)

### 문제 1: PVC가 Pending 상태로 멈춤

**증상**:
```bash
kubectl get pvc -n observer-prod
# STATUS가 "Pending"으로 표시됨
```

**원인**: StorageClass가 없거나, 프로비저너가 동작하지 않음

**해결책**:
```bash
# StorageClass 확인
kubectl get storageclass

# K3s 기본 StorageClass (local-path) 확인
kubectl get storageclass local-path -o yaml

# 없다면 수동 PV 생성
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: observer-data-pv
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-path
  hostPath:
    path: /home/ubuntu/data/observer/data
    type: DirectoryOrCreate
EOF
```

---

### 문제 2: Pod가 CrashLoopBackOff 상태

**증상**:
```bash
kubectl get pods -n observer-prod
# STATUS가 "CrashLoopBackOff"
```

**원인**: 볼륨 권한 문제 또는 환경 변수 오류

**해결책**:
```bash
# Pod 로그 확인
kubectl logs -n observer-prod <observer-pod-name>

# 권한 문제인 경우: fsGroup 확인
kubectl get deployment -n observer-prod observer -o yaml | grep fsGroup
# securityContext.fsGroup: 1000 설정되어 있는지 확인

# 환경 변수 문제인 경우: ConfigMap 재확인
kubectl get configmap -n observer-prod observer-config -o yaml
```

---

### 문제 3: 데이터가 여전히 손실됨

**증상**: Pod 재시작 후 파일이 사라짐

**원인**: PVC 마운트가 제대로 적용되지 않음

**확인 방법**:
```bash
# Deployment 스펙 확인
kubectl get deployment -n observer-prod observer -o yaml | grep -A 10 "volumes:"

# PVC가 올바르게 마운트되었는지 확인
kubectl describe pod -n observer-prod <observer-pod-name> | grep -A 20 "Mounts:"
```

**해결책**:
```bash
# Deployment 재배포
kubectl rollout restart deployment -n observer-prod observer

# 또는 수동 스케일 다운/업
kubectl scale deployment -n observer-prod observer --replicas=0
kubectl scale deployment -n observer-prod observer --replicas=1
```

---

## Success Criteria (성공 기준)

다음 모든 항목이 충족되면 Phase 1 완료:

- [ ] `observer-data-pvc`, `observer-logs-pvc`의 STATUS가 "Bound"
- [ ] observer Pod의 READY 상태가 "1/1"
- [ ] `/opt/platform/runtime/observer/data`와 `/opt/platform/runtime/observer/logs`가 PVC로 마운트됨
- [ ] ConfigMap에 누락된 환경 변수 8개가 모두 추가됨
- [ ] Pod 재시작 후 데이터 파일이 보존됨
- [ ] JSONL 파일이 정상적으로 생성됨
- [ ] `/health` 엔드포인트가 200 OK 반환

---

## Next Phase

Phase 1 완료 후 **Phase 2: Security & Database Reliability**로 진행합니다.

**Phase 2 주요 작업**:
- SealedSecrets 도입
- Postgres StatefulSet 전환

---

**문서 작성일**: 2026-02-04
**최종 업데이트**: 2026-02-04
