# Phase 2: Security & Database Reliability

**우선순위**: HIGH
**예상 작업 시간**: 6-8시간
**작업자 역할**: Platform Engineer / Database Administrator
**선행 조건**: Phase 1 완료, kubectl 관리자 권한, Helm 설치

---

## 목적 (Objective)

Secret 관리를 자동화하고 PostgreSQL의 안정성을 확보하여 프로덕션 환경의 보안과 데이터 일관성을 강화합니다.

### 해결할 문제
1. **Secret 수동 관리**: `kubectl create secret` 수동 실행으로 인한 휴먼 에러 위험
2. **Secret 버전 관리 부재**: Secret 변경 이력 추적 불가
3. **Postgres Deployment 한계**: StatefulSet이 아닌 Deployment 사용으로 데이터 일관성 위험

---

## Target Files

### 새로 생성할 파일
```
d:\development\deployment\infra\k8s\base\
├── sealed-secrets\
│   ├── observer-sealed-secrets.yaml      # SealedSecret 리소스
│   └── README.md                         # 사용 가이드
├── statefulsets\
│   └── postgres.yaml                     # StatefulSet 매니페스트
└── kustomization.yaml                    # 리소스 참조 업데이트
```

### 수정 대상 파일
```
d:\development\deployment\infra\k8s\base\
├── kustomization.yaml                    # StatefulSet 추가, Deployment 제거
└── secrets\observer-secrets.yaml         # 참조용 유지 (SealedSecret으로 전환)
```

---

## Part A: SealedSecrets 도입

### Step A1: SealedSecrets 컨트롤러 설치

**작업**: Kubernetes 클러스터에 SealedSecrets 컨트롤러를 설치합니다.

**실행 명령** (Helm 사용):
```bash
# Helm 레포지토리 추가
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

# sealed-secrets 네임스페이스 생성
kubectl create namespace sealed-secrets

# 컨트롤러 설치
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace sealed-secrets \
  --version 2.15.0 \
  --set image.tag=v0.26.0
```

**또는 kubectl 직접 적용**:
```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/controller.yaml
```

**검증**:
```bash
# 컨트롤러 Pod 확인
kubectl get pods -n sealed-secrets

# 예상 출력:
# NAME                                         READY   STATUS    RESTARTS   AGE
# sealed-secrets-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
```

---

### Step A2: kubeseal CLI 설치

**작업**: 로컬에서 Secret을 암호화하는 CLI 도구를 설치합니다.

**설치 명령** (Windows):
```powershell
# Chocolatey 사용
choco install kubeseal

# 또는 수동 다운로드
$url = "https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/kubeseal-0.26.0-windows-amd64.tar.gz"
Invoke-WebRequest -Uri $url -OutFile kubeseal.tar.gz
tar -xzf kubeseal.tar.gz
Move-Item kubeseal.exe C:\Windows\System32\
```

**설치 명령** (Linux/macOS):
```bash
# Homebrew 사용
brew install kubeseal

# 또는 직접 다운로드
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/kubeseal-0.26.0-linux-amd64.tar.gz
tar -xzf kubeseal-0.26.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

**검증**:
```bash
kubeseal --version
# 예상 출력: kubeseal version: v0.26.0
```

---

### Step A3: 기존 Secret을 SealedSecret으로 변환

**작업**: 현재 수동으로 생성한 Secret을 SealedSecret 형식으로 암호화합니다.

**실행 명령**:

```bash
cd d:\development\deployment\infra\k8s\base\secrets

# 1. 현재 Secret을 YAML로 추출 (이미 생성되어 있다면)
kubectl get secret observer-secrets -n observer-prod -o yaml > observer-secrets-plain.yaml

# 또는 새로 생성할 경우:
kubectl create secret generic observer-secrets \
  --from-literal=POSTGRES_USER=observer \
  --from-literal=POSTGRES_PASSWORD='<strong-password>' \
  --from-literal=DB_USER=observer \
  --from-literal=DB_PASSWORD='<strong-password>' \
  --from-literal=KIS_APP_KEY='<your-kis-app-key>' \
  --from-literal=KIS_APP_SECRET='<your-kis-app-secret>' \
  --from-literal=KIS_HTS_ID='<your-hts-id>' \
  --dry-run=client -o yaml > observer-secrets-plain.yaml

