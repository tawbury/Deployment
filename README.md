# Kubernetes K3s Deployment 프로젝트

이 프로젝트는 Kubernetes(K3s) 및 컨테이너 기반 인프라 구축을 위한 통합 관리 저장소입니다. ArgoCD를 통한 GitOps 방식의 배포와 모니터링 스택을 포함하고 있습니다.

## 📋 목차

- [프로젝트 개요](#프로젝트-개요)
- [프로젝트 구조](#프로젝트-구조)
- [빠른 시작](#빠른-시작)
- [주요 구성 요소](#주요-구성-요소)
- [인프라 설정](#인프라-설정)
- [배포 가이드](#배포-가이드)
- [개발 가이드](#개발-가이드)

## 프로젝트 개요

이 템플릿은 다음을 제공합니다:

- **GitOps 기반 배포**: ArgoCD를 활용한 Kubernetes 선언적 배포 관리
- **다중 환경 지원**: `base` 및 `overlays` 구조를 통한 환경별 설정 관리 (Production/Staging)
- **모니터링 스택**: Prometheus, Grafana, Alertmanager 통합
- **데이터베이스 마이그레이션**: PostgreSQL 기반 스키마 관리
- **애플리케이션 컨테이너화**: `observer`, `qts` 등 핵심 엔진의 Docker 빌드 및 배포 설정
- **데이터베이스 인프라**: PostgreSQL (Bitnami Helm 기반 또는 자체 정의) 및 PVC 관리

## 프로젝트 구조

```
Deployment/
├── app/                            # 애플리케이션 Docker 빌드 환경
│   ├── observer/                   # Observer 엔진 Dockerfile 및 설정
│   └── qts/                        # QTS 엔진 관련 설정
│
├── infra/                          # 인프라 설정 (K8s & Shared)
│   ├── k8s/                        # Kubernetes 매니페스트 (Kustomize 구조)
│   │   ├── base/                   # 기본 리소스 정의 (모든 환경 공통)
│   │   │   ├── deployments/        # 애플리케이션 및 DB 배포 (postgres, observer 등)
│   │   │   ├── services/           # 로드밸런서 및 내부 서비스 설정
│   │   │   ├── ingress/            # 접근 제어를 위한 Ingress 설정
│   │   │   ├── pvc/                # 퍼시스턴트 볼륨 클레임 (데이터 저장소)
│   │   │   ├── configmaps/         # 공통 설정값
│   │   │   ├── namespaces/         # 네임스페이스 정의
│   │   │   ├── monitoring/         # Prometheus/Grafana K8s 리소스
│   │   │   ├── sealed-secrets/     # 보안을 위해 암호화된 시크릿
│   │   │   └── kustomization.yaml  # Kustomize 설정
│   │   └── overlays/               # 환경별 오버라이드 설정
│   │       └── production/         # 프로덕션 환경 전용 설정 (ArgoCD 참조점)
│   │
│   ├── _shared/                    # 레거시 및 공통 공유 리소스
│   │   ├── monitoring/             # 독립 실행형 모니터링 설정 (Prometheus.yml 등)
│   │   ├── migrations/             # DB 초기화 및 마이그레이션 SQL
│   │   └── secrets/                # 로컬 테스트용 시크릿 (Git 비포함)
│   └── _legacy/                    # 이전 버전 호환용 설정
│
├── .github/                        # CI/CD 자동화 (GitHub Actions)
│   └── workflows/                  # 이미지 빌드 및 자동 태깅 워크플로우
│
├── docs/                           # 설치 및 운영 가이드 문서
├── ops/                            # 운영 지원 스크립트
├── tests/                          # 인프라 검증용 테스트 코드
└── README.md                       # 이 파일
```

## 빠른 시작

### 1. 사전 요구사항

- **Kubernetes**: K3s 또는 표준 K8s 클러스터
- **Tools**: `kubectl`, `kustomize`
- **GitOps**: ArgoCD (권장)

### 2. Kustomize를 이용한 로컬 빌드 테스트

```bash
# base 리소스 빌드 확인
kubectl kustomize infra/k8s/base

# production 오버레이 빌드 확인
kubectl kustomize infra/k8s/overlays/production
```

### 3. ArgoCD를 통한 배포

이 저장소를 ArgoCD의 소스(Repository URL)로 등록하고, `infra/k8s/overlays/production` 경로를 대상으로 애플리케이션을 생성합니다.

## 주요 구성 요소

### 애플리케이션 이미지 (`app/`)
- 핵심 서비스 엔진의 Docker 이미지를 빌드하기 위한 환경입니다.
- GitHub Actions를 통해 빌드된 이미지는 GHCR에 저장됩니다.

### Kubernetes 인프라 (`infra/k8s/`)
- **Base**: 모든 환경에서 공통적으로 사용되는 리소스의 원형입니다.
- **Overlays**: 특정 환경(Production 등)에 맞게 CPU/Memory 제한, 인스턴스 수, 호스트네임 등을 변경합니다.

### 데이터 관리 및 지속성
- **PVC**: `/opt/platform/runtime/` 경로의 영구 저장소를 관리합니다.
- **Sealed Secrets**: Git 저장소에 안전하게 시크릿을 저장하기 위해 `sealed-secrets`를 사용합니다.

## 인프라 설정

### 모니터링
Kubernetes 내부의 `infra/k8s/base/monitoring` 설정을 통해 클러스터 리소스와 애플리케이션 메트릭을 수집합니다.

### 로깅 및 스토리지
애플리케이션 로그는 각 PVC에 마운트된 경로(`.../logs/`)에 저장되며, 호스트 서버의 실제 경로와 매핑됩니다.

## 배포 가이드

자세한 배포 프로세스는 [docs/README.md](docs/README.md)를 참조하십시오.

## 🔄 변경 이력

| 날짜 | 버전 | 변경 사항 |
|------|------|---------|
| 2026-02-04 | v2.0 | Kubernetes (K3s) 및 Kustomize 기반 구조로 전면 개편 |
| 2026-01-27 | v1.1 | 공통 리소스를 `infra/_shared/`로 통합 |
| 2026-01-27 | v1.0 | 초기 템플릿 구조 생성 |

---

**마지막 업데이트**: 2026-02-04
