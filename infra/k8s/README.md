# Kubernetes (K3s) Manifests – Observer

k3s/Kubernetes 환경에서 **Observer** 앱을 배포하기 위한 kustomize 기반 매니페스트입니다.

## 디렉터리 구조

```
k8s/
├── base/                         # Observer 전용 공통 리소스
│   ├── namespaces/observer.yaml
│   ├── deployments/observer.yaml # Port 8000, /health
│   ├── services/observer-svc.yaml
│   ├── configmaps/observer-config.yaml
│   ├── secrets/                  # kubectl create secret 가이드만 (값 없음)
│   ├── pvc/observer-db-pvc.yaml
│   ├── pvc/observer-logs-pvc.yaml
│   ├── ingress/observer-ingress.yaml  # 필요 시 주석 해제
│   └── kustomization.yaml
└── overlays/
    ├── production/
    │   ├── kustomization.yaml    # 이미지 태그: YYYYMMDD-HHMMSS
    │   └── patches/
    └── staging/
        ├── kustomization.yaml
        └── patches/
```

## 이미지 태그 정책

- **형식**: `ghcr.io/tawbury/observer:YYYYMMDD-HHMMSS` (KST 빌드 시점)
- **자동 생성**: `infra/_shared/scripts/build/generate_build_tag.sh`
- **배포 시 태그 지정**:
  ```bash
  IMAGE_TAG=$(infra/_shared/scripts/build/generate_build_tag.sh)
  infra/_shared/scripts/deploy/k8s-deploy.sh production "$IMAGE_TAG"
  ```
  또는 overlay에서 수동: `kustomize edit set image ghcr.io/tawbury/observer=ghcr.io/tawbury/observer:20260202-143512`

## 사용법

### 1. manifest 확인 (dry-run)

```bash
kustomize build overlays/staging
kustomize build overlays/production
```

### 2. 배포

```bash
kubectl apply -k overlays/staging
kubectl apply -k overlays/production
```

또는 스크립트:

```bash
./infra/_shared/scripts/deploy/k8s-deploy.sh production 20260202-143512
```

### 3. 롤아웃 / 롤백

```bash
kubectl rollout status deployment/observer -n observer-prod
kubectl rollout undo deployment/observer -n observer-prod
```

## GHCR 인증

```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USER \
  --docker-password=YOUR_GITHUB_PAT \
  --docker-email=your@email.com \
  -n observer
# production/staging namespace에도 동일하게 생성
```

## 환경별 요약

| 환경       | Namespace      | replicas | 이미지 태그        |
|-----------|----------------|----------|--------------------|
| staging   | observer-staging | 1      | YYYYMMDD-HHMMSS    |
| production| observer-prod  | 2        | YYYYMMDD-HHMMSS    |

## 관련 문서

- [PERSISTENCE_AND_HOSTPATH.md](../../docs/PERSISTENCE_AND_HOSTPATH.md) – DB/로그 호스트 매핑
- [KUBECTL_AND_ARGOCD_SETUP.md](../../docs/KUBECTL_AND_ARGOCD_SETUP.md) – 서버 kubectl/ArgoCD 설정
