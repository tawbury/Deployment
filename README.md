# Kubernetes K3s Deployment 프로젝트

이 프로젝트는 Kubernetes(K3s) 및 컨테이너 기반 인프라 구축을 위한 통합 관리 저장소입니다. ArgoCD를 통한 GitOps 방식의 멀티 클러스터 배포와 모니터링 스택을 포함하고 있습니다.

## 멀티 클러스터 구조

```
                    ┌─────────────────────────────────┐
                    │  GitHub (Deployment 레포)        │
                    │  clusters/oci-1/* , clusters/oci-2/* │
                    └──────────┬──────────────────────┘
                               │ Git 감시
                    ┌──────────▼──────────────────────┐
                    │  ArgoCD (OCI #1)                 │
                    │  infra/argocd/applications/      │
                    └──┬───────────────────────┬──────┘
                       │                       │
          로컬 배포    │                       │  원격 배포
                       ▼                       ▼
          ┌────────────────────┐   ┌────────────────────┐
          │  OCI #1 (K3s)      │   │  OCI #2 (K3s)      │
          │  ├ QTS             │   │  └ n8n              │
          │  ├ Observer        │   │    (모니터링/자동화)  │
          │  └ PostgreSQL      │   │                     │
          └────────────────────┘   └────────────────────┘
                                            │
                                   감시자 ↔ 감시 대상 분리
```

## 📋 목차