# 2. SealedSecret으로 암호화
kubeseal --format yaml \
  --controller-name sealed-secrets \
  --controller-namespace sealed-secrets \
  < observer-secrets-plain.yaml \
  > ../sealed-secrets/observer-sealed-secrets.yaml

# 3. 평문 Secret 삭제 (보안)
rm observer-secrets-plain.yaml
```

**생성된 SealedSecret 예시** (`infra/k8s/base/sealed-secrets/observer-sealed-secrets.yaml`):
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: observer-secrets
  namespace: observer-prod
spec:
  encryptedData:
    POSTGRES_USER: AgBY3J9X8z...  # 암호화된 값
    POSTGRES_PASSWORD: AgBY3J9X8z...
    DB_USER: AgBY3J9X8z...
    DB_PASSWORD: AgBY3J9X8z...
    KIS_APP_KEY: AgBY3J9X8z...
    KIS_APP_SECRET: AgBY3J9X8z...
    KIS_HTS_ID: AgBY3J9X8z...
  template:
    metadata:
      name: observer-secrets
      namespace: observer-prod
    type: Opaque
```

---

### Step A4: kustomization.yaml 업데이트

**파일**: `infra/k8s/base/kustomization.yaml`

**작업**: SealedSecret 리소스를 추가합니다.

**변경 내용**:
```yaml
# 추가 항목
resources:
  # ... (기존 리소스들)
  - sealed-secrets/observer-sealed-secrets.yaml
  # secrets/observer-secrets.yaml는 제거 또는 주석 처리 (SealedSecret이 자동 생성)
```

---

### Step A5: SealedSecret 사용 가이드 작성

**파일**: `infra/k8s/base/sealed-secrets/README.md`

**내용**:
```markdown
# SealedSecrets 사용 가이드

## Secret 값 변경 방법

1. 평문 Secret 생성:
kubectl create secret generic observer-secrets \
  --from-literal=NEW_KEY='new-value' \
  --dry-run=client -o yaml > temp-secret.yaml

2. SealedSecret으로 암호화:
kubeseal --format yaml \
  < temp-secret.yaml \
  > observer-sealed-secrets.yaml

3. Git 커밋 및 푸시:
git add observer-sealed-secrets.yaml
git commit -m "chore: update observer secrets"
git push origin master

4. ArgoCD 자동 동기화 대기

## 백업 및 복구

### 공개 키 백업
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-key-backup.yaml

### 복구 시
kubectl apply -f sealed-secrets-key-backup.yaml
kubectl delete pod -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets
```

---

## Part B: Postgres StatefulSet 전환

### Step B1: StatefulSet 매니페스트 작성

**파일**: `infra/k8s/base/statefulsets/postgres.yaml`

**내용**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-headless
  labels:
    app: postgres
spec:
  clusterIP: None  # Headless Service
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
  selector:
    app: postgres

---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  labels:
    app: postgres
    app.kubernetes.io/name: postgres
    app.kubernetes.io/part-of: tawbury-deployment
spec:
  serviceName: postgres-headless
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15-alpine
          ports:
            - name: postgres
              containerPort: 5432
          envFrom:
            - secretRef:
                name: observer-secrets
          env:
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          livenessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - pg_isready -U ${POSTGRES_USER:-postgres}
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
          readinessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - pg_isready -U ${POSTGRES_USER:-postgres}
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
      securityContext:
        fsGroup: 999  # postgres 그룹
  volumeClaimTemplates:
    - metadata:
        name: postgres-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: local-path
        resources:
          requests:
            storage: 10Gi
```

---

### Step B2: 기존 Deployment 백업

**작업**: 기존 Postgres Deployment를 백업합니다.

**실행 명령**:
```bash
cd d:\development\deployment\infra\k8s\base

# 백업 디렉토리 생성
mkdir -p _backup/2026-02-04

