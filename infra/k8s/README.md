# Kubernetes Manifests

k3s/Kubernetes 환경에서 워크로드를 배포하기 위한 kustomize 기반 manifests입니다.

## 디렉터리 구조

```
k8s/
├── base/                     # 모든 환경에서 공통으로 사용하는 manifests
│   ├── namespaces/           # Namespace 정의
│   ├── deployments/          # Deployment 정의
│   ├── services/             # Service 정의
│   ├── configmaps/           # ConfigMap 정의
│   ├── secrets/              # Secret 템플릿 (실제 값은 SealedSecrets)
│   ├── pvc/                  # PersistentVolumeClaim 정의
│   ├── ingress/              # Ingress 정의
│   └── kustomization.yaml    # base 리소스 조합
└── overlays/                 # 환경별 오버레이
    ├── production/           # 프로덕션 환경
    │   ├── kustomization.yaml
    │   └── patches/
    │       ├── replicas.yaml
    │       └── resources.yaml
    └── staging/              # 스테이징 환경
        ├── kustomization.yaml
        └── patches/
```

## 사용법

### 1. 로컬에서 manifest 확인 (dry-run)

```bash
# 스테이징 환경 manifest 확인
kustomize build overlays/staging

# 프로덕션 환경 manifest 확인
kustomize build overlays/production
```

### 2. 배포

```bash
# 스테이징 환경 배포
kubectl apply -k overlays/staging

# 프로덕션 환경 배포
kubectl apply -k overlays/production
```

### 3. 이미지 태그 업데이트

```bash
cd overlays/production
kustomize edit set image ghcr.io/org/app=ghcr.io/org/app:v1.2.3
```

### 4. 롤아웃 상태 확인

```bash
kubectl rollout status deployment/app -n prj-01-prod
```

### 5. 롤백

```bash
kubectl rollout undo deployment/app -n prj-01-prod
```

## GHCR 인증 설정

Private 레포에서 이미지를 pull하려면 Secret을 생성해야 합니다:

```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=$GITHUB_USERNAME \
  --docker-password=$GITHUB_PAT \
  --docker-email=$GITHUB_EMAIL \
  -n prj-01
```

## 환경별 설정

| 환경 | Namespace | replicas | CPU limit | Memory limit |
|------|-----------|----------|-----------|--------------|
| staging | prj-01-staging | 1 | 250m | 512Mi |
| production | prj-01-prod | 3 | 1000m | 2Gi |

## 관련 문서

- [Deploy Architecture](../../docs/arch/deploy_architecture.md)
- [Deploy Sub Architecture](../../docs/arch/deploy_sub_architecture.md)
