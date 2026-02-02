<!-- Document Metadata -->
- Document Name: App Repository Architecture
- File Name: k8s_app_architecture.md
- Document ID: ARCH-APP-SUB-001
- Status: Active
- Version: 2.0.0
- Created Date: 2026-02-02
- Last Updated: 2026-02-02
- Author: {{USER}}
- Reviewer: {{REVIEWER}}
- Parent Document: [[k8s_architecture.md]] (ARCH-DEPLOY-001)
- Related Reference: [[k8s_sub_architecture.md]] (ARCH-DEPLOY-SUB-001)
- Change Summary:
  - App 레포 책임 범위 및 경계 정의
  - App 레포 로컬 디렉터리 표준 구조 수립
  - GHCR 이미지 빌드 및 태깅 전략 명세
  - App ↔ Deploy 인터페이스 규칙 정의
  - Observer / QTS 공통 원칙 및 QTS 특이 사항 명시
  - v1.1.0: 템플릿 프로젝트 구조 반영, 문서 간 연결 매핑 강화
  - 메타데이터 파일 최상단 배치 (H1 위)
  - GHCR latest 태그 설계상 배제 톤 정정
  - DB 마이그레이션 책임 경계 명확화 (App: 로직·명령어·스키마 / Deploy: 시점·적용 여부·순서)
  - release.yml 역할 명확화 (이미지 재빌드·릴리스 트리거)
  - App Repository 로컬 폴더 구조 섹션 보강 (필수 요소·설계 원칙·Deploy와 경계)
  - **v2.0.0: k3s(경량 Kubernetes) 기반 배포 친화적 설계 반영**
    - 역사: docker-compose에서 Kubernetes manifests (kustomize/Helm)로 전환
    - k8s Probe 엔드포인트 (readiness/liveness) 설계 가이드 추가
    - Graceful Shutdown (SIGTERM) 처리 가이드 추가
    - 12-Factor App 원칙 강화
    - k8s 환경 장애 복원성 (PodDisruptionBudget, Resource Limits) 설계 추가
<!-- End Metadata -->

---

# App Repository Architecture

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
         ├─▶ [App Repository Architecture] ◀─ 본 문서
         │   k8s_app_architecture.md (ARCH-APP-SUB-001)
         │   ├── App 레포 책임 구체화
         │   ├── 디렉터리 구조 표준화
         │   ├── 빌드/태깅 전략 상세
         │   ├── App → Deploy 인터페이스 정의
         │   └── k8s 배포 친화적 설계 (Probe, Graceful Shutdown)
         │
         └─▶ [Deploy 서브 아키텍처]
             k8s_sub_architecture.md (ARCH-DEPLOY-SUB-001)
             ├── Deploy 레포 k8s manifests 구조
             ├── 이미지 핸들링 규칙 (kustomize)
             ├── GitOps 배포 파이프라인
             └── k8s 네이티브 모니터링
```

**템플릿 내 참조:**
- App 레포 예시: `app/prj_*/` (실제로는 독립 Git 레포)
- Deploy 레포 구조: `infra/k8s/`, `infra/helm/` (k8s manifests)
- 아키텍처 문서: `docs/arch/`

---

## 목차

1. [App Repository Architecture 개요](#1-app-repository-architecture-개요)
2. [App 레포 책임 범위 정의](#2-app-레포-책임-범위-정의)
3. [App Repository 로컬 디렉터리 표준 구조](#3-app-repository-로컬-디렉터리-표준-구조)
4. [GHCR 이미지 빌드 및 태깅 전략](#4-ghcr-이미지-빌드-및-태깅-전략)
5. [App ↔ Deploy 인터페이스 규칙](#5-app--deploy-인터페이스-규칙)
6. [k8s 배포 친화적 설계](#6-k8s-배포-친화적-설계)
7. [프로젝트 공통 원칙 및 특수 요구사항](#7-프로젝트-공통-원칙-및-특수-요구사항)
8. [변경 및 확장 시 책임 분리 기준](#8-변경-및-확장-시-책임-분리-기준)
9. [금지 사항](#9-금지-사항)

---

## 1. App Repository Architecture 개요

> **템플릿 프로젝트 참고**: 본 문서는 App 레포 구조와 책임을 정의합니다. 현재 Kubernetes_k8s 템플릿의 `app/` 디렉터리는 참조용이며, 실제 프로젝트에서는 독립적인 Git 레포지토리로 분리해야 합니다. 메인 아키텍처([[k8s_architecture.md]])의 원칙을 참조하며, Deploy 레포와의 경계는 [[k8s_sub_architecture.md]]와 상호 보완 관계로 유지한다.

### 1.1 메인/Deploy 아키텍처와의 관계

본 문서는 **[[k8s_architecture.md]] (ARCH-DEPLOY-001)의 하위 문서**이다.

**메인 아키텍처와의 관계:**
```
k8s_architecture.md (메인)
         │
         ├── 1.1절: 책임 분리 원칙
         │   └─▶ 본 문서 2절에서 App 레포 책임 구체화
         │
         ├── 1.2절: GHCR 기반 CI/CD 흐름
         │   └─▶ 본 문서 4절에서 빌드/태깅 전략 상세화
         │
         └── 2절: App Template 서브 아키텍처
             └─▶ 본 문서 3절에서 디렉터리 구조 표준 정의
```

**메인 아키텍처에서 정의된 전제 조건:**
- App 레포는 "무엇을 실행할 것인가"에 대한 답을 가진다 → 본 문서 2절 참조
- Deploy 레포는 "어디서, 어떻게 실행할 것인가"에 대한 답을 가진다 → [[k8s_sub_architecture.md]] 참조
- 두 레포는 GHCR 이미지 태그라는 단일 인터페이스로만 연결된다 → 본 문서 5절 참조

**Deploy Sub Architecture와의 관계:**

본 문서는 **[[k8s_sub_architecture.md]] (ARCH-DEPLOY-SUB-001)와 상호 보완 관계**에 있다.

| 관점 | App Sub Architecture (본 문서) | Deploy Sub Architecture |
|------|------------------------------|-------------------------|
| **관심사** | 이미지 생산 (Image Producer) | 이미지 소비 (Image Consumer) |
| **책임 종료점** | GHCR에 이미지 푸시 완료 시 | 컨테이너 실행 및 운영 |
| **환경변수** | 스키마 정의 (키 목록, 형식) | 실제 값 제공 (환경별) |
| **GHCR 태깅** | 태그 생성 및 푸시 | 태그 선택 및 Pull |
| **디렉터리** | 템플릿: `app/prj_*/` | 템플릿: `infra/` |

**교차 참조:**
- App의 환경변수 스키마 → Deploy에서 실제 값 제공 (본 문서 5.2절, [[k8s_sub_architecture.md]] 3.4절)
- App의 이미지 태깅 → Deploy에서 태그 선택 (본 문서 4.2절, [[k8s_sub_architecture.md]] 3.1절)
- App의 포트 정의 → Deploy에서 포트 매핑 (본 문서 5.4절, [[k8s_sub_architecture.md]] 2.2절)

### 1.2 App 레포의 역할 정의

App 레포는 **이미지 생산자(Image Producer)**로서 다음 역할을 수행한다:

```
[App Repo의 역할]
    │
    ├── 소스 코드 관리
    │   └── 비즈니스 로직, 서비스 코드의 단일 진실 공급원
    │
    ├── 빌드 정의
    │   └── Dockerfile, 의존성, 빌드 스크립트 소유
    │
    ├── 이미지 생성
    │   └── CI를 통한 컨테이너 이미지 빌드 및 GHCR 푸시
    │
    ├── 품질 보증
    │   └── 테스트, 린팅, 정적 분석 실행
    │
    └── 설정 스키마 제공
        └── 환경변수 목록, 설정 형식 정의 (값 아님)
