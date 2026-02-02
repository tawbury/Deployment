# 서버 측 kubectl 및 ArgoCD 설정 가이드

리팩토링된 K8s 매니페스트(Observer, kustomize)를 서버에서 적용하기 위한 **kubectl** 사용법과 **ArgoCD** 도입 시 설정을 정리한 문서입니다.

## 전제 조건

- K3s 클러스터가 설치되어 있음 (`infra/_shared/scripts/k3s/install.sh` 등 참고)
- 이미지: `ghcr.io/tawbury/observer` (태그: YYYYMMDD-HHMMSS)
- 네임스페이스: `observer`, `observer-staging`, `observer-prod` 등

---

## 1. kubectl 기반 배포

### 1.1 kubeconfig

- 서버에서 K3s를 설치했다면 보통 `/etc/rancher/k3s/k3s.yaml`을 복사해 사용합니다.
  ```bash
  mkdir -p ~/.kube
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
  sudo chown $(id -u):$(id -g) ~/.kube/config
  chmod 600 ~/.kube/config
  ```
- 원격 클러스터용이라면 해당 클러스터의 kubeconfig를 `KUBECONFIG` 또는 `~/.kube/config`에 설정하세요.

### 1.2 GHCR Secret 생성 (이미지 출입증)

Observer 이미지를 pull하려면 **observer 네임스페이스**에 레지스트리 Secret을 생성합니다. 모든 Secret·ConfigMap은 앱이 실행되는 동일 네임스페이스(observer) 내에서 관리합니다.

**observer 네임스페이스에서 ghcr-secret 생성 (base 배포 시):**

```bash
# observer 네임스페이스 생성 (없으면)
kubectl create namespace observer

# observer 네임스페이스 내에서 GHCR 이미지 출입증 생성
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USER \
  --docker-password=YOUR_GITHUB_PAT \
  --docker-email=your@email.com \
  -n observer
```

**overlay 사용 시 (observer-staging, observer-prod) 해당 네임스페이스에도 동일하게 생성:**

```bash
kubectl create namespace observer-prod 2>/dev/null || true
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USER \
  --docker-password=YOUR_GITHUB_PAT \
  --docker-email=your@email.com \
  -n observer-prod
```

### 1.3 Observer Secret (앱·DB·Postgres 초기화)

민감 정보는 Git에 넣지 않고, **observer 네임스페이스**에서만 생성합니다. Postgres Deployment 초기화와 Observer 앱·마이그레이션 Job이 같은 Secret을 참조합니다.

- **POSTGRES_USER**, **POSTGRES_PASSWORD**, **POSTGRES_DB**: Postgres 컨테이너 초기화용
- **PGHOST**, **PGPORT**, **PGDATABASE**, **PGUSER**, **PGPASSWORD**: Observer 앱 및 마이그레이션 Job 접속용 (PGHOST=postgres, 포트 5432)

```bash
# observer 네임스페이스 내에서 생성 (base 사용 시)
kubectl create secret generic observer-secrets \
  --from-literal=POSTGRES_USER=observer \
  --from-literal=POSTGRES_PASSWORD=your-db-password \
  --from-literal=POSTGRES_DB=observer \
  --from-literal=PGHOST=postgres \
  --from-literal=PGPORT=5432 \
  --from-literal=PGDATABASE=observer \
  --from-literal=PGUSER=observer \
  --from-literal=PGPASSWORD=your-db-password \
  --from-literal=DB_USER=observer \
  --from-literal=DB_PASSWORD=your-db-password \
  -n observer
```

overlay(observer-prod) 사용 시 네임스페이스만 변경:

```bash
kubectl create secret generic observer-secrets \
  --from-literal=POSTGRES_USER=observer \
  --from-literal=POSTGRES_PASSWORD=your-db-password \
  --from-literal=POSTGRES_DB=observer \
  --from-literal=PGHOST=postgres \
  --from-literal=PGPORT=5432 \
  --from-literal=PGDATABASE=observer \
  --from-literal=PGUSER=observer \
  --from-literal=PGPASSWORD=your-db-password \
  --from-literal=DB_USER=observer \
  --from-literal=DB_PASSWORD=your-db-password \
  -n observer-prod
```