- [프로젝트 개요](#프로젝트-개요)
- [프로젝트 구조](#프로젝트-구조)
- [클러스터별 배포](#클러스터별-배포)
- [빠른 시작](#빠른-시작)
- [주요 구성 요소](#주요-구성-요소)
- [비상 수동 배포](#비상-수동-배포)
- [설정 체크리스트](#설정-체크리스트)

## 프로젝트 개요

이 저장소는 다음을 제공합니다:

- **멀티 클러스터 GitOps**: ArgoCD를 활용한 복수 K3s 클러스터 선언적 배포 관리
- **감시자 분리 원칙**: 감시자(n8n)와 감시 대상(QTS/Observer)을 별도 서버에서 운영
- **다중 환경 지원**: `base/overlays` 구조 및 환경별 values 파일로 환경 관리
- **모니터링 스택**: Prometheus, Grafana, Alertmanager 통합
- **자동화 허브**: n8n을 통한 실시간 모니터링, 장애 알림, AI 연동 자동 복구
- **데이터베이스 인프라**: PostgreSQL (StatefulSet) 및 PVC 관리

## 프로젝트 구조

```
Deployment/
├── clusters/                       # 멀티 클러스터 Helm Charts
│   ├── oci-1/                      # OCI #1 서버 (QTS 클러스터)
│   │   ├── qts/                    # QTS Helm Chart
│   │   └── observer/               # Observer Helm Chart
│   ├── oci-2/                      # OCI #2 서버 (n8n 클러스터)
│   │   └── n8n/helm-charts/        # n8n Helm Chart
│   └── gcp/                        # GCP 서버 (향후 헬스체크용)
│
├── infra/                          # 인프라 설정 (K8s & Shared)
│   ├── argocd/                     # ArgoCD 설정
│   │   ├── applications/           # ArgoCD Application 매니페스트
│   │   │   ├── observer-prod.yaml  # Observer → clusters/oci-1/observer
│   │   │   ├── qts-prod.yaml      # QTS → clusters/oci-1/qts
│   │   │   ├── oci-2-n8n.yaml     # n8n → clusters/oci-2/n8n/helm-charts
│   │   │   └── project.yaml       # AppProject 정의
│   │   └── root-app.yaml          # App of Apps (applications/ 스캔)
│   ├── k8s/                        # Kubernetes 매니페스트 (Kustomize)
│   │   ├── base/                   # 기본 리소스 정의
│   │   └── overlays/               # 환경별 오버라이드
│   └── _shared/                    # 공유 리소스 (스크립트, 마이그레이션, 모니터링)
│
├── .github/workflows/              # CI/CD 자동화
│   ├── argocd-sync.yml             # ArgoCD 자동 동기화
│   ├── helm-validate.yml           # Helm PR 검증
│   ├── deploy.yaml                 # 비상 수동 배포 (n8n)
│   └── cd-deploy.yml               # CD 배포
│
├── docs/                           # 문서
│   └── multi-cluster-setup.md      # 멀티 클러스터 설정 가이드
├── ops/                            # 운영 스크립트 (SealedSecrets 등)
└── tests/                          # 인프라 테스트
```

## 클러스터별 배포

### OCI #1: QTS + Observer (운영 중)

ArgoCD가 자동으로 관리합니다. `clusters/oci-1/` 하위 Helm Chart 변경 시 자동 동기화됩니다.

```bash
# 상태 확인
argocd app get observer-prod
argocd app get qts-prod
```

### OCI #2: n8n (신규)

```bash
# 운영 환경 (OCI #2 ARM64)
helm upgrade --install n8n ./clusters/oci-2/n8n/helm-charts \
  -n n8n --create-namespace \
  -f ./clusters/oci-2/n8n/helm-charts/values.yaml \
  -f ./clusters/oci-2/n8n/helm-charts/values.oci.yaml \
  --set n8n.encryptionKey=<KEY>

# GCP 스테이징
helm upgrade --install n8n ./clusters/oci-2/n8n/helm-charts \
  -n n8n --create-namespace \
  -f ./clusters/oci-2/n8n/helm-charts/values.yaml \
  -f ./clusters/oci-2/n8n/helm-charts/values.gcp.yaml \
  --set n8n.encryptionKey=<KEY>
```

## 빠른 시작

### 1. 사전 요구사항

- **Kubernetes**: K3s 또는 표준 K8s 클러스터
- **Tools**: `kubectl`, `helm`, `kustomize`
- **GitOps**: ArgoCD (권장)

### 2. Kustomize를 이용한 로컬 빌드 테스트

```bash
# base 리소스 빌드 확인
kubectl kustomize infra/k8s/base

# production 오버레이 빌드 확인
kubectl kustomize infra/k8s/overlays/production
```

### 3. ArgoCD를 통한 배포

이 저장소를 ArgoCD의 소스로 등록합니다. root-app이 `infra/argocd/applications/` 디렉토리를 스캔하여 모든 앱을 자동 관리합니다.

멀티 클러스터 설정은 [docs/multi-cluster-setup.md](docs/multi-cluster-setup.md)를 참조하십시오.

## 주요 구성 요소

### Helm Charts (`clusters/`)
- **clusters/oci-1/qts/**: QTS 트레이딩 엔진
- **clusters/oci-1/observer/**: 시장 데이터 수집기
- **clusters/oci-2/n8n/helm-charts/**: 워크플로우 자동화 (모니터링, 장애 알림)

### Kubernetes 인프라 (`infra/k8s/`)
- **Base**: 모든 환경에서 공통적으로 사용되는 리소스의 원형
- **Overlays**: 특정 환경에 맞게 리소스 조정

### 데이터 관리
- **PVC**: `/opt/platform/runtime/` 경로의 영구 저장소 관리
- **Sealed Secrets**: Git 저장소에 안전하게 시크릿을 저장 (`kubeseal`)

## 비상 수동 배포

GitHub Actions의 `Emergency Deploy (n8n)` 워크플로우를 통해 수동 배포가 가능합니다.

**사용법**: Actions 탭 → Emergency Deploy (n8n) → Run workflow

| 파라미터 | 옵션 | 설명 |
|---------|------|------|
| target | `oci-2` / `gcp` | 배포 대상 서버 |
| action | `deploy` / `rollback` / `restart` | 배포 액션 |

## 설정 체크리스트

### GitHub Secrets 설정

| Secret | Environment | 용도 |
|--------|------------|------|
| `OCI2_SSH_KEY` | OCI2 | OCI #2 서버 SSH 개인키 |
| `OCI2_HOST` | OCI2 | OCI #2 서버 호스트 |
| `OCI2_USER` | OCI2 | OCI #2 SSH 사용자명 |
| `GCP_SSH_KEY` | GCP | GCP 서버 SSH 개인키 |
| `GCP_HOST` | GCP | GCP 서버 호스트 |
| `GCP_USER` | GCP | GCP SSH 사용자명 |
| `N8N_ENCRYPTION_KEY` | 공통 | n8n 데이터 암호화 키 |

### 플레이스홀더 변경 필요 항목

| 파일 | 플레이스홀더 | 설명 |
|------|------------|------|
| `clusters/oci-2/n8n/helm-charts/values.yaml` | `<GITHUB_USERNAME>` | GitHub 사용자명 |
| `clusters/oci-2/n8n/helm-charts/values.gcp.yaml` | `<GCP_EXTERNAL_IP>` | GCP 외부 IP |
| `clusters/oci-2/n8n/helm-charts/values.oci.yaml` | `<N8N_DOMAIN>` | n8n 도메인 |
| `infra/argocd/applications/oci-2-n8n.yaml` | `<GITHUB_USERNAME>` | GitHub 사용자명 |
| `infra/argocd/applications/oci-2-n8n.yaml` | `<OCI_2_K3S_API_주소>` | OCI #2 API 서버 |

## 변경 이력

| 날짜 | 버전 | 변경 사항 |
|------|------|---------|
| 2026-02-15 | v3.0 | 멀티 클러스터 구조 리팩토링 (clusters/ 도입), n8n 추가 |
| 2026-02-04 | v2.0 | Kubernetes (K3s) 및 Kustomize 기반 구조로 전면 개편 |
| 2026-01-27 | v1.1 | 공통 리소스를 `infra/_shared/`로 통합 |
| 2026-01-27 | v1.0 | 초기 템플릿 구조 생성 |

---

**마지막 업데이트**: 2026-02-15