```

App 레포는 이미지가 GHCR에 푸시된 시점에서 책임이 종료된다. 이후의 배포, 실행, 운영은 Deploy 레포의 책임이다. CI 산출물은 컨테이너 이미지뿐이며, 스케일링·네트워킹·영속성 등 런타임 관리는 App 책임이 아니다.

---

## 2. App 레포 책임 범위 정의

### 2.1 App 레포가 책임지는 것

| 책임 영역 | 수행 내용 |
|----------|----------|
| 애플리케이션 소스 코드 | 비즈니스 로직, 서비스 코드 전체를 관리한다 |
| Dockerfile | 이미지 빌드 방법을 정의한다 |
| 의존성 정의 | requirements.txt, package.json 등 패키지 의존성을 관리한다 |
| 빌드 스크립트 | 멀티 스테이지 빌드, 빌드 최적화 스크립트를 포함한다 |
| CI 파이프라인 | 빌드, 테스트, GHCR 푸시 워크플로우를 정의한다 |
| 테스트 코드 | 단위 테스트, 통합 테스트, E2E 테스트를 포함한다 |
| 환경변수 스키마 | 필요한 환경변수 목록과 형식을 정의한다 |
| DB 마이그레이션 로직·명령어·스키마 | 마이그레이션 로직, 실행 명령어, 스키마 정의를 포함한다 (실행 시점·순서는 Deploy 책임) |
| 애플리케이션 문서 | README, API 문서, 아키텍처 설명을 제공한다 |
| 헬스체크 엔드포인트 | 컨테이너 상태 확인용 엔드포인트를 구현한다 |
| 로그 출력 형식 | 표준 출력으로 로그를 출력하는 방식을 정의한다 |

### 2.2 App 레포가 책임지지 않는 것

| 금지 영역 | 이유 | 책임 주체 |
|----------|------|----------|
| Kubernetes manifests | Deployment, Service 등 k8s 리소스는 배포 영역이다 | Deploy 레포 |
| docker-compose.yml | 컨테이너 오케스트레이션은 배포 영역이다 | Deploy 레포 |
| 실제 환경변수 값 | ConfigMap/Secret으로 배포 시점에 주입한다 | Deploy 레포 |
| PVC/볼륨 마운트 | PersistentVolumeClaim 정의는 배포 영역이다 | Deploy 레포 |
| Service/Ingress | 네트워크 노출은 배포 영역이다 | Deploy 레포 |
| 배포 스크립트 | kubectl apply, helm upgrade는 배포 영역이다 | Deploy 레포 |
| 서버 IP/도메인 | 인프라 정보는 배포 영역이다 | Deploy 레포 |
| 시크릿 값 | SealedSecrets/SOPS로 배포 시점에 주입한다 | Deploy 레포 |
| Ingress Controller 설정 | traefik, nginx-ingress는 인프라 영역이다 | Deploy 레포 |
| ServiceMonitor 설정 | kube-prometheus-stack 연동은 인프라 영역이다 | Deploy 레포 |

스케일링, 네트워킹, 영속성 등 런타임 관리는 Deploy 레포 책임이며, App은 이에 대한 제어를 하지 않는다.

---

## 3. App Repository 로컬 디렉터리 표준 구조

### 3.1 App Repository 기본 로컬 디렉터리 구조 (필수 요소)

Observer / QTS 등 **App Template 기준**으로 공통 사용 가능한 구조이다. 모든 App 레포는 동일한 디렉터리 템플릿을 따르며, 비즈니스 로직만 다르고 구조적 일관성을 유지한다.

**필수 포함 요소:**

| 요소 | 위치 | 역할 |
|------|------|------|
| Dockerfile | `docker/` | 프로덕션 이미지 빌드 정의 |
| 이미지 빌드 관련 스크립트 | `docker/`, `scripts/` | 빌드 전용 스크립트 (멀티 스테이지, 최적화 등) |
| 앱 실행 엔트리포인트 | `src/{app}/main.py` 등 | 컨테이너 내 실행 진입점 |
| DB 마이그레이션 디렉터리 | `migrations/` | 마이그레이션 로직·스키마 (해당 시) |
| 설정과 코드 분리 | `config/` vs `src/` | 설정 스키마(`.env.example`)와 소스 코드 명확 분리 |
| App 레포 전용 CI | `.github/workflows/` | 빌드·테스트·GHCR 푸시만 (배포 워크플로우 제외) |

```
{app-name}/                     # App Template 기준, 신규 앱 시 복사 가능
├── .github/
│   └── workflows/              # App 레포 전용: 빌드·테스트·이미지 푸시만
│       ├── build.yml           # 이미지 빌드 및 푸시
│       ├── test.yml            # 테스트 실행
│       └── release.yml         # 릴리스 트리거: 태그 푸시 시 이미지 재빌드·푸시
├── src/
│   ├── {app}/                  # 메인 애플리케이션 패키지
│   │   ├── __init__.py
│   │   ├── main.py             # 진입점 (앱 실행 엔트리포인트)
│   │   ├── config.py           # 설정 로더
│   │   └── ...                 # 비즈니스 로직
│   └── shared/                 # 공유 유틸리티 (선택적)
├── tests/
│   ├── unit/                   # 단위 테스트
│   ├── integration/            # 통합 테스트
│   └── fixtures/               # 테스트 픽스처
├── migrations/                 # DB 마이그레이션 로직·스키마 (해당 시)
├── docker/
│   ├── Dockerfile              # 프로덕션 이미지 빌드 (빌드용만, 오케스트레이션 없음)
│   ├── entrypoint.sh           # 컨테이너 진입 스크립트 (필요 시)
│   └── Dockerfile.dev          # 개발용 이미지 (선택적)
├── config/
│   ├── .env.example            # 환경변수 스키마 (설정과 코드 분리)
│   └── settings.schema.json    # 설정 스키마 (선택적)
├── docs/
│   ├── README.md               # 프로젝트 개요
│   ├── ARCHITECTURE.md         # 내부 아키텍처
│   └── API.md                  # API 문서 (해당 시)
├── scripts/
│   └── dev/                    # 개발용 스크립트만 (배포 스크립트 없음)
├── pyproject.toml              # 언어별 상이
├── requirements.txt            # 프로덕션 의존성 (언어별 상이)
├── requirements-dev.txt        # 개발 의존성 (언어별 상이)
└── .gitignore
```

### 3.2 구조 설계 원칙

- **App 레포는 이미지를 “생산”하는 레포이다.**  
  책임은 GHCR에 이미지가 푸시될 때까지이며, 이후 실행·배포는 Deploy 레포 책임이다.

- **Deploy 레포와의 유일한 인터페이스는 GHCR 이미지(불변 태그)이다.**  
  파일 공유, API, 이벤트 연동 등은 하지 않는다.

- **로컬 실행·CI 실행·배포 실행 간 구조가 최대한 동일해야 한다.**  
  같은 소스·같은 Dockerfile로 로컬/CI에서 빌드 가능하고, 배포 시에는 해당 이미지 태그만 참조한다.

- **신규 앱 생성 시 위 구조를 복사 가능한 템플릿으로 사용한다.**  
  디렉터리 이름·역할을 바꾸지 않고, 앱 이름·비즈니스 로직만 치환한다.

### 3.3 Deploy 레포와 중복되지 않도록 할 것

- **Kubernetes manifests 및 컨테이너 오케스트레이션은 Deploy 레포 책임이다.**
  App 레포에는 Deployment, Service, ConfigMap, kustomization.yaml, Helm chart, 배포 스크립트를 두지 않는다.

- **App 레포 내 docker 관련 파일은 빌드용에 한한다.**
  - 포함: **Dockerfile**, **entrypoint**(컨테이너 내 진입 스크립트), **.dockerignore**, 빌드 전용 스크립트.
  - 미포함: Kubernetes manifests, Helm charts, kustomize 설정, 환경별 실행 설정, 배포용 스크립트.

- **실행 오케스트레이션(replicas, resources, PVC, Service, Ingress 등)은 App 레포에 두지 않는다.**
  [[k8s_sub_architecture.md]]에서 정의한 Deploy 레포의 `k8s/`, `helm/` 구조만이 실행 방식을 소유한다.

### 3.4 각 디렉터리의 단일 책임 원칙

#### `.github/workflows/`

**책임:** App 레포의 빌드, 테스트, 이미지 푸시 워크플로우만 포함한다.

| 포함하는 것 | 포함하지 않는 것 |
|------------|----------------|
| 이미지 빌드 워크플로우 | 배포 트리거 워크플로우 |
| 테스트 실행 워크플로우 | 서버 배포 워크플로우 |
| GHCR 푸시 워크플로우 | 인프라 프로비저닝 |
| 코드 품질 검사 | 환경 설정 검증 |

**`release.yml` 역할:**  
릴리스용 **태그 푸시**(예: `v1.2.3`)를 **트리거**로, 해당 태그 기준 소스를 빌드하여 **이미지 재빌드 및 GHCR 푸시**를 수행한다. 단순 “태그 생성”이 아니라, **릴리스 이미지 생성을 유발하는 워크플로우**이다. 태그와 이미지는 1:1로 매핑되며, 배포 측은 이 불변 태그만 참조한다.

#### `src/`

**책임:** 실행 가능한 애플리케이션 코드만 포함한다.

**원칙:**
- 비즈니스 로직은 이 디렉터리에만 존재한다.
- 환경별 분기 코드를 포함하지 않는다.
- 서버 경로, IP 등 인프라 정보를 하드코딩하지 않는다.

#### `tests/`

**책임:** 테스트 코드와 테스트 데이터만 포함한다.

**원칙:**
- 프로덕션 코드와 명확히 분리한다.
- 외부 서비스 의존 테스트는 모킹으로 처리한다.
- 테스트는 환경 독립적으로 실행 가능해야 한다.

#### `docker/`

**책임:** 컨테이너 이미지 빌드에 필요한 파일만 포함한다.

| 포함하는 것 | 포함하지 않는 것 |
|------------|----------------|
| Dockerfile | docker-compose.yml |
| .dockerignore | 환경별 설정 파일 |
| 빌드 전용 스크립트 | 배포 스크립트 |

#### `config/`

**책임:** 환경변수 스키마와 설정 형식·기본값만 정의한다. 환경별 실제 값은 배포 레이어(Deploy)에서 주입하며, 애플리케이션은 런타임 인프라를 제어하지 않는다.

**원칙:**
- `.env.example`은 키 목록과 설명만 포함한다.
- 실제 값은 절대 포함하지 않는다.
- 기본값은 개발 환경에서만 의미 있는 값으로 설정한다.

#### `migrations/`

**책임:** DB 마이그레이션의 **로직, 실행 명령어, 스키마 정의**만 포함한다.

**책임 경계:**
- **App 레포:** 마이그레이션 **로직**(스크립트·코드), **실행 명령어**(어떤 명령으로 돌릴지), **스키마 정의**(테이블·컬럼 등).
- **Deploy 레포:** 마이그레이션 **실행 시점**(배포 전/후 등), **배포 흐름 내 적용 여부**, **실행 순서 제어**(다중 마이그레이션 순서).  
  → Deploy 레포는 마이그레이션 **로직/내용**을 포함하지 않으며, App이 제공한 명령·스크립트를 **언제·어떤 순서로** 실행할지만 담당한다.

#### `scripts/dev/`

**책임:** 개발 환경 설정 스크립트만 포함한다.

**원칙:**
- 프로덕션 배포 스크립트를 포함하지 않는다.
- 로컬 개발, 테스트 실행 편의 스크립트만 허용한다.

### 3.5 Dockerfile이 App 레포에 존재해야 하는 이유

Dockerfile은 App 레포의 `docker/` 디렉터리에 위치한다.

**이유 1: 소스 코드와 빌드 방법의 1:1 관계**
- 코드가 변경되면 빌드 방법도 변경될 수 있다.
- 동일 커밋에서 코드와 Dockerfile이 함께 버전 관리된다.
- 특정 버전 체크아웃 시 해당 시점의 정확한 빌드 방법을 얻는다.

**이유 2: CI 파이프라인의 자체 완결성**
- App 레포 하나만 체크아웃하면 빌드가 가능하다.
- 외부 레포 의존성 없이 이미지를 생성한다.
- 빌드 실패 시 원인 추적이 단순하다.

**이유 3: 롤백의 정확성**
- v1.2.3 태그 체크아웃 시 그 시점의 Dockerfile을 사용한다.
- 빌드 재현성이 보장된다.
- 과거 버전 이미지 재빌드가 가능하다.

**이유 4: 앱별 독립성**
- Observer와 QTS의 Dockerfile이 다를 수 있다.
- 각 앱이 자신의 빌드 방법을 소유한다.
- 빌드 최적화를 앱별로 독립적으로 수행한다.

---

## 4. GHCR 이미지 빌드 및 태깅 전략

### 4.1 이미지 빌드, 테스트, 푸시 책임 흐름

```
[코드 변경]
    │
    ▼