# Deployment 백업
cp deployments/postgres.yaml _backup/2026-02-04/postgres-deployment.yaml
```

---

### Step B3: 데이터 마이그레이션 계획

**주의**: StatefulSet으로 전환 시 기존 PVC를 재사용하거나 데이터를 마이그레이션해야 합니다.

**옵션 A: 기존 PVC 재사용** (권장)

1. 기존 Deployment 스케일 다운:
```bash
kubectl scale deployment postgres -n observer-prod --replicas=0
```

2. 기존 PVC 이름 확인:
```bash
kubectl get pvc -n observer-prod | grep postgres
# observer-db-pvc
```

3. StatefulSet의 volumeClaimTemplates 대신 volumes로 기존 PVC 직접 마운트:
```yaml
# statefulsets/postgres.yaml 수정
spec:
  template:
    spec:
      volumes:
        - name: postgres-data
          persistentVolumeClaim:
            claimName: observer-db-pvc  # 기존 PVC 재사용
      containers:
        - name: postgres
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
  # volumeClaimTemplates는 제거
```

**옵션 B: 데이터 백업 후 신규 PVC 생성**

1. 데이터 백업:
```bash
kubectl exec -it -n observer-prod <postgres-pod-name> -- \
  pg_dumpall -U postgres > postgres-backup-$(date +%Y%m%d).sql
```

2. StatefulSet 배포 (신규 PVC 자동 생성)

3. 데이터 복원:
```bash
kubectl cp postgres-backup-20260204.sql observer-prod/<new-postgres-pod>:/tmp/
kubectl exec -it -n observer-prod <new-postgres-pod> -- \
  psql -U postgres < /tmp/postgres-backup-20260204.sql
```

---

### Step B4: kustomization.yaml 업데이트

**파일**: `infra/k8s/base/kustomization.yaml`

**변경 내용**:
```yaml
# 변경 전
resources:
  - deployments/postgres.yaml  # ← 제거
  - deployments/observer.yaml
  # ...

# 변경 후
resources:
  - statefulsets/postgres.yaml  # ← 추가
  - deployments/observer.yaml
  # ...
```

---

### Step B5: StatefulSet 배포

**실행 명령**:
```bash
cd d:\development\deployment

# Git 커밋
git add infra/k8s/base/statefulsets/postgres.yaml
git add infra/k8s/base/kustomization.yaml
git commit -m "feat(k8s): migrate postgres from Deployment to StatefulSet

- Add StatefulSet manifest with volumeClaimTemplates
- Replace Deployment reference in kustomization
- Add Headless Service for StatefulSet

Refs: docs/SERVER_ANALYSIS_AND_REMEDIATION_PLAN.md Phase 2

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git push origin master
```

---

## Verification (검증 체크리스트)

### 1. SealedSecrets 컨트롤러 상태

```bash
kubectl get pods -n sealed-secrets

# 예상 출력:
# NAME                                         READY   STATUS    RESTARTS   AGE
# sealed-secrets-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          5m
```

---

### 2. SealedSecret이 Secret으로 복호화되었는지 확인

```bash
# SealedSecret 리소스 확인
kubectl get sealedsecrets -n observer-prod

# 생성된 Secret 확인
kubectl get secret observer-secrets -n observer-prod

# Secret 값 확인 (base64 디코딩)
kubectl get secret observer-secrets -n observer-prod -o jsonpath='{.data.POSTGRES_USER}' | base64 -d
# 예상 출력: observer
```

---

### 3. StatefulSet 상태 확인

```bash
kubectl get statefulset -n observer-prod

# 예상 출력:
# NAME       READY   AGE
# postgres   1/1     2m

# Pod 이름 확인 (StatefulSet은 고정 이름 사용)
kubectl get pods -n observer-prod -l app=postgres
# 예상 출력: postgres-0
```

---

### 4. PVC 자동 생성 확인 (volumeClaimTemplates 사용 시)

```bash
kubectl get pvc -n observer-prod

# 예상 출력:
# NAME                    STATUS   VOLUME   CAPACITY   ACCESS MODES
# postgres-data-postgres-0   Bound    pvc-xxx  10Gi       RWO
```

---

### 5. 데이터베이스 연결 테스트

```bash
# Observer Pod에서 DB 연결 테스트
kubectl exec -it -n observer-prod <observer-pod-name> -- \
  psql -h postgres -U observer -d observer -c "SELECT version();"