가이드: `infra/k8s/base/secrets/observer-secrets.yaml` 주석 참고. 앱 Config가 **DB_USER**, **DB_PASSWORD**를 읽으면 위와 같이 Secret에 포함해야 합니다.

### 1.4 마이그레이션 ConfigMap 및 Job (선택)

DB 마이그레이션을 한 번 실행할 때:

```bash
# 레포 클론 후 migrations 디렉터리로 이동
cd infra/_shared/migrations
kubectl create configmap observer-migrations \
  --from-file=001_create_scalp_tables.sql \
  --from-file=002_create_swing_tables.sql \
  --from-file=003_create_portfolio_tables.sql \
  --from-file=004_create_analysis_tables.sql \
  -n observer-prod
# job-template.yaml 의 namespace 를 observer-prod 로 수정 후
kubectl apply -f job-template.yaml
kubectl wait --for=condition=complete job/observer-migrate -n observer-prod --timeout=300s
```

### 1.5 매니페스트 배포

레포 루트에서:

```bash
# 스테이징
kubectl apply -k infra/k8s/overlays/staging

# 프로덕션 (이미지 태그는 overlay의 kustomization.yaml 에서 수정)
kubectl apply -k infra/k8s/overlays/production
```

또는 배포 스크립트 사용 (이미지 태그 자동 반영):

```bash
IMAGE_TAG=20260202-143512
infra/_shared/scripts/deploy/k8s-deploy.sh production "$IMAGE_TAG"
```

### 1.6 상태 확인 및 롤백

```bash
kubectl get pods,svc -n observer-prod -l app=observer
kubectl rollout status deployment/observer -n observer-prod
kubectl rollout undo deployment/observer -n observer-prod
```

---

## 2. ArgoCD 설정 (선택)

GitOps로 동기화하려면 ArgoCD를 설치한 뒤, 이 레포의 overlay 경로를 Application으로 등록합니다.

### 2.1 ArgoCD 설치 (K3s)

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s
# 초기 admin 비밀번호
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 2.2 Observer Application 등록

레포 URL과 브랜치, overlay 경로를 실제 값으로 바꿉니다.

```yaml
# argocd/observer-production.yaml 예시
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: observer-production
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/tawbury/deployment.git
    targetRevision: main
    path: infra/k8s/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: observer-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

적용:

```bash
kubectl apply -f argocd/observer-production.yaml
```

### 2.3 이미지 태그 업데이트 (ArgoCD 사용 시)

- overlay의 `kustomization.yaml`에서 `images[].newTag`를 원하는 YYYYMMDD-HHMMSS로 바꾼 뒤 Git에 push하면, ArgoCD가 자동으로 동기화합니다.
- 또는 CI에서 이미지 빌드 후 해당 파일만 수정해 커밋하는 방식으로 자동화할 수 있습니다.

### 2.4 마이그레이션 Pre-Sync Hook

DB 마이그레이션을 앱 배포 전에 실행하려면 `infra/_shared/migrations/job-template.yaml`의 ArgoCD hook 주석을 해제하고, 해당 Job을 Application에 포함할 리소스로 두거나 별도 Application으로 관리하세요.

---

## 3. 체크리스트 요약

| 단계 | 내용 |
|------|------|
| 1 | kubeconfig 설정, `kubectl get nodes` 확인 |
| 2 | 네임스페이스 생성 (또는 kustomize가 CreateNamespace로 생성) |
| 3 | `ghcr-secret`, `observer-secrets` 생성 |
| 4 | (선택) 마이그레이션 ConfigMap + Job 실행 |
| 5 | `kubectl apply -k infra/k8s/overlays/production` 또는 ArgoCD Application 등록 |
| 6 | `kubectl rollout status deployment/observer -n observer-prod` 로 완료 확인 |

영속 볼륨(호스트 경로) 설정은 [PERSISTENCE_AND_HOSTPATH.md](PERSISTENCE_AND_HOSTPATH.md)를 참고하세요.