[Pull Request]
    │
    ├── 테스트 실행 (필수)
    ├── 린팅/정적 분석 (필수)
    └── 빌드 검증 (선택적)
    │
    ▼
[main 브랜치 머지]
    │
    ├── 테스트 재실행
    ├── 이미지 빌드
    └── GHCR 푸시 (sha 태그)
    │
    ▼
[릴리스 태그 푸시] (v1.2.3) → release.yml 트리거
    │
    ├── 이미지 재빌드 (해당 태그 기준 소스로 빌드)
    └── GHCR 푸시 (버전 태그)
    │
    ▼
[GHCR에 이미지 저장]
    │
    └── App 레포 책임 종료
```

CI는 컨테이너 이미지만 산출한다. 스케일링, 네트워킹, 영속성은 배포 레이어(Deploy) 책임이다.

### 4.2 불변 태그 정책

App 레포는 다음 태그 정책을 준수하여 이미지를 푸시한다:

| 트리거 | 생성 태그 | 용도 |
|--------|----------|------|
| main 브랜치 push | `sha-{commit-hash}` | 커밋 단위 추적, 디버깅 |
| 릴리스 태그 (v*) | `v1.2.3` | 프로덕션/스테이징 배포 |

**불변성 원칙:**
- 한 번 푸시된 버전 태그(v1.2.3)는 절대 덮어쓰지 않는다.
- sha 태그는 커밋 해시와 1:1 매핑되어 불변이다.
- 이미지 내용 변경이 필요하면 새 버전을 릴리스한다.

### 4.3 latest 태그: 설계상 배제

**원칙:** `latest` 태그는 **공식 배포 흐름에서 사용되지 않으며**, Deploy 레포는 `latest` 태그를 **절대 참조하지 않는다**.

**기술적 사실:**
- App 레포 CI는 `latest` 태그를 기술적으로 생성·푸시할 수 있다.
- 해당 태그는 가변(mutable)이며, 언제 어떤 이미지를 가리키는지 보장되지 않는다.
- 롤백 및 재현성이 불가능하므로, **설계상 공식 배포 경로에서는 배제**된다.

**규칙:**
- 공식 배포(Production, Staging) 및 배포 자동화에서는 **불변 태그(v1.2.3, sha-xxx)만 사용**한다.
- Deploy 레포의 k8s manifests 및 배포 스크립트는 `latest`를 참조하지 않는다.
- App 레포는 `.env.example` 등에서 `IMAGE_TAG=v1.0.0` 형태로 **버전 태그 사용**을 안내한다.

---

## 5. App ↔ Deploy 인터페이스 규칙

### 5.1 유일한 인터페이스: GHCR 이미지 태그

```
[App Repo]                           [Deploy Repo]
    │                                      │
    │   ghcr.io/org/observer:v1.2.3       │
    │ ─────────────────────────────────▶  │
    │                                      │
    │   (이것이 유일한 인터페이스)           │
    │                                      │