# 예상 출력: PostgreSQL 15.x ...
```

---

### 6. 데이터 무결성 검증

```bash
# 테이블 목록 확인
kubectl exec -it -n observer-prod postgres-0 -- \
  psql -U observer -d observer -c "\dt"

# 레코드 수 확인 (주요 테이블)
kubectl exec -it -n observer-prod postgres-0 -- \
  psql -U observer -d observer -c "SELECT COUNT(*) FROM scalp_ticks;"
```

---

## Rollback Plan (롤백 계획)

### SealedSecret 롤백

```bash
# 1. SealedSecret 삭제
kubectl delete sealedsecret observer-secrets -n observer-prod

# 2. 기존 방식으로 Secret 수동 생성
kubectl create secret generic observer-secrets \
  --from-literal=POSTGRES_USER=observer \
  --from-literal=POSTGRES_PASSWORD='<password>' \
  -n observer-prod

# 3. Git에서 SealedSecret 제거
git revert <sealed-secret-commit-hash>
git push origin master
```

### StatefulSet 롤백

```bash
# 1. StatefulSet 스케일 다운
kubectl scale statefulset postgres -n observer-prod --replicas=0

# 2. 기존 Deployment 복원
kubectl apply -f infra/k8s/base/_backup/2026-02-04/postgres-deployment.yaml

# 3. kustomization.yaml 원복
git revert <statefulset-commit-hash>
git push origin master
```

---

## Troubleshooting (문제 해결)

### 문제 1: SealedSecret이 Secret으로 복호화되지 않음

**증상**:
```bash
kubectl get secret observer-secrets -n observer-prod
# Error from server (NotFound): secrets "observer-secrets" not found
```

**원인**: SealedSecrets 컨트롤러가 동작하지 않거나, 네임스페이스 불일치

**해결책**:
```bash
# 컨트롤러 로그 확인
kubectl logs -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets

# SealedSecret 리소스 상태 확인
kubectl describe sealedsecret observer-secrets -n observer-prod

# 네임스페이스 확인 (SealedSecret과 Secret이 동일해야 함)
```

---

### 문제 2: StatefulSet Pod가 Pending 상태

**증상**:
```bash
kubectl get pods -n observer-prod
# postgres-0   0/1   Pending
```

**원인**: PVC가 Bound되지 않음

**해결책**:
```bash
# PVC 상태 확인
kubectl get pvc -n observer-prod

# PVC 이벤트 확인
kubectl describe pvc postgres-data-postgres-0 -n observer-prod

# StorageClass 확인
kubectl get storageclass
```

---

### 문제 3: Postgres 데이터 손실

**증상**: 기존 데이터가 없어짐

**원인**: 기존 PVC가 아닌 신규 PVC가 생성됨

**해결책**:
```bash
# 1. StatefulSet 스케일 다운
kubectl scale statefulset postgres -n observer-prod --replicas=0

# 2. volumeClaimTemplates 대신 기존 PVC 직접 마운트
# (Step B3의 옵션 A 참조)

# 3. StatefulSet 재배포
```

---

## Success Criteria (성공 기준)

다음 모든 항목이 충족되면 Phase 2 완료:

- [ ] SealedSecrets 컨트롤러가 Running 상태
- [ ] `observer-sealed-secrets.yaml`이 Git에 커밋됨
- [ ] SealedSecret이 Secret으로 자동 복호화됨
- [ ] StatefulSet `postgres`의 READY 상태가 "1/1"
- [ ] PVC `postgres-data-postgres-0`가 Bound 상태 (또는 기존 PVC 재사용)
- [ ] Observer가 Postgres에 정상 연결됨
- [ ] 기존 데이터베이스 테이블이 그대로 존재함

---

## Next Phase

Phase 2 완료 후 **Phase 3: Optimization & Monitoring**으로 진행합니다.

**Phase 3 주요 작업**:
- KIS 토큰 캐싱 구현
- Prometheus ServiceMonitor 추가
- Grafana 대시보드 구축

---

**문서 작성일**: 2026-02-04
**최종 업데이트**: 2026-02-04
