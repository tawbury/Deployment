<!-- Document Metadata -->
- Document Name: Deploy Sub Architecture
- File Name: k8s_sub_architecture.md
- Document ID: ARCH-DEPLOY-SUB-001
- Status: Active
- Version: 2.0.0
- Created Date: 2026-02-02
- Last Updated: 2026-02-02
- Author: {{USER}}
- Reviewer: {{REVIEWER}}
- Parent Document: [[k8s_architecture.md]] (ARCH-DEPLOY-001)
- Related Reference: [[k8s_app_architecture.md]] (ARCH-APP-SUB-001)
- Change Summary:
  - Deploy 레포 로컬 디렉터리 구조 정의
  - GHCR 이미지 핸들링 책임 명세
  - CI/CD 워크플로우 배치 규칙 수립
  - 멀티 앱/멀티 클라우드 확장성 고려사항 명시
  - v1.1.0: 템플릿 프로젝트 구조 반영, 문서 간 연결 매핑 강화
  - **v2.0.0: k3s(경량 Kubernetes) 기반 아키텍처로 전환**
    - 역사: Docker Compose에서 Kubernetes manifests (kustomize)로 전환
    - Helm charts 지원 추가
    - ConfigMap/Secret 기반 환경변수 관리
    - PersistentVolumeClaim 기반 스토리지 관리
    - ServiceMonitor 기반 k8s 네이티브 모니터링
    - GitOps (ArgoCD/Flux) 선택적 도입
    - kubectl/helm 기반 배포 스크립트
<!-- End Metadata -->

---

# Deploy Sub Architecture

---

## 문서 연결 매핑

```
[메인 아키텍처]
k8s_architecture.md (ARCH-DEPLOY-001)
         ├── 책임 분리 원칙 정의
         ├── GHCR 기반 CI/CD 흐름 정의
         ├── k3s 아키텍처 선택 이유
         └── Kubernetes 핵심 개념 매핑
         │
         ├─▶ [App Architecture]
         │   k8s_app_architecture.md (ARCH-APP-SUB-001)
         │   ├── App 레포 책임 구체화
         │   ├── 이미지 생산 (Producer)
         │   └── 환경변수 스키마 정의
         │
         └─▶ [Deploy 서브 아키텍처] ◀─ 본 문서
             k8s_sub_architecture.md (ARCH-DEPLOY-SUB-001)
             ├── Deploy 레포 k8s manifests 구조
             ├── 이미지 소비 (Consumer)
             ├── ConfigMap/Secret으로 환경변수 값 제공
             └── kustomize/Helm 기반 환경별 오버레이
```

**템플릿 내 참조:**
- k8s manifests: `infra/k8s/` (kustomize base + overlays)
- Helm charts: `infra/helm/` (선택적)
- GitOps: `infra/argocd/` (선택적)
- 공통 인프라: `infra/_shared/`
- App 레포 예시: `app/prj_*/` (참조용)

---

## 목차