```

**인터페이스 규칙:**
- App 레포는 이미지 태그를 "생산"한다.
- Deploy 레포는 이미지 태그를 "소비"한다.
- 두 레포 간 직접적인 파일 참조, API 호출, 이벤트 연동은 없다.
- 이미지 태그만 알면 배포가 가능하다.

### 5.2 환경 변수 주입 책임

| 책임 주체 | 역할 |
|----------|------|
| App 레포 | 환경변수 스키마와 기본값만 정의한다 (키 목록, 형식, 필수 여부) |
| Deploy 레포 | 환경별 실제 값을 ConfigMap/Secret으로 런타임에 주입한다 |
- 환경변수 키 변경 시 SemVer 영향 명시
- 예 : breaking change: 키 제거/의미 변경 → major / additive: optional key 추가 → minor

**App 레포의 환경변수 정의 규칙:**

```
# config/.env.example (App 레포)

# Required: Database connection
DB_HOST=                    # 필수, Deploy에서 제공
DB_PORT=5432                # 선택, 기본값 있음
DB_NAME=                    # 필수, Deploy에서 제공
DB_USER=                    # 필수, Deploy에서 제공
DB_PASSWORD=                # 필수, 시크릿, Deploy에서 제공

# Required: API configuration
API_KEY=                    # 필수, 시크릿, Deploy에서 제공
API_ENDPOINT=               # 필수, Deploy에서 제공

# Optional: Logging
LOG_LEVEL=INFO              # 선택, 기본값 있음
LOG_FORMAT=json             # 선택, 기본값 있음
```

**원칙:**
- App 레포는 스키마와 기본값만 정의한다. 환경별 값은 배포 레이어에서 주입한다.
- 환경별로 달라지는 값은 절대 하드코딩하지 않는다.
- 시크릿 값은 App 레포에 절대 존재하지 않는다.

### 5.3 로그 출력 원칙

App 레포는 다음 로그 출력 원칙을 따른다:

| 원칙 | 설명 |
|------|------|
| 표준 출력 사용 | 모든 로그는 stdout/stderr로 출력한다 |
| 파일 직접 쓰기 금지 | 컨테이너 내부 파일에 로그를 쓰지 않는다 |
| 구조화된 형식 | JSON 형식 로그를 기본으로 한다 |
| 로그 레벨 환경변수화 | LOG_LEVEL 환경변수로 제어 가능하게 한다 |

**이유:**
- 로그 수집, 저장, 로테이션은 Deploy 레포의 책임이다.
- 컨테이너는 stateless여야 한다.
- 로그 경로 하드코딩은 서버 환경 의존성을 만든다.

### 5.4 포트/네트워크 원칙

| 원칙 | 설명 |
|------|------|
| 내부 포트만 정의 | App은 컨테이너 내부 포트만 알고 있다 |
| Service/Ingress 무관심 | k8s Service, Ingress 정의는 Deploy 레포의 책임이다 |
| 네트워크 정책 무관심 | NetworkPolicy 구성은 Deploy 레포의 책임이다 |
| 서비스 간 통신 | 환경변수로 주입받은 Service DNS를 사용한다 |

**App 레포에서 정의하는 것:**
- EXPOSE 8080 (Dockerfile) - 컨테이너 포트
- 환경변수 스키마에 SERVICE_PORT 정의

**Deploy 레포에서 정의하는 것 (상세는 [[k8s_sub_architecture.md]] 참조):**
```yaml
# k8s/base/services/app-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: app
spec:
  ports:
    - port: 80           # 클러스터 내부 접근 포트
      targetPort: 8080   # 컨테이너 포트
  selector:
    app: app

# k8s/base/ingress/app-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
spec:
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            backend:
              service:
                name: app
                port:
                  number: 80
```

**서비스 간 통신 (k8s DNS):**
- 같은 Namespace: `http://app:80`
- 다른 Namespace: `http://app.prj-01.svc.cluster.local:80`

### 5.5 App이 서버 환경을 알지 못해야 하는 이유

**원칙:** App 코드는 실행 환경에 대해 무지(environment-agnostic)해야 한다.

**이유 1: 동일 이미지의 다중 환경 배포**
- 하나의 이미지로 staging, production 모두 배포 가능해야 한다.
- 환경 차이는 환경변수로만 주입한다.

**이유 2: 테스트 용이성**
- 서버 환경 의존성이 없으면 로컬 테스트가 쉽다.
- CI 환경에서도 동일하게 동작한다.

**이유 3: 확장성**
- 새 서버 추가 시 App 레포 수정이 불필요하다.
- 클라우드 마이그레이션 시 App 레포 변경 없음.

**이유 4: 책임 분리**
- "무엇을 실행할 것인가"와 "어디서 실행할 것인가"의 명확한 분리.
- 각 레포의 변경 이유가 단일해진다.

---

## 6. k8s 배포 친화적 설계

> **App 레포의 책임**: 이 섹션에서 설명하는 Probe 엔드포인트, Graceful Shutdown, 12-Factor App 원칙은 **App 레포에서 구현**해야 하는 코드 수준의 설계이다. Deploy 레포는 이를 **활용**하여 Deployment manifest에 설정만 추가한다.

### 6.1 Kubernetes Probe 엔드포인트

k8s는 Pod의 상태를 확인하기 위해 Probe를 사용한다. App은 이 Probe에 응답하는 엔드포인트를 제공해야 한다.

**Probe 종류:**

| Probe | 용도 | 실패 시 동작 |
|-------|------|-------------|
| **readinessProbe** | 트래픽 수신 준비 여부 확인 | Service에서 제외 (트래픽 차단) |
| **livenessProbe** | 프로세스 정상 동작 여부 확인 | Pod 재시작 |
| **startupProbe** | 시작 완료 여부 확인 (느린 앱용) | 시작 실패 시 재시작 |

**App에서 구현해야 하는 엔드포인트:**

```python
# src/app/health.py

from fastapi import FastAPI, Response

app = FastAPI()

# Liveness: 프로세스가 살아있는지 확인
# - 간단한 응답만 반환
# - 외부 의존성 체크 하지 않음 (DB, Redis 등)
@app.get("/health/live")
def liveness():
    return {"status": "alive"}

# Readiness: 트래픽 처리 준비 완료 여부
# - 외부 의존성 연결 상태 확인
# - 초기화 완료 여부 확인
@app.get("/health/ready")
def readiness():
    # DB 연결 확인
    if not db.is_connected():
        return Response(status_code=503, content="DB not connected")

    # 캐시 연결 확인
    if not redis.is_connected():
        return Response(status_code=503, content="Redis not connected")

    return {"status": "ready"}

# Startup: 앱 시작 완료 여부 (선택적)
# - 초기 데이터 로딩 등 오래 걸리는 초기화 완료 확인
@app.get("/health/startup")
def startup():
    if not app.state.initialized:
        return Response(status_code=503, content="Still initializing")
    return {"status": "started"}
```

**Deploy에서 설정 (참조용):**
```yaml
# k8s/base/deployments/app.yaml (Deploy 레포)
spec:
  containers:
  - name: app
    livenessProbe:
      httpGet:
        path: /health/live
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 10
      failureThreshold: 3
    readinessProbe:
      httpGet:
        path: /health/ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 5
      failureThreshold: 3
    startupProbe:          # 느린 시작 앱용
      httpGet:
        path: /health/startup
        port: 8080
      initialDelaySeconds: 10
      periodSeconds: 10
      failureThreshold: 30  # 5분간 시작 대기
```

**Probe 설계 원칙:**

| 원칙 | 설명 |
|------|------|
| Liveness는 가볍게 | 외부 의존성 체크 없이 빠르게 응답 |
| Readiness는 철저하게 | 실제 트래픽 처리 가능 여부를 정확히 반영 |
| 적절한 타임아웃 | Probe 타임아웃을 초과하면 실패로 간주 |
| 멱등성 보장 | Probe 호출이 앱 상태에 영향을 주지 않음 |

### 6.2 Graceful Shutdown (SIGTERM 처리)

k8s는 Pod 종료 시 SIGTERM 신호를 보낸다. App은 이 신호를 받아 진행 중인 작업을 안전하게 완료해야 한다.

**Graceful Shutdown 시퀀스:**
```
1. kubectl delete pod / Rolling Update 시작
2. k8s가 Pod에 SIGTERM 전송
3. readinessProbe 실패 → Service에서 제외
4. App이 진행 중인 요청 완료
5. App 정상 종료
6. terminationGracePeriodSeconds 초과 시 SIGKILL
```

**App에서 구현:**