1. [Deploy Sub Architecture 개요](#1-deploy-sub-architecture-개요)
2. [Deploy Repository 로컬 디렉터리 구조](#2-deploy-repository-로컬-디렉터리-구조)
3. [GHCR 이미지 핸들링 책임](#3-ghcr-이미지-핸들링-책임)
4. [CI/CD 워크플로우 배치 규칙](#4-cicd-워크플로우-배치-규칙)
5. [확장성 고려](#5-확장성-고려)
6. [Kubernetes Secrets 관리](#6-kubernetes-secrets-관리)
7. [k8s 네이티브 모니터링](#7-k8s-네이티브-모니터링)
8. [GitOps 배포 파이프라인](#8-gitops-배포-파이프라인)

---

## 1. Deploy Sub Architecture 개요

> **템플릿 프로젝트 참고**: 본 문서는 Deploy 레포 구조와 책임을 정의합니다. 현재 Kubernetes_k8s 템플릿의 `infra/` 디렉터리가 Deploy 레포의 실제 구조입니다.
>
> **k3s 기반 아키텍처**: 본 문서는 k3s(경량 Kubernetes) 환경에서 kustomize/Helm 기반으로 워크로드를 관리하는 방식을 설명합니다. k3s/Kubernetes를 유일한 런타임으로 가정하며, Docker 기반 오케스트레이션은 대상이 아니다.

### 1.1 메인 아키텍처와의 관계

본 문서는 **[[k8s_architecture.md]] (ARCH-DEPLOY-001)의 하위 문서**이다.

**메인 아키텍처와의 관계:**
```
k8s_architecture.md (메인)
         │
         ├── 1.1절: 책임 분리 원칙
         │   └─▶ 본 문서 1.2절에서 Deploy 레포 책임 구체화
         │
         ├── 1.3절: 클러스터 기준 철학
         │   └─▶ 본 문서 2절에서 k8s manifests 구조로 구현
         │
         ├── 3절: Deploy Template 서브 아키텍처
         │   └─▶ 본 문서 전체에서 상세 구조 정의
         │
         ├── 6절: k3s 아키텍처 선택 이유
         │   └─▶ 본 문서의 k8s 구조 설계 근거
         │
         └── 7절: Kubernetes 핵심 개념 매핑
             └─▶ 본 문서의 리소스 정의 참조
```

**메인 아키텍처에서 정의된 전제 조건:**
- App 레포와 Deploy 레포의 책임 분리 → 본 문서 1.2절 참조
- GHCR 기반 이미지 불변 태그 정책 → 본 문서 3.1절 참조
- PVC 기반 스토리지 관리 → [[k8s_architecture.md]] 1.3절 참조
- 컨테이너/데이터 생명주기 원칙 → [[k8s_architecture.md]] 1.3절 참조

**템플릿 내 실제 구조:**
```
Kubernetes_k8s/
├── app/                    # App 레포 참조 (별도 레포로 분리)
│   └── prj_*/              # App Architecture 참조
└── infra/                  # Deploy 레포 구조 (본 문서)
    ├── k8s/                # [k3s] Kubernetes manifests
    │   ├── base/           # kustomize base
    │   └── overlays/       # 환경별 오버레이
    ├── helm/               # [선택적] Helm charts
    ├── argocd/             # [선택적] GitOps Application
    └── _shared/            # 공통 인프라 리소스
        ├── monitoring/     # kube-prometheus-stack
        ├── migrations/     # DB 마이그레이션 Job 실행 템플릿 (소유권은 App)
        ├── secrets/        # SealedSecrets/SOPS
        └── scripts/        # kubectl/helm 배포 스크립트
```

본 문서는 메인 아키텍처의 원칙을 **Deploy 레포 k8s manifests 구조**로 구체화한다. 메인 아키텍처에서 이미 정의된 내용은 반복하지 않으며, 참조만 한다.

### 1.2 Deploy 레포의 책임 범위 정의

Deploy 레포는 다음에 대해서만 책임진다:

| 책임 영역 | 수행 내용 | k8s 리소스 |
|----------|----------|-----------|
| 이미지 Pull | GHCR에서 불변 태그 이미지를 가져온다 | Deployment (imagePullSecrets) |
| 워크로드 오케스트레이션 | Pod 배포, 복제, 업데이트를 관리한다 | Deployment, ReplicaSet, Pod |
| 환경 설정 관리 | 환경별 설정값과 시크릿 참조를 관리한다 | ConfigMap, Secret |
| 스토리지 관리 | 영속 볼륨 요청과 마운트를 정의한다 | PVC, volumeMounts |
| 네트워크 노출 | 서비스 디스커버리와 외부 접근을 제공한다 | Service, Ingress |
| 배포 자동화 | kubectl apply, helm upgrade, GitOps sync를 제공한다 | scripts/, ArgoCD Application |
| 운영 자동화 | Probe 기반 헬스체크, 메트릭 노출을 설정한다 | readinessProbe, ServiceMonitor |

Deploy 레포는 다음에 대해 책임지지 않는다:

| 금지 영역 | 이유 |
|----------|------|
| 이미지 빌드 | App 레포 CI의 책임이다 |
| 소스 코드 보관 | App 레포의 책임이다 |
| DB 마이그레이션 로직 | App 레포의 책임이다 (Deploy는 Job 실행만) |
| 비즈니스 로직 실행 | 컨테이너 이미지 내부에서 처리한다 |

**DB 마이그레이션 책임 구분:** 데이터베이스 마이그레이션의 **소유권(정의·로직)** 은 애플리케이션 레이어(App)에 있다. 본 문서에서 언급하는 `_shared/migrations/` 디렉터리 및 Job 정의는 **실행 환경용 템플릿**일 뿐이며, Deploy는 해당 Job을 실행하는 환경만 제공한다. 소유권과 실행 환경을 혼동하지 않는다.

---

## 2. Deploy Repository 로컬 디렉터리 구조

### 2.1 루트 디렉터리 구조

**k3s 기반 템플릿 구조 (`infra/`):**
```
infra/
├── k8s/                         # [k3s] Kubernetes manifests
│   ├── base/                    # kustomize base (공통 리소스)
│   │   ├── namespaces/          # Namespace 정의
│   │   │   └── prj-01.yaml
│   │   ├── deployments/         # Deployment 정의
│   │   │   └── app.yaml
│   │   ├── services/            # Service 정의
│   │   │   └── app-svc.yaml
│   │   ├── configmaps/          # ConfigMap 정의
│   │   │   └── app-config.yaml
│   │   ├── secrets/             # Secret 참조 (실제 값은 SealedSecrets)
│   │   │   └── app-secrets.yaml
│   │   ├── pvc/                 # PersistentVolumeClaim 정의
│   │   │   └── app-pvc.yaml
│   │   ├── ingress/             # Ingress 정의
│   │   │   └── app-ingress.yaml
│   │   └── kustomization.yaml   # base 리소스 조합
│   └── overlays/                # 환경별 오버레이
│       ├── production/
│       │   ├── kustomization.yaml
│       │   └── patches/
│       │       ├── replicas.yaml
│       │       └── resources.yaml
│       └── staging/
│           ├── kustomization.yaml
│           └── patches/
├── helm/                        # [선택적] Helm charts
│   └── apps/
│       └── app-name/
│           ├── Chart.yaml
│           ├── values.yaml      # 기본 values
│           ├── values-prod.yaml # 프로덕션 오버라이드
│           ├── values-staging.yaml
│           └── templates/
│               ├── deployment.yaml
│               ├── service.yaml
│               └── _helpers.tpl
├── argocd/                      # [선택적] GitOps Application 정의
│   └── applications/
│       ├── app-production.yaml
│       └── app-staging.yaml
└── _shared/                     # 공통 인프라 리소스
    ├── monitoring/              # kube-prometheus-stack 설정
    │   ├── values.yaml          # Helm values
    │   ├── dashboards/          # Grafana 대시보드 ConfigMap
    │   └── README.md
    ├── migrations/              # DB 마이그레이션 Job 실행 템플릿 (소유권은 App)
    │   └── job-template.yaml
    ├── secrets/                 # SealedSecrets / SOPS
    │   ├── sealed/              # 암호화된 시크릿 (Git 추적)
    │   └── README.md
    └── scripts/                 # 배포, k3s 관리 스크립트
        ├── build/
        ├── deploy/              # kubectl/helm 배포 스크립트
        ├── k3s/                 # k3s 클러스터 관리
        ├── env/
        ├── migrate/             # 마이그레이션 Job 실행
        └── oci/
```

**템플릿 → 실제 프로젝트 매핑:**

| 템플릿 경로 | 실제 Deploy 레포 | 용도 |
|-----------|-----------------|------|
| `infra/k8s/base/` | `deploy-repo/k8s/base/` | kustomize base (공통 manifests) |
| `infra/k8s/overlays/` | `deploy-repo/k8s/overlays/` | 환경별 오버레이 |
| `infra/helm/` | `deploy-repo/helm/` | Helm charts (선택적) |
| `infra/argocd/` | `deploy-repo/argocd/` | GitOps Application (선택적) |
| `infra/_shared/` | `deploy-repo/_shared/` | 공통 리소스 |
| `infra/_shared/monitoring/` | `deploy-repo/_shared/monitoring/` | kube-prometheus-stack |
| `infra/_shared/secrets/` | `deploy-repo/_shared/secrets/` | SealedSecrets/SOPS |
| `infra/_shared/scripts/` | `deploy-repo/_shared/scripts/` | kubectl/helm 배포 스크립트 |

### 2.2 각 디렉터리의 단일 책임 원칙

#### `k8s/base/` (kustomize base)

**책임:** 모든 환경에서 공통으로 사용하는 k8s manifests를 정의한다.

**구조:**
```
k8s/base/
├── namespaces/              # Namespace 정의
│   └── prj-01.yaml
├── deployments/             # Deployment 정의
│   └── app.yaml
├── services/                # Service 정의
│   └── app-svc.yaml
├── configmaps/              # ConfigMap 정의
│   └── app-config.yaml
├── secrets/                 # Secret 참조 (SealedSecrets)
│   └── app-secrets.yaml
├── pvc/                     # PersistentVolumeClaim
│   └── app-pvc.yaml
├── ingress/                 # Ingress 정의
│   └── app-ingress.yaml
└── kustomization.yaml       # 리소스 조합
```

**kustomization.yaml 예시:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: prj-01

resources:
  - namespaces/prj-01.yaml
  - deployments/app.yaml
  - services/app-svc.yaml
  - configmaps/app-config.yaml
  - secrets/app-secrets.yaml
  - pvc/app-pvc.yaml
  - ingress/app-ingress.yaml

commonLabels:
  app.kubernetes.io/managed-by: kustomize
```

**원칙:**
- base는 환경에 독립적인 공통 설정만 포함
- 환경별 차이는 overlays에서 패치
- 이미지 태그는 base에서 `latest` 또는 placeholder 사용

#### `k8s/overlays/` (환경별 오버레이)

**책임:** 환경별로 다른 설정을 패치한다.

**구조:**
```
k8s/overlays/
├── production/
│   ├── kustomization.yaml
│   └── patches/
│       ├── replicas.yaml        # replicas: 3
│       ├── resources.yaml       # CPU/Memory limits
│       └── image-tag.yaml       # 이미지 태그 지정
└── staging/
    ├── kustomization.yaml
    └── patches/
        ├── replicas.yaml        # replicas: 1
        └── resources.yaml
```

**production/kustomization.yaml 예시:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: prj-01-prod

images:
  - name: ghcr.io/org/app
    newTag: v1.2.3

patchesStrategicMerge:
  - patches/replicas.yaml
  - patches/resources.yaml
```

**원칙:**
- 각 환경은 base를 참조하고 필요한 부분만 패치
- 이미지 태그는 overlay에서 명시적으로 지정
- 환경별 ConfigMap/Secret 값은 별도 파일로 관리

#### `helm/` (선택적)

**책임:** Helm chart로 앱을 패키징한다.

**구조:**
```
helm/apps/app-name/
├── Chart.yaml               # Chart 메타데이터
├── values.yaml              # 기본 values
├── values-prod.yaml         # 프로덕션 오버라이드
├── values-staging.yaml      # 스테이징 오버라이드
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    ├── configmap.yaml
    ├── secret.yaml
    ├── pvc.yaml
    ├── ingress.yaml
    └── _helpers.tpl
```

**원칙:**
- Helm은 kustomize 대신 사용하거나 함께 사용
- 복잡한 템플릿 로직이 필요할 때 Helm 선택
- values 파일로 환경별 설정 분리

**kustomize vs Helm 선택 기준:**

| 상황 | 권장 |
|------|------|
| 단순한 환경별 패치 | kustomize |
| 조건부 로직 필요 | Helm |
| 외부 chart 사용 | Helm |
| GitOps 단순화 | kustomize |

#### `argocd/` (선택적)

**책임:** GitOps Application을 정의한다.

**구조:**
```
argocd/applications/
├── app-production.yaml      # 프로덕션 Application
├── app-staging.yaml         # 스테이징 Application
└── app-of-apps.yaml         # App of Apps 패턴 (선택적)
```

**Application 예시:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-production
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/deploy-repo.git
    targetRevision: main
    path: infra/k8s/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: prj-01-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**원칙:**
- ArgoCD는 선택적 도입
- Application 정의는 Git에 저장
- automated sync 정책은 환경에 따라 결정

#### `_shared/` (공통 인프라)

**책임:** 모든 환경에서 공통으로 사용하는 인프라 리소스를 관리한다.

**k3s 기반 구조:**
```
_shared/
├── monitoring/              # kube-prometheus-stack 설정
│   ├── values.yaml          # Helm values
│   ├── dashboards/          # Grafana 대시보드 ConfigMap
│   │   ├── app-dashboard.json
│   │   └── kustomization.yaml
│   └── README.md
├── migrations/              # DB 마이그레이션 Job 실행 템플릿 (마이그레이션 소유권·로직은 App)
│   ├── 001_create_scalp_tables.sql
│   ├── 002_create_swing_tables.sql
│   └── job-template.yaml    # 마이그레이션 Job 실행 템플릿
├── secrets/                 # SealedSecrets / SOPS
│   ├── sealed/              # 암호화된 시크릿 (Git 추적)
│   │   └── app-secrets.yaml
│   ├── .gitignore
│   └── README.md
└── scripts/                 # 자동화 스크립트
    ├── build/               # 빌드 태그 생성
    ├── deploy/              # kubectl/helm 배포 스크립트
    ├── k3s/                 # k3s 클러스터 관리
    ├── env/                 # 환경 설정
    ├── migrate/             # 마이그레이션 Job 실행
    └── oci/                 # OCI 프로비저닝
```

**App Architecture와의 연결:**
- App의 이미지 → `k8s/base/deployments/`에서 참조
- App이 소유한 마이그레이션 → Deploy의 `_shared/migrations/` Job 실행 템플릿으로 실행 환경만 제공
- App의 환경변수 스키마 → `k8s/base/configmaps/`, `k8s/base/secrets/`에서 값 제공

#### `_shared/scripts/` (배포 스크립트)

**k3s 기반 스크립트 구조:**
```
scripts/
├── build/
│   ├── generate_build_tag.ps1
│   ├── generate_build_tag.sh
│   └── README.md
├── deploy/
│   ├── k8s-deploy.sh           # kustomize 배포
│   ├── helm-deploy.sh          # Helm 배포
│   ├── check_health.sh         # kubectl 기반 헬스체크
│   ├── rollback.sh             # kubectl rollout undo
│   └── README.md
├── k3s/
│   ├── install.sh              # k3s 설치
│   ├── join-agent.sh           # 워커 노드 추가
│   ├── backup.sh               # etcd 스냅샷 백업
│   └── README.md
├── env/
│   ├── setup_env_secure.sh
│   └── README.md
├── migrate/
│   ├── run-migration-job.sh    # 마이그레이션 Job 실행
│   └── README.md
└── oci/
    ├── oci_launch_instance.ps1
    ├── cloud-init-k3s.yaml     # k3s 설치용 cloud-init
    └── README.md
```

**k8s-deploy.sh 예시:**
```bash
#!/bin/bash
set -euo pipefail

ENVIRONMENT="${1:-staging}"
IMAGE_TAG="${2:-latest}"
NAMESPACE="${3:-prj-01}"
OVERLAY_PATH="infra/k8s/overlays/${ENVIRONMENT}"

# 이미지 태그 업데이트
cd "${OVERLAY_PATH}"
kustomize edit set image "ghcr.io/org/app=ghcr.io/org/app:${IMAGE_TAG}"

# 배포 적용
kubectl apply -k .

# 롤아웃 대기
kubectl rollout status deployment/app -n "${NAMESPACE}" --timeout=300s

# 상태 확인
kubectl get pods,svc -n "${NAMESPACE}" -l app=app
```

**원칙:**
- 모든 스크립트는 멱등성을 가져야 한다
- 스크립트는 환경변수로 동작을 제어한다
- 위험한 작업은 `--dry-run` 옵션을 지원한다

#### `docs/runbooks/`

**책임:** k8s 운영 매뉴얼을 제공한다.

**포함 내용:**
- 장애 대응 절차 (Pod CrashLoopBackOff, OOMKilled 등)
- 배포/롤백 절차
- k3s 클러스터 관리 (노드 추가/제거, 업그레이드)
- 백업/복원 절차

---

## 3. GHCR 이미지 핸들링 책임

### 3.1 이미지 태그 정책 (Immutable)

Deploy 레포는 다음 태그 정책을 준수한다:

| 환경 | 허용 태그 | 금지 태그 |
|------|----------|----------|
| Production | `v1.2.3`, `sha-abc1234` | `latest`, `dev`, `test` |
| Staging | `v1.2.3`, `sha-abc1234`, `rc-*` | `latest` |
| Development | 모든 태그 허용 | - |

**근거:** 메인 아키텍처 (ARCH-DEPLOY-001) 1.2절 "태깅 전략" 참조

### 3.1.1 Timestamp 기반 태그 정책 (권장)

본 아키텍처에서는 App 이미지 태그를 의미 기반 버전(v1.2.3)이 아닌
빌드 시점 기준 타임스탬프 기반으로 관리하는 것을 기본 전략으로 한다.

권장 포맷:
- YYYYMMDD-HHMMSS (KST 기준)

예:
- 20260202-143512

이 방식의 목적은 다음과 같다:
- 개발자의 수동 버전 관리 부담 제거
- 이미지 태그의 절대적 불변성 보장
- 배포/롤백 시 단순한 태그 선택 구조 유지

### 3.2 이미지 참조 규칙

Kubernetes manifest에서 이미지를 참조할 때 다음 규칙을 따른다:

```yaml
# k8s/base/deployments/app.yaml
spec:
  containers:
  - name: app
    image: ghcr.io/{organization}/{app-name}:{tag}
```

**이미지 참조 형식:** `ghcr.io/{organization}/{app-name}:{tag}`

| 요소 | 규칙 |
|------|------|
| organization | GitHub 조직명 또는 사용자명을 사용한다 |
| app-name | App 레포 이름과 동일하게 유지한다 |
| tag | base에서는 placeholder, overlay에서 실제 태그 지정 |

**kustomize로 이미지 태그 관리:**
```yaml
# k8s/overlays/production/kustomization.yaml
images:
  - name: ghcr.io/org/app
    newTag: v1.2.3
```

### 3.3 빌드/푸시/릴리스 책임 분리

```
[App Repo]                    [Deploy Repo]
    │                              │
    ├── 빌드 책임                   │
    ├── 테스트 책임                 │
    ├── GHCR 푸시 책임              │
    │                              │
    │   ══════════════════════════════
    │        (GHCR이 경계선)
    │   ══════════════════════════════
    │                              │
    │                              ├── 이미지 태그 선택 책임
    │                              ├── kustomize/Helm에서 이미지 참조
    │                              ├── kubectl apply / helm upgrade 실행
    │                              └── kubectl rollout undo (롤백)
```

**명확한 책임 경계:**
- App 레포는 이미지를 "생산"한다.
- Deploy 레포는 이미지를 "소비"한다.
- 두 레포 간 직접적인 의존성은 존재하지 않는다.
- 이미지 태그가 유일한 인터페이스이다.
- k3s 클러스터가 GHCR에서 이미지를 Pull한다.

### 3.4 이미지 버전 관리

Deploy 레포는 다음 방식으로 이미지 버전을 관리한다:

**kustomize 방식:**

| 파일 | 역할 |
|------|------|
| `k8s/base/deployments/app.yaml` | 기본 이미지 (placeholder 또는 latest) |
| `k8s/overlays/{env}/kustomization.yaml` | `images:` 섹션에서 실제 태그 지정 |

**Helm 방식:**

| 파일 | 역할 |
|------|------|
| `helm/apps/app/values.yaml` | `image.tag: "placeholder"` |
| `helm/apps/app/values-prod.yaml` | `image.tag: "v1.2.3"` |

**버전 변경 절차 (kustomize):**
```bash
# 1. 이미지 태그 업데이트
cd infra/k8s/overlays/production
kustomize edit set image ghcr.io/org/app=ghcr.io/org/app:v1.2.4

# 2. 변경사항 커밋
git add kustomization.yaml
git commit -m "chore: bump app image to v1.2.4"
git push

# 3. 배포 적용
kubectl apply -k .

# 또는 ArgoCD 자동 동기화 대기
```

### 3.5 GHCR 인증 (imagePullSecrets)

k3s 클러스터에서 private GHCR 이미지를 pull하려면 인증이 필요하다.

**Secret 생성:**
```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=$GITHUB_USERNAME \
  --docker-password=$GITHUB_PAT \
  --docker-email=$GITHUB_EMAIL \
  -n prj-01
```

**Deployment에서 참조:**
```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: ghcr-secret
      containers:
        - name: app
          image: ghcr.io/org/app:v1.2.3
```

**ServiceAccount에 연결 (권장):**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
imagePullSecrets:
  - name: ghcr-secret
```

---

## 4. CI/CD 워크플로우 배치 규칙

### 4.1 GitHub Actions 위치 규칙

| 워크플로우 유형 | 위치 | 이유 |
|---------------|------|------|
| 이미지 빌드/푸시 | App 레포 | 소스 코드와 함께 버전 관리되어야 한다 |
| 앱 테스트 | App 레포 | 소스 코드 변경 시 트리거되어야 한다 |
| manifest 검증 | Deploy 레포 | kustomize build, kubeval, kubeconform |
| 배포 트리거 | Deploy 레포 또는 ArgoCD | 설정 변경 시 트리거 |
| 인프라 프로비저닝 | Deploy 레포 | 클러스터 설정 변경 추적 |

### 4.2 배포 방식 선택

#### 옵션 1: kubectl/kustomize 직접 배포

```bash
# GitHub Actions 또는 로컬에서 실행
kubectl apply -k infra/k8s/overlays/production/
```

**장점:** 단순함, 학습 곡선 낮음
**단점:** 수동 실행 필요, 상태 추적 어려움

#### 옵션 2: Helm 배포

```bash
helm upgrade --install app infra/helm/apps/app \
  -f infra/helm/apps/app/values-prod.yaml \
  -n prj-01
```

**장점:** 릴리스 관리, 롤백 용이
**단점:** 템플릿 복잡도 증가

#### 옵션 3: GitOps (ArgoCD)

```yaml
# Git push 후 ArgoCD가 자동 동기화
# 또는 수동 동기화
argocd app sync app-production
```

**장점:** 선언적 관리, 자동 상태 조정, 감사 로그
**단점:** ArgoCD 운영 오버헤드

### 4.3 공통 워크플로우 (Deploy 레포)

```
.github/workflows/
├── validate-manifests.yml     # kustomize build, kubeconform
├── deploy-staging.yml         # 스테이징 배포 (자동)
├── deploy-production.yml      # 프로덕션 배포 (승인 필요)
└── sync-argocd.yml            # ArgoCD 동기화 트리거 (선택적)
```

**validate-manifests.yml 예시:**
```yaml
name: Validate Manifests

on:
  pull_request:
    paths:
      - 'infra/k8s/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup kustomize
        uses: imranismail/setup-kustomize@v2

      - name: Build kustomize
        run: |
          kustomize build infra/k8s/overlays/staging > /tmp/staging.yaml
          kustomize build infra/k8s/overlays/production > /tmp/production.yaml

      - name: Validate with kubeconform
        uses: yannh/kubeconform-action@v0.1
        with:
          files: /tmp/*.yaml
```

### 4.4 워크플로우 트리거 규칙

| 트리거 | 대상 환경 | 조건 |
|--------|----------|------|
| push to main | Staging | 자동 배포 (kubectl apply 또는 ArgoCD sync) |
| manual dispatch | Production | 수동 승인 필수, 이미지 태그 입력 |
| tag push (v*) | - | 배포 없음 (App 레포에서 이미지 빌드만) |
| pull request | - | manifest 검증만, 배포 안 함 |

### 4.5 롤백 절차

**kubectl 롤백:**
```bash
# 이전 버전으로 롤백
kubectl rollout undo deployment/app -n prj-01

# 특정 revision으로 롤백
kubectl rollout history deployment/app -n prj-01
kubectl rollout undo deployment/app -n prj-01 --to-revision=2
```

**ArgoCD 롤백:**
```bash
# 이전 동기화 상태로 롤백
argocd app history app-production
argocd app rollback app-production <REVISION>
```

**Git 기반 롤백 (권장):**
```bash
# kustomization.yaml에서 이전 이미지 태그로 변경
git revert HEAD
git push
# ArgoCD 자동 동기화 또는 kubectl apply
```

---

## 5. 확장성 고려

### 5.1 멀티 앱 확장 시 구조 유지 방식

신규 앱 추가 시 다음 절차를 따른다:

**kustomize 방식:**
```
1. k8s/base/에 앱별 manifests 추가 (deployments/, services/ 등)
2. k8s/base/kustomization.yaml에 리소스 추가
3. k8s/overlays/*/에 앱별 패치 추가 (필요시)
4. 기존 앱의 설정은 수정하지 않음
```

**Namespace로 앱 분리:**
```yaml
# k8s/base/namespaces/
prj-01.yaml   # 프로젝트 1 Namespace
prj-02.yaml   # 프로젝트 2 Namespace (신규)
```

**구조 유지 원칙:**
- 각 앱은 별도 Namespace에서 격리
- 공통 인프라 (모니터링, 시크릿)는 `_shared/`에서 관리
- 앱 간 의존성은 Service DNS로 해결 (`{service}.{namespace}.svc.cluster.local`)

### 5.2 멀티 노드/클러스터 확장

#### 워커 노드 추가

```bash
# 서버 노드에서 토큰 가져오기
sudo cat /var/lib/rancher/k3s/server/node-token

# 워커 노드에서 실행
curl -sfL https://get.k3s.io | K3S_URL=https://server:6443 K3S_TOKEN=xxx sh -
```

**영향:**
- manifest 변경 없음
- Kubernetes 스케줄러가 자동으로 Pod 분산
- replicas 증가 시 자동으로 워커 노드 활용

#### HA (고가용성) 클러스터 구성

```bash
# 첫 번째 서버 (임베디드 etcd)
curl -sfL https://get.k3s.io | sh -s - server --cluster-init

# 추가 서버 노드
curl -sfL https://get.k3s.io | K3S_TOKEN=xxx sh -s - server --server https://server1:6443
```

#### Replica 수평 확장

```yaml
# k8s/overlays/production/patches/replicas.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 3  # 1 → 3으로 확장
```

### 5.3 클라우드 확장 시 영향 범위

#### OCI (Oracle Cloud Infrastructure) + k3s

| 영향받는 영역 | 변경 내용 |
|-------------|----------|
| `_shared/scripts/oci/` | k3s 설치용 cloud-init 스크립트 |
| `k8s/overlays/oci-production/` | OCI 환경 전용 오버레이 (선택적) |
| StorageClass | OCI Block Volume 또는 local-path |

**cloud-init-k3s.yaml 예시:**
```yaml
#cloud-config
runcmd:
  - curl -sfL https://get.k3s.io | sh -
  - kubectl create secret docker-registry ghcr-secret ...
```

#### Azure / GCP / AWS 확장

| 클라우드 | 추가 고려사항 |
|---------|-------------|
| Azure | AKS 사용 또는 VM에 k3s, ACR 이미지 레지스트리 |
| GCP | GKE 사용 또는 VM에 k3s, Artifact Registry |
| AWS | EKS 사용 또는 EC2에 k3s, ECR 이미지 레지스트리 |

**대응 원칙:**
- 레지스트리 주소를 kustomize images로 추상화
- StorageClass는 환경별 overlay에서 지정
- Ingress Controller는 클라우드 로드밸런서와 연동

### 5.4 멀티 클러스터 확장

```
k8s/
├── base/                     # 모든 클러스터 공통
├── overlays/
│   ├── cluster-a/
│   │   ├── production/
│   │   └── staging/
│   └── cluster-b/
│       ├── production/
│       └── staging/
```

**원칙:**
- 각 클러스터는 독립적인 overlay 세트
- base는 클러스터 간 공유
- kubeconfig로 클러스터 선택: `kubectl --context=cluster-a`

### 5.5 확장 시 금지 사항

다음 패턴은 확장성을 저해하므로 금지한다:

| 금지 패턴 | 이유 |
|----------|------|
| base manifests에 환경별 값 하드코딩 | overlay로 분리해야 함 |
| 앱별 디렉터리 구조 변형 | 일관성 파괴 |
| 스크립트 내 하드코딩 | 환경변수로 제어해야 함 |
| 앱 간 직접 파일 참조 | Namespace 격리 원칙 위반 |
| kubectl edit으로 직접 수정 | Git에 반영되지 않음 |

---

## 6. Kubernetes Secrets 관리

### 6.1 Secret 관리 원칙

**핵심 원칙:**
- 민감 정보는 절대 Git에 평문으로 저장하지 않는다
- Secret은 암호화된 형태로만 Git에 커밋한다
- 런타임에만 복호화되어 Pod에 주입된다

**관리 옵션:**

| 방식 | 설명 | 권장 상황 |
|------|------|----------|
| SealedSecrets | 클러스터 키로 암호화, Git 저장 | GitOps 환경 |
| SOPS | 파일 단위 암호화 (age/gpg) | 멀티 클러스터 |
| External Secrets | 외부 시크릿 매니저 연동 | 클라우드 네이티브 |
| Vault | HashiCorp Vault 연동 | 엔터프라이즈 |

### 6.2 SealedSecrets 워크플로우

**아키텍처:**
```
[개발자 로컬]                    [k3s 클러스터]
     │                               │
     │ kubeseal                      │
     ├──────────────────────────────▶│ SealedSecrets Controller
     │                               │
     │   암호화된 SealedSecret       │
     │   (Git에 커밋 가능)           │
     │                               │
     │                               ▼
     │                          [복호화]
     │                               │
     │                               ▼
     │                          Secret 생성
     │                               │
     │                               ▼
     │                          Pod에 주입
```

**설치:**
```bash
# SealedSecrets Controller 설치
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# kubeseal CLI 설치 (로컬)
# macOS
brew install kubeseal
# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar -xzf kubeseal-*.tar.gz
sudo mv kubeseal /usr/local/bin/
```

**사용 워크플로우:**
```bash
# 1. 일반 Secret 생성 (로컬, Git에 커밋하지 않음)
kubectl create secret generic app-secrets \
  --from-literal=DB_PASSWORD=mysecret \
  --from-literal=API_KEY=myapikey \
  --dry-run=client -o yaml > /tmp/secret.yaml

# 2. SealedSecret으로 변환
kubeseal --format yaml < /tmp/secret.yaml > infra/_shared/secrets/sealed/app-secrets.yaml

# 3. Git에 커밋 (암호화된 상태)
git add infra/_shared/secrets/sealed/app-secrets.yaml
git commit -m "chore: add sealed app-secrets"

# 4. 클러스터에 적용
kubectl apply -f infra/_shared/secrets/sealed/app-secrets.yaml
# Controller가 자동으로 Secret 생성
```

**디렉터리 구조:**
```
_shared/secrets/
├── sealed/                    # Git 추적 (암호화됨)
│   ├── app-secrets.yaml       # SealedSecret
│   └── ghcr-secret.yaml       # GHCR 인증 SealedSecret
├── templates/                 # 템플릿 (예시용)
│   └── secret-template.yaml
├── .gitignore                 # 평문 Secret 제외
└── README.md
```

**.gitignore:**
```gitignore
# 평문 Secret 절대 커밋 금지
*.secret.yaml
!sealed/*.yaml
/tmp/
```

### 6.3 SOPS 워크플로우 (대안)

**age 키 기반 암호화:**
```bash
# age 키 생성
age-keygen -o keys.txt

# SOPS 설정 (.sops.yaml)
cat > .sops.yaml << EOF
creation_rules:
  - path_regex: .*secrets.*\.yaml$
    age: >-
      age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
EOF

# Secret 암호화
sops -e secrets.yaml > secrets.enc.yaml

# Secret 복호화 (배포 시)
sops -d secrets.enc.yaml | kubectl apply -f -
```

**장점:**
- 클러스터 의존성 없음 (로컬에서 복호화 가능)
- 멀티 클러스터 환경에 적합
- age, gpg, AWS KMS, GCP KMS 등 다양한 키 지원

### 6.4 Deployment에서 Secret 사용

```yaml
# k8s/base/deployments/app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  template:
    spec:
      containers:
      - name: app
        envFrom:
          # ConfigMap에서 일반 설정 로드
          - configMapRef:
              name: app-config
          # Secret에서 민감 정보 로드
          - secretRef:
              name: app-secrets
        env:
          # 개별 Secret 키 참조
          - name: DB_PASSWORD
            valueFrom:
              secretKeyRef:
                name: app-secrets
                key: DB_PASSWORD
```

### 6.5 Secret 교체 절차

```bash
# 1. 새 Secret 값으로 SealedSecret 재생성
kubectl create secret generic app-secrets \
  --from-literal=DB_PASSWORD=newsecret \
  --dry-run=client -o yaml | kubeseal --format yaml > sealed/app-secrets.yaml

# 2. Git 커밋
git add sealed/app-secrets.yaml
git commit -m "chore: rotate app-secrets"
git push

# 3. 배포 (Pod 재시작 필요)
kubectl apply -f sealed/app-secrets.yaml
kubectl rollout restart deployment/app -n prj-01
```

---

## 7. k8s 네이티브 모니터링

### 7.1 모니터링 스택 구성

**kube-prometheus-stack 기반 아키텍처:**
```
┌─────────────────────────────────────────────────────────────┐
│                    k3s 클러스터                               │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ kube-prometheus-stack (Helm)                        │   │
│  │                                                     │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐      │   │
│  │  │Prometheus │  │  Grafana  │  │AlertManager│      │   │
│  │  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘      │   │
│  │        │              │              │            │   │
│  │        ▼              ▼              ▼            │   │
│  │   ┌─────────┐    ┌─────────┐    ┌─────────┐      │   │
│  │   │Scrape   │    │Dashboard│    │ Alert   │      │   │
│  │   │Metrics  │    │Render   │    │ Route   │      │   │
│  │   └─────────┘    └─────────┘    └─────────┘      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   App Pod   │  │   App Pod   │  │ Node Exp.  │         │
│  │  /metrics   │  │  /metrics   │  │  /metrics  │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

### 7.2 kube-prometheus-stack 설치

**Helm으로 설치:**
```bash
# Helm repo 추가
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 설치
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -f infra/_shared/monitoring/values.yaml \
  -n monitoring --create-namespace
```

**values.yaml 예시:**
```yaml
# infra/_shared/monitoring/values.yaml
prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi

grafana:
  adminPassword: "admin"  # Example only. Production must use Secret or SealedSecret
  persistence:
    enabled: true
    size: 10Gi
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard

alertmanager:
  config:
    global:
      resolve_timeout: 5m
    route:
      receiver: 'slack-notifications'
    receivers:
      - name: 'slack-notifications'
        slack_configs:
          - api_url: 'https://hooks.slack.com/...'
            channel: '#alerts'
```

### 7.3 ServiceMonitor로 앱 메트릭 수집

**ServiceMonitor 정의:**
```yaml
# k8s/base/servicemonitor/app-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: app-monitor
  labels:
    release: kube-prometheus-stack  # Prometheus가 발견하도록
spec:
  selector:
    matchLabels:
      app: app
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
  namespaceSelector:
    matchNames:
      - prj-01
```

**앱 Service에 포트 정의:**
```yaml
# k8s/base/services/app-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: app
  labels:
    app: app
spec:
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: metrics   # 메트릭 전용 포트 (선택적)
      port: 9090
      targetPort: 9090
  selector:
    app: app
```

### 7.4 Grafana 대시보드 관리

**ConfigMap으로 대시보드 배포:**
```yaml
# infra/_shared/monitoring/dashboards/app-dashboard-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "true"  # Grafana sidecar가 자동 로드
data:
  app-dashboard.json: |
    {
      "title": "App Dashboard",
      "panels": [
        {
          "title": "Request Rate",
          "type": "graph",
          "targets": [
            {
              "expr": "rate(http_requests_total{app=\"app\"}[5m])"
            }
          ]
        }
      ]
    }
```

**디렉터리 구조:**
```
_shared/monitoring/
├── values.yaml                # kube-prometheus-stack values
├── dashboards/
│   ├── app-dashboard.json     # Grafana 대시보드 JSON
│   ├── app-dashboard-cm.yaml  # ConfigMap으로 래핑
│   └── kustomization.yaml
├── rules/
│   └── app-alerts.yaml        # PrometheusRule (알림 규칙)
└── README.md
```

### 7.5 알림 규칙 (PrometheusRule)

```yaml
# infra/_shared/monitoring/rules/app-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: app-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: app.rules
      rules:
        - alert: AppHighErrorRate
          expr: |
            rate(http_requests_total{status=~"5.."}[5m])
            / rate(http_requests_total[5m]) > 0.05
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "High error rate detected"
            description: "Error rate is {{ $value | humanizePercentage }}"

        - alert: AppPodCrashLooping
          expr: |
            rate(kube_pod_container_status_restarts_total{namespace="prj-01"}[15m]) > 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Pod crash looping"
            description: "Pod {{ $labels.pod }} is restarting frequently"
```

### 7.6 리소스 메트릭 (Metrics Server)

**k3s에서 metrics-server 활성화:**
```bash
# k3s는 기본적으로 metrics-server 포함
kubectl top nodes
kubectl top pods -n prj-01
```

**HorizontalPodAutoscaler (HPA) 연동:**
```yaml
# k8s/base/hpa/app-hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

## 8. GitOps 배포 파이프라인

### 8.1 GitOps 개요

**GitOps 원칙:**
- Git을 Single Source of Truth로 사용
- 선언적 구성 (Kubernetes manifests)
- 자동화된 동기화 (Reconciliation Loop)
- 변경 이력 추적 및 감사

**도구 선택:**

| 도구 | 특징 | 권장 상황 |
|------|------|----------|
| ArgoCD | UI 제공, 직관적, 멀티 클러스터 | 대부분의 경우 |
| Flux | 경량, CLI 중심, 네이티브 k8s | GitOps 순수주의자 |

### 8.2 ArgoCD 설치 및 설정

**설치:**
```bash
# ArgoCD 네임스페이스 생성
kubectl create namespace argocd

# ArgoCD 설치
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# CLI 설치
# macOS
brew install argocd
# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/

# 초기 비밀번호 확인
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**UI 접근:**
```bash
# 포트 포워딩
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 브라우저: https://localhost:8080
# ID: admin, PW: (위에서 확인한 비밀번호)
```

### 8.3 Application 정의

**kustomize 기반 Application:**
```yaml
# infra/argocd/applications/app-production.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-production
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: https://github.com/org/deploy-repo.git
    targetRevision: main
    path: infra/k8s/overlays/production

  destination:
    server: https://kubernetes.default.svc
    namespace: prj-01-prod

  syncPolicy:
    automated:
      prune: true      # 삭제된 리소스 자동 정리
      selfHeal: true   # 수동 변경 시 자동 복구
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

**Helm 기반 Application:**
```yaml
# infra/argocd/applications/app-helm.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-helm
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://github.com/org/deploy-repo.git
    targetRevision: main
    path: infra/helm/apps/app-name
    helm:
      valueFiles:
        - values-prod.yaml

  destination:
    server: https://kubernetes.default.svc
    namespace: prj-01-prod
```

### 8.4 App of Apps 패턴

**여러 앱을 하나의 Application으로 관리:**
```yaml
# infra/argocd/applications/app-of-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/deploy-repo.git
    targetRevision: main
    path: infra/argocd/applications
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**디렉터리 구조:**
```
infra/argocd/
├── applications/
│   ├── app-of-apps.yaml        # 루트 Application
│   ├── app-production.yaml     # 프로덕션 앱
│   ├── app-staging.yaml        # 스테이징 앱
│   └── monitoring.yaml         # 모니터링 스택
└── projects/
    └── default.yaml            # AppProject 정의 (선택적)
```

### 8.5 GitOps 배포 워크플로우

**표준 배포 흐름:**
```
[App Repo]              [Deploy Repo]              [k3s Cluster]
    │                        │                          │
    │ 1. git push            │                          │
    │ 2. CI: build, test     │                          │
    │ 3. GHCR push           │                          │
    │    (v1.2.3)            │                          │
    │                        │                          │
    │ 4. PR/커밋             │                          │
    │    (이미지 태그 변경)   │                          │
    │                        │                          │
    └───────────────────────▶│                          │
                             │ 5. git push              │
                             │    (main 브랜치)          │
                             │                          │
                             │                          │
                             │ ◀───────────────────────│
                             │   6. ArgoCD 감지          │
                             │   7. Auto Sync           │
                             │                          │
                             │                          ▼
                             │                    [배포 완료]
                             │                    [상태: Synced]
```

**이미지 태그 업데이트 자동화 (선택적):**
```yaml
# App 레포의 .github/workflows/update-deploy.yml
name: Update Deploy Repo

on:
  push:
    tags:
      - 'v*'

jobs:
  update-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout deploy repo
        uses: actions/checkout@v4
        with:
          repository: org/deploy-repo
          token: ${{ secrets.DEPLOY_REPO_TOKEN }}

      - name: Update image tag
        run: |
          cd infra/k8s/overlays/staging
          kustomize edit set image ghcr.io/org/app=ghcr.io/org/app:${{ github.ref_name }}

      - name: Commit and push
        run: |
          git config user.name "github-actions"
          git config user.email "github-actions@github.com"
          git add .
          git commit -m "chore: bump app to ${{ github.ref_name }}"
          git push
```

### 8.6 롤백 및 복구

**ArgoCD 롤백:**
```bash
# 히스토리 확인
argocd app history app-production

# 특정 revision으로 롤백
argocd app rollback app-production <REVISION>

# 또는 Git revert 후 자동 동기화
git revert HEAD
git push
# ArgoCD가 자동으로 이전 상태로 동기화
```

**수동 동기화 (automated 비활성화 시):**
```bash
# 동기화 실행
argocd app sync app-production

# 특정 리소스만 동기화
argocd app sync app-production --resource apps:Deployment:app
```

### 8.7 ArgoCD + Kustomize + SealedSecrets 통합

**전체 워크플로우:**
```
1. 개발자: kubeseal로 Secret 암호화
2. Git push: SealedSecret 커밋
3. ArgoCD: 변경 감지 및 동기화
4. SealedSecrets Controller: SealedSecret → Secret 복호화
5. Deployment: Secret 참조하여 Pod 시작
```

**Application에서 SealedSecrets 포함:**
```yaml
# ArgoCD Application이 base와 secrets를 모두 동기화
spec:
  source:
    path: infra/k8s/overlays/production
    # kustomization.yaml에서 SealedSecrets 포함
```

**kustomization.yaml:**
```yaml
# infra/k8s/overlays/production/kustomization.yaml
resources:
  - ../../base
  - ../../../_shared/secrets/sealed/app-secrets.yaml
```

---

## 부록 A: 문서 간 교차 참조 매핑

### A.1 메인 아키텍처와의 연결

| 메인 아키텍처 섹션 | 본 문서 섹션 | 설명 |
|------------------|------------|------|
| [[k8s_architecture.md]] 1.1절 | 본 문서 1.2절 | 책임 분리 원칙 → Deploy 레포 책임 구체화 |
| [[k8s_architecture.md]] 1.3절 | 본 문서 2절 | 서버 기준 철학 → 디렉터리 구조 구현 |
| [[k8s_architecture.md]] 3절 | 본 문서 전체 | Deploy Template → 상세 구조 정의 |

### A.2 App Sub Architecture와의 인터페이스

| Deploy의 책임 (본 문서) | App의 책임 | 연결 포인트 |
|----------------------|-----------|-----------|
| 환경변수 값 제공 (2.2절) | 환경변수 스키마 정의 | [[k8s_app_architecture.md]] 5.2절 |
| 이미지 태그 선택 (3.1절) | GHCR 이미지 태깅 | [[k8s_app_architecture.md]] 4.2절 |
| 외부 포트 매핑 (2.2절) | 내부 포트 정의 | [[k8s_app_architecture.md]] 5.4절 |
| 로그 수집/저장 (2.2절) | 로그 stdout 출력 | [[k8s_app_architecture.md]] 5.3절 |

### A.3 템플릿 디렉터리 매핑

| 본 문서 참조 | 템플릿 내 위치 | 실제 Deploy 레포 |
|-----------|-------------|----------------|
| 2.1절 루트 구조 | `infra/` | `deploy-repo/` |
| 2.2절 `k8s/base/` | `infra/k8s/base/` | `deploy-repo/k8s/base/` |
| 2.2절 `k8s/overlays/` | `infra/k8s/overlays/` | `deploy-repo/k8s/overlays/` |
| 2.2절 `_shared/` | `infra/_shared/` | `deploy-repo/_shared/` |
| 2.2절 `monitoring/` | `infra/_shared/monitoring/` | `deploy-repo/_shared/monitoring/` |
| 2.2절 `scripts/` | `infra/_shared/scripts/` | `deploy-repo/_shared/scripts/` |
| 3절 GHCR 이미지 | kustomize images에서 참조 | `ghcr.io/org/app:tag` |
| 6절 Secrets | `infra/_shared/secrets/sealed/` | SealedSecret 저장 |
| 8절 ArgoCD | `infra/argocd/applications/` | Application 정의 |

### A.4 책임 경계 요약

```
[App Sub Architecture]           [Deploy Sub Architecture]
(본 문서와 상호 보완)              (본 문서)
         │                              │
         ├── 이미지 생산 ─────────────▶ ├── 이미지 소비
         ├── 환경변수 스키마 ──────────▶ ├── 환경변수 값
         ├── 내부 포트 ───────────────▶ ├── 외부 포트 매핑
         └── 빌드/태깅 ───────────────▶ └── Pull/실행
         
         연결 인터페이스: GHCR 이미지 태그
         ghcr.io/org/app:v1.2.3
```

---

## 부록 B: 디렉터리별 .gitignore 규칙

아래 예시의 `docker-compose.local.yml` 항목은 역사적 호환용이며, Docker Compose는 지원되는 실행 모델이 아니다. 런타임은 k3s/Kubernetes만 대상으로 한다.

```gitignore
# === Kubernetes 관련 ===

# 평문 Secret 파일 (SealedSecret만 커밋)
**/secrets/*.secret.yaml
**/secrets/plain/

# kubeconfig (로컬)
kubeconfig
*.kubeconfig
.kube/

# Helm 임시 파일
**/charts/*.tgz
**/Chart.lock

# kustomize 빌드 출력
**/kustomize-build/
*.rendered.yaml

# === 레거시 (호환성) ===

# environments/ 내 민감 파일
environments/**/.env.local
environments/**/secrets/

# 로컬 오버라이드 (선택적)
**/docker-compose.local.yml

# 스크립트 실행 로그
scripts/**/*.log

# 임시 파일
**/.tmp/
**/tmp/

# SOPS 키 파일
*.agekey
keys.txt
```

---

## 부록 C: k8s 명령어 빠른 참조

### C.1 기본 kubectl 명령어

```bash
# 리소스 조회
kubectl get pods,svc,deploy -n prj-01
kubectl get all -n prj-01

# 상세 정보
kubectl describe pod <pod-name> -n prj-01
kubectl describe deployment app -n prj-01

# 로그 확인
kubectl logs <pod-name> -n prj-01
kubectl logs -f <pod-name> -n prj-01  # 실시간
kubectl logs <pod-name> -c <container> -n prj-01  # 특정 컨테이너

# Pod 접속
kubectl exec -it <pod-name> -n prj-01 -- /bin/sh
```

### C.2 배포 관련 명령어

```bash
# kustomize 배포
kubectl apply -k infra/k8s/overlays/production/

# Helm 배포
helm upgrade --install app infra/helm/apps/app -f values-prod.yaml -n prj-01

# 롤아웃 상태
kubectl rollout status deployment/app -n prj-01

# 롤백
kubectl rollout undo deployment/app -n prj-01

# 히스토리
kubectl rollout history deployment/app -n prj-01
```

### C.3 디버깅 명령어

```bash
# Pod 이벤트 확인
kubectl get events -n prj-01 --sort-by='.lastTimestamp'

# 리소스 사용량
kubectl top pods -n prj-01
kubectl top nodes

# 임시 Pod으로 디버깅
kubectl run debug --rm -it --image=busybox -n prj-01 -- sh

# Secret 확인 (base64 디코딩)
kubectl get secret app-secrets -n prj-01 -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
```

### C.4 ArgoCD 명령어

```bash
# 앱 목록
argocd app list

# 동기화 상태
argocd app get app-production

# 수동 동기화
argocd app sync app-production

# 롤백
argocd app rollback app-production <REVISION>

# 앱 삭제
argocd app delete app-production
```

---