```python
# src/app/main.py

import signal
import sys
import asyncio

class GracefulShutdown:
    def __init__(self):
        self.shutdown_requested = False
        signal.signal(signal.SIGTERM, self._handle_sigterm)
        signal.signal(signal.SIGINT, self._handle_sigterm)

    def _handle_sigterm(self, signum, frame):
        print("SIGTERM received, starting graceful shutdown...")
        self.shutdown_requested = True

    async def wait_for_shutdown(self):
        while not self.shutdown_requested:
            await asyncio.sleep(0.1)

shutdown = GracefulShutdown()

# FastAPI/Uvicorn 예시
@app.on_event("shutdown")
async def on_shutdown():
    print("Closing database connections...")
    await db.close()
    print("Closing Redis connections...")
    await redis.close()
    print("Shutdown complete")

# 장기 실행 작업 (QTS 등)
async def trading_loop():
    while not shutdown.shutdown_requested:
        await process_trading_cycle()
        await asyncio.sleep(1)

    # Graceful shutdown: 진행 중인 주문 완료 대기
    await complete_pending_orders()
    await close_positions_safely()
```

**Deploy에서 설정 (참조용):**
```yaml
# k8s/base/deployments/app.yaml
spec:
  terminationGracePeriodSeconds: 60  # 기본 30초, 필요시 증가
  containers:
  - name: app
    lifecycle:
      preStop:
        exec:
          command: ["/bin/sh", "-c", "sleep 5"]  # 트래픽 드레인 대기
```

**Graceful Shutdown 원칙:**

| 원칙 | 설명 |
|------|------|
| 새 요청 거부 | SIGTERM 후 새 연결 수락 중지 |
| 진행 중 작업 완료 | 현재 처리 중인 요청은 완료 |
| 연결 정리 | DB, Redis, 외부 서비스 연결 종료 |
| 타임아웃 준수 | terminationGracePeriodSeconds 내 종료 |

### 6.3 12-Factor App 원칙 준수

k8s 환경에서 최적의 운영을 위해 12-Factor App 원칙을 따른다.

| Factor | 원칙 | App 레포에서 구현 |
|--------|------|------------------|
| **I. Codebase** | 버전 관리되는 하나의 코드베이스 | Git 레포 1개 = 앱 1개 |
| **II. Dependencies** | 명시적 의존성 선언 | requirements.txt, package.json |
| **III. Config** | 환경에 설정 저장 | 환경변수로 설정 주입 (ConfigMap) |
| **IV. Backing Services** | 외부 서비스를 리소스로 취급 | DB_HOST, REDIS_URL 환경변수 |
| **V. Build, Release, Run** | 빌드/릴리스/실행 분리 | Dockerfile, GHCR, k8s Deployment |
| **VI. Processes** | 무상태 프로세스 | 상태는 DB/Redis에 저장 |
| **VII. Port Binding** | 포트 바인딩으로 서비스 노출 | EXPOSE 8080, Service |
| **VIII. Concurrency** | 프로세스 모델로 확장 | replicas 증가로 스케일 아웃 |
| **IX. Disposability** | 빠른 시작, Graceful Shutdown | Probe, SIGTERM 처리 |
| **X. Dev/Prod Parity** | 개발/운영 환경 유사성 | 동일 이미지, ConfigMap 분리 |
| **XI. Logs** | 로그를 이벤트 스트림으로 | stdout/stderr, JSON 포맷 |
| **XII. Admin Processes** | 관리 작업을 일회성 프로세스로 | kubectl exec, Job 활용 |

**특히 중요한 원칙:**

```python
# Factor III: Config - 하드코딩 금지
# BAD
DB_HOST = "192.168.1.100"

# GOOD
import os
DB_HOST = os.environ.get("DB_HOST")

# Factor VI: Processes - 무상태
# BAD: 메모리에 세션 저장
sessions = {}

# GOOD: 외부 저장소 사용
session = redis.get(f"session:{session_id}")

# Factor XI: Logs - stdout으로 출력
# BAD
with open("/var/log/app.log", "a") as f:
    f.write(log_message)

# GOOD
import logging
logging.info(log_message)  # stdout으로 출력
```

### 6.4 k8s 환경 장애 복원성

App은 Pod 재시작, 리소스 제한 등 k8s 환경에서 발생하는 조건에 대해 **애플리케이션 코드 수준에서** 대응할 수 있도록 설계한다. 스케일링·네트워크·영속성 정책은 Deploy 레포 책임이며, App은 이에 대한 제어를 하지 않는다.

**Pod 재시작에 대한 복원력:**

```python
# 재시작 후 상태 복구
class AppState:
    def __init__(self):
        self.initialized = False

    async def initialize(self):
        # 외부 저장소에서 상태 복구
        self.last_processed_id = await redis.get("last_processed_id")
        self.pending_orders = await db.get_pending_orders()
        self.initialized = True

# 앱 시작 시 자동 복구
@app.on_event("startup")
async def startup():
    await state.initialize()
    # 중단된 작업 재개
    await resume_pending_work()
```

**리소스 제한 대응 (OOMKilled 방지):**

```python
# 메모리 사용량 모니터링
import psutil

def check_memory_usage():
    process = psutil.Process()
    memory_mb = process.memory_info().rss / 1024 / 1024

    if memory_mb > 800:  # 1GB limit의 80%
        # 캐시 정리, GC 강제 실행
        cache.clear()
        gc.collect()
        logging.warning(f"High memory usage: {memory_mb}MB")

# 큰 데이터 처리 시 스트리밍
async def process_large_data():
    # BAD: 전체 로드
    # data = await fetch_all_records()

    # GOOD: 청크 단위 처리
    async for chunk in fetch_records_chunked(size=1000):
        await process_chunk(chunk)
```

**네트워크 장애 대응:**

```python
import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=1, max=10)
)
async def call_external_api():
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get("http://external-service/api")
        return response.json()

# Circuit Breaker 패턴
class CircuitBreaker:
    def __init__(self, failure_threshold=5, recovery_timeout=30):
        self.failure_count = 0
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.last_failure_time = None
        self.state = "closed"  # closed, open, half-open

    async def call(self, func):
        if self.state == "open":
            if time.time() - self.last_failure_time > self.recovery_timeout:
                self.state = "half-open"
            else:
                raise CircuitOpenError()

        try:
            result = await func()
            self.failure_count = 0
            self.state = "closed"
            return result
        except Exception as e:
            self.failure_count += 1
            if self.failure_count >= self.failure_threshold:
                self.state = "open"
                self.last_failure_time = time.time()
            raise
```

**Deploy에서 활용 (참조용):**
```yaml
# k8s/base/deployments/app.yaml
spec:
  containers:
  - name: app
    resources:
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "1Gi"
        cpu: "500m"

---
# PodDisruptionBudget (Deploy 레포)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: app
```

### 6.5 메트릭 노출 (/metrics 엔드포인트)

Prometheus에서 수집할 수 있는 메트릭 엔드포인트를 제공한다.

```python
# src/app/metrics.py
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi import Response

# 메트릭 정의
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint']
)

# 비즈니스 메트릭
ORDERS_TOTAL = Counter(
    'trading_orders_total',
    'Total trading orders',
    ['side', 'symbol', 'status']
)

# 메트릭 엔드포인트
@app.get("/metrics")
def metrics():
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )
```

**메트릭 설계 원칙:**

| 원칙 | 설명 |
|------|------|
| RED 메트릭 | Rate(요청률), Errors(에러율), Duration(지연시간) |
| USE 메트릭 | Utilization(사용률), Saturation(포화도), Errors(에러) |
| 비즈니스 메트릭 | 도메인 특화 지표 (주문 수, 체결률 등) |
| 카디널리티 주의 | 레이블 조합 수 제한 (메모리 폭발 방지) |

---

## 7. 프로젝트 공통 원칙 및 특수 요구사항

> **용어 변경**: Observer/QTS → 프로젝트 일반 (템플릿은 다양한 유형의 프로젝트 지원)

### 7.1 공통 템플릿 준수 원칙

모든 App 레포는 다음 공통 원칙을 준수한다:

동일한 App Template 구조를 따를 대상: `app/prj_01/`, `app/prj_02/`, `app/prj_03/` 등.

| 원칙 | 설명 |
|------|------|
| 동일 디렉터리 구조 | 3.1절의 표준 구조를 따른다 |
| 동일 CI 워크플로우 패턴 | 빌드, 테스트, 푸시 흐름이 동일하다 |
| 동일 환경변수 형식 | .env.example 형식이 동일하다 |
| 동일 로그 출력 방식 | 구조화된 JSON 로그를 stdout으로 출력한다 |
| 동일 헬스체크 패턴 | /health 엔드포인트를 제공한다 |

**템플릿 버전 추적:**
- 각 앱 레포는 파생된 템플릿 버전을 기록한다.
- 템플릿 업데이트 시 영향받는 앱을 식별할 수 있다.

### 7.2 QTS(엔터프라이즈급 퀀트 매매 오토봇)의 안정성 요구사항

QTS는 실제 금전 거래를 수행하는 시스템으로, Observer보다 높은 안정성 요구사항을 가진다.

| 요구사항 | 설명 |
|---------|------|
| 무중단 실행 | 장기간 안정적으로 실행되어야 한다 |
| 빠른 장애 복구 | 장애 발생 시 자동 복구되어야 한다 |
| 상태 일관성 | 주문 상태, 포지션 정보의 일관성을 보장해야 한다 |
| 감사 추적 | 모든 거래 행위가 로깅되어야 한다 |

**App 레포에서 구현해야 하는 것:**

| 구현 항목 | 설명 |
|----------|------|
| Graceful Shutdown | SIGTERM 수신 시 진행 중인 작업을 안전하게 완료한다 |
| 재시작 복원력 | 재시작 후 이전 상태를 복구할 수 있다 |
| 헬스체크 엔드포인트 | 거래소 연결 상태, 주문 시스템 상태를 반환한다 |
| 구조화된 로깅 | 모든 거래 행위를 추적 가능하게 로깅한다 |
| 에러 분류 | 복구 가능/불가능 에러를 구분하여 처리한다 |

### 7.3 장기 실행 프로세스 설계 원칙

Observer와 QTS 모두 장기 실행 프로세스로 설계한다.

**상태 관리 원칙:**

| 원칙 | 설명 |
|------|------|
| 외부 상태 저장 | 컨테이너 내부에 상태를 저장하지 않는다 |
| DB/Redis 활용 | 영속 상태는 외부 저장소에 보관한다 |
| 재시작 안전성 | 언제든 재시작해도 상태를 복구할 수 있다 |

**연결 관리 원칙:**

| 원칙 | 설명 |
|------|------|
| 재연결 로직 | 외부 서비스 연결 끊김 시 자동 재연결한다 |
| 백오프 전략 | 재연결 시 지수 백오프를 적용한다 |
| 연결 상태 노출 | 헬스체크에 연결 상태를 포함한다 |

**리소스 관리 원칙:**

| 원칙 | 설명 |
|------|------|
| 메모리 누수 방지 | 장기 실행 시 메모리가 무한 증가하지 않는다 |
| 파일 디스크립터 관리 | 연결, 파일 핸들을 적절히 해제한다 |
| 주기적 상태 점검 | 내부 상태를 주기적으로 검증한다 |

### 7.4 장애 복원성 설계 원칙

**Crash-Only Design:**
- 정상 종료와 비정상 종료의 복구 경로가 동일하다.
- 복잡한 종료 절차 대신 재시작으로 복구한다.
- 상태는 항상 외부에 저장되어 있다.

**Idempotency (멱등성):**
- 동일 작업을 여러 번 실행해도 결과가 동일하다.
- 재시작 시 중복 처리를 방지한다.
- 주문 요청에 고유 ID를 부여하여 중복 주문을 방지한다.

**Circuit Breaker:**
- 외부 서비스 장애 시 빠르게 실패한다.
- 장애 전파를 방지한다.
- 복구 시 자동으로 정상 상태로 전환한다.

---

## 8. 변경 및 확장 시 책임 분리 기준

### 8.1 App 레포 수정으로 해결해야 하는 변경

| 변경 유형 | 예시 | App 레포 수정 내용 |
|----------|------|-------------------|
| 비즈니스 로직 변경 | 새 전략 추가, 알고리즘 수정 | src/ 코드 수정 |
| 새 환경변수 필요 | 새 외부 서비스 연동 | config/.env.example 수정, 코드에서 읽기 |
| 의존성 추가/변경 | 새 라이브러리 필요 | requirements.txt 수정, Dockerfile 수정 |
| API 엔드포인트 추가 | 새 헬스체크 항목 | src/ 코드 수정 |
| 빌드 방식 변경 | 멀티 스테이지 빌드 최적화 | docker/Dockerfile 수정 |
| 테스트 추가 | 새 기능 테스트 | tests/ 추가 |
| 로그 형식 변경 | 새 필드 추가 | src/ 로깅 코드 수정 |

### 8.2 Deploy 레포 수정으로 해결해야 하는 변경

| 변경 유형 | 예시 | Deploy 레포 수정 내용 |
|----------|------|---------------------|
| 환경변수 값 변경 | DB 호스트 변경, API 키 교체 | ConfigMap/Secret 수정 |
| replicas 변경 | 스케일 아웃 | `k8s/overlays/*/patches/replicas.yaml` |
| Service/Ingress 변경 | 외부 포트, 도메인 변경 | `k8s/base/services/`, `k8s/base/ingress/` |
| PVC 변경 | 스토리지 용량 변경 | `k8s/base/pvc/` 수정 |
| 리소스 제한 변경 | CPU/메모리 limit 조정 | `k8s/overlays/*/patches/resources.yaml` |
| 이미지 버전 변경 | 새 버전 배포 | `kustomize edit set image` 또는 Helm values |
| Ingress 설정 | 도메인 연결, TLS | `k8s/base/ingress/` 수정 |
| 모니터링 설정 | ServiceMonitor, 알림 규칙 | `_shared/monitoring/` 수정 |

### 8.3 판단 기준

변경이 필요할 때 다음 질문으로 책임을 판단한다:

```
Q1: 이 변경이 "무엇을 실행할 것인가"를 바꾸는가?
    → Yes: App 레포 수정

Q2: 이 변경이 "어디서, 어떻게 실행할 것인가"를 바꾸는가?
    → Yes: Deploy 레포 수정

Q3: 이 변경이 이미지 내용을 바꾸는가?
    → Yes: App 레포 수정, 새 이미지 빌드

Q4: 이 변경이 환경/서버별로 다른가?
    → Yes: Deploy 레포 수정
```

---

## 9. 금지 사항

### 9.1 App 레포에 포함되면 안 되는 항목

| 금지 항목 | 이유 |
|----------|------|
| Kubernetes manifests | Deployment, Service, ConfigMap 등은 Deploy 책임이다 |
| Helm charts | 패키징/배포 정의는 Deploy 책임이다 |
| kustomization.yaml | kustomize 설정은 Deploy 책임이다 |
| docker-compose.yml | 컨테이너 오케스트레이션은 Deploy 책임이다 |
| 실제 환경변수 값 | ConfigMap/Secret으로 배포 시 주입한다 |
| 서버 IP/도메인 하드코딩 | 환경 종속성이 생긴다 |
| PVC 정의 | 스토리지 설정은 Deploy 책임이다 |
| kubectl/helm 배포 스크립트 | 배포 자동화는 Deploy 책임이다 |
| 프로덕션 시크릿 | 보안 위험이 있다 |
| 환경별 분기 설정 파일 | config/production.yaml 같은 파일 금지 |
| Deploy 레포 참조 | 두 레포 간 직접 의존성 금지 |

### 9.2 구조 일관성을 해치는 패턴

| 금지 패턴 | 올바른 패턴 |
|----------|-----------|
| 앱별로 다른 디렉터리 구조 | 표준 템플릿 구조 사용 |
| 환경별 Dockerfile | 단일 Dockerfile + 빌드 인자 |
| 환경별 소스 코드 분기 | 환경변수로 동작 제어 |
| 루트에 산재한 설정 파일 | config/ 디렉터리에 집중 |
| 테스트 코드와 프로덕션 코드 혼재 | src/와 tests/ 분리 |
| CI 워크플로우에 배포 로직 포함 | 빌드/푸시만 포함 |

### 9.3 의존성 관련 금지 사항

| 금지 사항 | 이유 |
|----------|------|
| Deploy 레포 코드 import | 두 레포는 독립적이어야 한다 |
| 런타임에 Deploy 레포 파일 참조 | 이미지는 자체 완결적이어야 한다 |
| 빌드 시 외부 레포 체크아웃 | 빌드 재현성이 깨진다 |
| 서버 파일시스템 직접 참조 | 볼륨 마운트로만 외부 접근한다 |

---

## 부록 A: 문서 간 교차 참조 매핑

### A.1 메인 아키텍처와의 연결

| 메인 아키텍처 섹션 | 본 문서 섹션 | 설명 |
|------------------|------------|------|
| [[k8s_architecture.md]] 1.1절 | 본 문서 2절 | 책임 분리 원칙 → App 레포 책임 구체화 |
| [[k8s_architecture.md]] 1.2절 | 본 문서 4절 | GHCR CI/CD 흐름 → 빌드/태깅 전략 상세 |
| [[k8s_architecture.md]] 2절 | 본 문서 3절 | App Template → 디렉터리 구조 표준 |

### A.2 Deploy Sub Architecture와의 인터페이스

| App의 책임 (본 문서) | Deploy의 책임 | 연결 포인트 |
|-------------------|-------------|-----------|
| 환경변수 스키마 정의 (5.2절) | ConfigMap/Secret 값 제공 | [[k8s_sub_architecture.md]] 2.2절 `configmaps/`, `secrets/` |
| GHCR 이미지 태깅 (4.2절) | kustomize로 이미지 태그 선택 | [[k8s_sub_architecture.md]] 3.2절 |
| 내부 포트 정의 (5.4절) | Service/Ingress 정의 | [[k8s_sub_architecture.md]] 2.2절 `services/`, `ingress/` |
| 로그 stdout 출력 (5.3절) | 로그 수집 (Loki/Promtail) | [[k8s_sub_architecture.md]] 7절 모니터링 |
| Probe 엔드포인트 (6.1절) | Deployment Probe 설정 | [[k8s_sub_architecture.md]] 2.2절 `deployments/` |
| /metrics 엔드포인트 (6.5절) | ServiceMonitor 설정 | [[k8s_sub_architecture.md]] 7.3절 |

### A.3 템플릿 디렉터리 매핑

| 본 문서 참조 | 템플릿 내 위치 | Deploy 레포 대응 |
|-----------|-------------|----------------|
| 3.1절 디렉터리 구조 | `app/prj_*/` | 독립 Git 레포 |
| 3.4절 `.github/workflows/` | (참조용) | App 레포의 CI/CD |
| 5.2절 환경변수 스키마 | `app/prj_*/.env.example` | `infra/k8s/base/configmaps/`, `infra/_shared/secrets/sealed/` |
| 4절 GHCR 이미지 | (빌드 결과) | `infra/k8s/overlays/*/kustomization.yaml` (images 섹션) |
| 6.1절 Probe 엔드포인트 | `src/app/health.py` | `infra/k8s/base/deployments/` (Probe 설정) |
| 6.5절 메트릭 엔드포인트 | `src/app/metrics.py` | `infra/_shared/monitoring/` (ServiceMonitor) |

---

## 부록 B: 디렉터리별 .gitignore 규칙

```gitignore
# 환경변수 실제 값 (스키마만 추적)
.env
.env.local
.env.production
.env.staging

# config/.env.example은 추적함 (스키마)
!config/.env.example

# 빌드 산출물
dist/
build/
*.egg-info/
__pycache__/

# 테스트 커버리지
.coverage
htmlcov/
.pytest_cache/

# IDE
.idea/
.vscode/
*.swp

# 로컬 개발
.tmp/
tmp/
*.log
```

---
