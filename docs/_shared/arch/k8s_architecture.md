<!-- Document Metadata -->
- Document Name: 서버/배포 아키텍처 설계 문서
- File Name: k8s_architecture.md
- Document ID: ARCH-DEPLOY-001
- Status: Active
- Version: 2.0.0
- Created Date: 2026-02-02 14:55
- Last Updated: 2026-02-02
- Author: {{USER}}
- Reviewer: {{REVIEWER}}
- Parent Document: (없음)
- Child Documents: [[k8s_app_architecture.md]] (ARCH-APP-SUB-001), [[k8s_sub_architecture.md]] (ARCH-DEPLOY-SUB-001)
- Related Reference: [[k8s_app_architecture.md]], [[k8s_sub_architecture.md]]
- Change Summary:
  - App / Deploy 책임 분리 원칙 명문화
  - GHCR 기반 이미지 불변 태그 정책 명시
  - 서버 데이터 루트(/data) 및 볼륨 규칙 고정
  - QTS 확장 및 분리 기준 아키텍처 반영
  - v1.1.0: 템플릿 프로젝트 특성 반영, 실제 디렉터리 구조와 일치하도록 업데이트
  - **v2.0.0: k3s(경량 Kubernetes) 기반 아키텍처로 전환**
    - Docker Compose → Kubernetes manifests/Helm charts 전환
    - kustomize 기반 환경별 오버레이 구조 도입
    - k3s 선택 이유 및 Kubernetes 핵심 개념 매핑 추가
    - GitOps 배포 전략 (ArgoCD/Flux) 선택적 도입
    - PersistentVolumeClaim 기반 데이터 관리
<!-- End Metadata -->

---

# 서버/배포 아키텍처 설계 문서

---

## 템플릿 프로젝트 안내

이 저장소는 **템플릿 및 참조 아키텍처용**이며, 실제 프로덕션 애플리케이션은 **별도 저장소**에서 운영하는 것을 전제로 합니다. 본 레포를 **프로덕션 모노레포로 직접 운영할 목적이 아님**을 명시합니다.

본 문서가 설명하는 아키텍처 원칙은 **App 레포와 Deploy 레포를 분리**하는 구조를 기반으로 합니다.

**현재 Kubernetes_k8s 템플릿의 특성:**
- 학습 및 참조 목적으로 App과 Deploy 영역을 **하나의 레포에 통합**
- `app/` 디렉터리: App 레포 구조 참조용 (실제로는 별도 레포로 분리)
- `infra/` 디렉터리: Deploy 레포 구조 (실제 프로젝트에서 사용)
- `docs/` 디렉터리: 아키텍처 원칙 및 가이드

**실제 프로젝트 적용 시:**
1. `app/prj_*` 구조를 참조하여 독립적인 App 레포 생성
2. `infra/` 구조를 기반으로 Deploy 레포 구성
3. 본 문서의 책임 분리 원칙 준수

**템플릿 구조:**
```
Kubernetes_k8s/
├── app/                    # App 레포 참조 구조 (분리 예정)
│   ├── prj_01/             # 프로젝트 1 예시
│   ├── prj_02/             # 프로젝트 2 예시
│   └── prj_03/             # 프로젝트 3 예시
├── infra/                  # Deploy 레포 구조 (실제 사용)
│   ├── k8s/                # [k3s] Kubernetes manifests
│   │   ├── base/           # kustomize base (공통 리소스)
│   │   └── overlays/       # 환경별 오버레이 (production, staging)
│   ├── helm/               # [k3s 선택적] Helm charts
│   ├── argocd/             # [k3s 선택적] GitOps Application 정의
│   ├── _shared/            # 공통 인프라 리소스
│   │   ├── monitoring/     # kube-prometheus-stack 설정
│   │   ├── migrations/     # DB 마이그레이션
│   │   ├── secrets/        # SealedSecrets/SOPS
│   │   └── scripts/        # 배포, 마이그레이션, k3s 관리 스크립트
│   └── README.md
├── docs/                   # 아키텍처 문서
│   └── arch/
│       ├── k8s_architecture.md       # 본 문서
│       ├── k8s_app_architecture.md
│       └── k8s_sub_architecture.md
├── tests/                  # 테스트 구조 참조
│   └── k8s/                # Kubernetes manifest 테스트
└── README.md
```

---

## 문서 계층 구조

```
[메인 아키텍처] k8s_architecture.md (본 문서, ARCH-DEPLOY-001)
    │
    ├── 1절: 메인 아키텍처 (통합 관점)
    │   ├── 1.1: 책임 분리 원칙 ─────────────┐
    │   ├── 1.2: GHCR 기반 CI/CD 흐름        │
    │   └── 1.3: 서버 기준 철학              │
    │                                        │
    ├── 2절: App Template 서브 아키텍처     │
    │   └── k8s_app_architecture.md 요약 ◀───┼── [상세 문서]
    │                                        │   ARCH-APP-SUB-001
    ├── 3절: Deploy Template 서브 아키텍처  │   ├── App 레포 책임
    │   └── k8s_sub_architecture.md 요약 ◀┼── ├── 디렉터리 구조
    │                                        │   ├── GHCR 이미지 빌드
    ├── 4절: 프로젝트 확장성 검토           │   └── 인터페이스 규칙
    │   └── 다양한 프로젝트 유형 지원       │
    │                                        └── [상세 문서]
    └── 5절: 아키텍처 의사결정 요약             ARCH-DEPLOY-SUB-001
                                                ├── Deploy 레포 구조
                                                ├── 이미지 핸들링
                                                ├── CI/CD 배치
                                                └── 확장성 고려
```

**문서 읽기 순서:**
1. **먼저**: 본 문서 (k8s_architecture.md) - 전체 아키텍처 원칙 이해
2. **App 관점**: k8s_app_architecture.md - App 레포 구조 및 책임 상세
3. **Deploy 관점**: k8s_sub_architecture.md - Deploy 레포 구조 및 운영 상세

**템플릿 적용 순서:**
1. 본 문서로 아키텍처 원칙 학습
2. `app/prj_*/` 구조 참조하여 App 레포 생성
3. `infra/` 구조 기반으로 Deploy 레포 구성

---

## 목차
1. [메인 아키텍처 (통합 관점)](#1-메인-아키텍처-통합-관점)
2. [App Template 서브 아키텍처](#2-app-template-서브-아키텍처)
3. [Deploy Template 서브 아키텍처](#3-deploy-template-서브-아키텍처)
4. [프로젝트 확장성 검토](#4-프로젝트-확장성-검토)
5. [아키텍처 의사결정 요약](#5-아키텍처-의사결정-요약)
6. [k3s 아키텍처 선택 이유](#6-k3s-아키텍처-선택-이유)
7. [Kubernetes 핵심 개념 매핑](#7-kubernetes-핵심-개념-매핑)

---

## 1. 메인 아키텍처 (통합 관점)

> **템플릿 프로젝트 참고**: 본 문서는 App 레포와 Deploy 레포를 분리하는 아키텍처 원칙을 설명합니다. 현재 Kubernetes_k8s 템플릿은 학습 및 참조 목적으로 두 영역을 통합한 구조를 가지고 있으며, 실제 프로젝트에서는 아래 원칙에 따라 분리해야 합니다.
>
> **k3s 기반 아키텍처**: 본 아키텍처에서 채택한 기준 Kubernetes 배포판은 k3s이다. 본 문서는 k3s(경량 Kubernetes)를 기반으로 컨테이너 오케스트레이션을 설명하며, k3s는 Kubernetes의 모든 핵심 기능을 제공하면서도 단일 바이너리로 설치되어 리소스 효율성이 높다.

### 1.1 책임 분리 원칙

**개념적 경계:** App은 **코드, 스키마, 빌드 산출물, 내부 로직**을 담당하고, Deploy는 **런타임 실행, 환경 연동(wiring), 인프라 정의**를 담당한다. 상세 책임은 각 서브 아키텍처 문서에서 다루며, 아래는 그 요약이다.

#### App 레포의 책임 범위

App 레포는 **"무엇을 실행할 것인가"**에 대한 답을 가진다.

| 책임 영역 | 설명 | 템플릿 내 위치 |
|----------|------|---------------|
| 애플리케이션 소스 코드 | 비즈니스 로직, 서비스 코드 전체 | `app/prj_*/` (실제로는 별도 레포) |
| 빌드 정의 | Dockerfile, 빌드 스크립트, 의존성 목록 | `app/prj_*/dockerfile` (예시) |
| 이미지 생성 | CI를 통한 컨테이너 이미지 빌드 및 GHCR 푸시 | `.github/workflows/` (참조용) |
| 애플리케이션 설정 스키마 | 환경변수 목록, 설정 파일 형식 정의 (값이 아닌 형식) | `app/prj_*/.env.example` |
| DB 스키마 마이그레이션 | 마이그레이션 정의 및 실행 책임 | 템플릿에서는 `infra/_shared/migrations/` (예외) |
| 테스트 | 단위 테스트, 통합 테스트, 빌드 검증 | `tests/` (템플릿 참조용) |

#### Deploy 레포의 책임 범위

Deploy 레포는 **"어디서, 어떻게 실행할 것인가"**에 대한 답을 가진다.

| 책임 영역 | 설명 | 템플릿 내 위치 |
|----------|------|---------------|
| 서버/환경별 설정값 | 실제 환경변수 값, 시크릿, 도메인 | `infra/_shared/secrets/`, `infra/k8s/overlays/` |
| 컨테이너 오케스트레이션 | Kubernetes manifests/Helm charts, 서비스 간 의존성 정의 | `infra/k8s/base/`, `infra/helm/` |
| 볼륨 마운트 정의 | PersistentVolumeClaim으로 스토리지 연결 | `infra/k8s/base/pvc/` |
| 네트워크 구성 | Service, Ingress, NetworkPolicy | `infra/k8s/base/services/`, `infra/k8s/base/ingress/` |
| 배포 스크립트 | kubectl apply, helm upgrade, health check, rollback | `infra/_shared/scripts/deploy/` |

**템플릿의 특수 사항**: 본 템플릿에서 DB 마이그레이션 스크립트는 `infra/_shared/migrations/`에 위치합니다. 이는 초기 단계 또는 단일 서버 환경에서의 실용성을 위한 예외적 구조이며, 마이그레이션 코드의 논리적 소유권은 애플리케이션 도메인에 있다. 성숙한 환경 또는 App/Deploy 저장소 분리 구성에서는 마이그레이션을 App 레포로 이관하는 것을 전제로 한다.

#### 절대 섞이면 안 되는 요소

```
❌ App 레포에 있으면 안 되는 것:
- 실제 환경변수 값 (API 키, DB 비밀번호)
- 서버별 docker-compose.yml 등 비-Kubernetes 오케스트레이션 (초기 로컬 개발용 제외)
- 볼륨 경로 하드코딩
- 특정 서버 IP/도메인

❌ Deploy 레포에 있으면 안 되는 것:
- 애플리케이션 소스 코드
- Dockerfile
- 빌드 로직
- 패키지 의존성 정의
- DB 마이그레이션 로직
```

**위반 시 발생하는 문제:**
- App 레포에 환경값이 있으면 → 서버마다 브랜치 분기 필요 → 관리 불가
- Deploy 레포에 Dockerfile이 있으면 → 이미지 버전과 배포 버전이 꼬임 → 롤백 불가

---

### 1.2 GHCR 기반 CI/CD 흐름

#### 전체 흐름 (텍스트 다이어그램)

```
[개발자]
    │
    ▼ push
[App Repo: your-app-repo]          # 실제로는 별도 레포
    │                                # 템플릿: app/prj_*/ 참조
    ▼ GitHub Actions trigger
[CI: Build & Test]
    │
    ▼ docker build & push
[GHCR: ghcr.io/org/your-app:v1.2.3]
    │
    │ ════════════════════════════════════════
    │         (이미지 레지스트리가 경계선)
    │ ════════════════════════════════════════
    │
    ▼ 이미지 태그 참조
[Deploy Repo: deploy-repo]          # 실제로는 별도 레포
    │                                # 템플릿: infra/k8s/, infra/helm/ 참조
    ▼ kubectl apply / helm upgrade / ArgoCD sync
[k3s Cluster]
    │
    ├── Deployment (Pod 관리)
    ├── Service (네트워크 노출)
    ├── ConfigMap/Secret (설정 주입)
    └── PVC (영속 스토리지)
```

#### App 레포 → GHCR 단계

1. **트리거**: main 브랜치 push 또는 tag 생성
2. **빌드**: Dockerfile 기반으로 이미지 생성
3. **태깅 전략**:
   - `latest` - 최신 main 브랜치
   - `v1.2.3` - 릴리스 태그
   - `sha-abc1234` - 커밋 해시 (디버깅용)
   production 및 staging 환경에서는 semantic version 또는 커밋 해시 태그만 참조해야 하며, latest 태그는 배포 참조에 사용하지 않는다. staging 및 production용 배포 매니페스트에서는 latest 태그 사용을 금지·거부한다. 재현성과 롤백을 위해 불변 태그만 사용한다.
4. **푸시**: GHCR에 이미지 업로드
5. **결과물**: 불변(immutable) 이미지 아티팩트

#### Deploy 레포 → k3s 클러스터 실행 단계

1. **이미지 참조**: Deployment manifest 또는 Helm values에서 GHCR 이미지 태그 지정
2. **설정 적용**: ConfigMap/Secret으로 환경변수 및 시크릿 정의
3. **배포 실행**:
   - `kubectl apply -k infra/k8s/overlays/production/` (kustomize)
   - `helm upgrade --install app infra/helm/app -f values-prod.yaml` (Helm)
   - ArgoCD Application sync (GitOps)
4. **롤아웃 확인**: `kubectl rollout status deployment/app-name`
5. **검증**: readinessProbe/livenessProbe 기반 health check 자동 확인

#### 느슨한 결합의 핵심

두 레포는 **"이미지 태그"**라는 단일 인터페이스로만 연결된다.

```
연결 지점: ghcr.io/org/observer:v1.2.3
          └─────────────────────────┘
                    │
    App 레포가 생성    │    Deploy 레포가 소비
```

**이 구조의 이점:**
- App 레포 변경 → Deploy 레포 수정 불필요 (태그만 업데이트)
- Deploy 레포 변경 → App 레포 영향 없음
- 롤백 시 → 이전 태그로 교체만 하면 됨
- 여러 서버에서 동일 이미지 사용 가능

---

### 1.3 서버 기준 철학

#### 컨테이너 생명주기

```
원칙: 컨테이너는 언제든 죽을 수 있고, 언제든 다시 생성될 수 있다.
```

| 상태 | 허용 여부 | 설명 |
|------|----------|------|
| 컨테이너 삭제 후 재생성 | ✅ 허용 | 서비스 중단 없이 가능해야 함 |
| 컨테이너 내부 상태 의존 | ❌ 금지 | 모든 상태는 외부 저장소에 |
| 컨테이너 내부 파일 직접 수정 | ❌ 금지 | 이미지 재빌드 또는 볼륨으로 |

**실제 운영 시나리오:**
- 메모리 누수 발생 → 컨테이너 재시작 → 서비스 정상
- 이미지 업데이트 → 기존 컨테이너 삭제 → 새 컨테이너 생성
- 디버깅 → 컨테이너 들어가서 확인 → 수정은 코드에서

#### 데이터 생명주기

```
원칙: 데이터는 컨테이너보다 오래 산다.
```

| 데이터 유형 | 저장 위치 | 백업 정책 |
|------------|----------|----------|
| 애플리케이션 DB | 볼륨 마운트된 PostgreSQL/MySQL 데이터 | 정기 백업 필수 |
| 수집된 시계열 데이터 | 볼륨 마운트된 TimescaleDB/InfluxDB | 보존 기간 정책 |
| 로그 | 볼륨 마운트 또는 외부 로그 시스템 | 로테이션 정책 |
| 설정 파일 | Deploy 레포 (Git 추적) | Git 자체가 백업 |
| 시크릿 | 환경변수 또는 시크릿 매니저 | 별도 백업 |

**스토리지 관리 원칙 (k3s/Kubernetes):**

k3s 환경에서 데이터 영속성은 **PersistentVolumeClaim (PVC)**을 통해 관리한다. 로컬 스토리지를 사용하는 경우 서버 기준 데이터 루트는 `/data`로 고정하며, StorageClass를 통해 동적 프로비저닝을 설정한다.

```
# k3s 스토리지 구조 예시:

Namespace: prj-01
├── PVC: prj-01-db-pvc          # PostgreSQL 데이터
│   └── PV: /data/prj-01/db
├── PVC: prj-01-logs-pvc        # 애플리케이션 로그
│   └── PV: /data/prj-01/logs
└── PVC: prj-01-timeseries-pvc  # 시계열 데이터 (필요시)
    └── PV: /data/prj-01/timeseries

Namespace: monitoring
├── PVC: prometheus-pvc
│   └── PV: /data/monitoring/prometheus
├── PVC: grafana-pvc
│   └── PV: /data/monitoring/grafana
└── PVC: alertmanager-pvc
    └── PV: /data/monitoring/alertmanager
```

**PVC 정의 원칙:**
- 앱 단위로 Namespace를 분리하여 리소스 격리
- PVC 이름은 `{앱이름}-{용도}-pvc` 형식
- StorageClass: `local-path` (k3s 기본) 또는 클라우드 스토리지

#### 클러스터 재구축 가능성

```
원칙: 클러스터는 언제든 재구축될 수 있다. 재구축에 4시간 이상 걸리면 실패다.
```

**재구축 시 필요한 것들:**
1. k3s 설치: `curl -sfL https://get.k3s.io | sh -`
2. Deploy 레포 clone
3. 시크릿 복원: `kubectl apply -f sealed-secrets/` 또는 SOPS 복호화
4. 워크로드 배포: `kubectl apply -k infra/k8s/overlays/production/`
5. 데이터 볼륨 복원 (백업에서 PVC로)

**재구축에 필요하면 안 되는 것들:**
- "예전에 클러스터에서 직접 수정한 설정" (모든 설정은 Git에)
- "문서화되지 않은 수동 kubectl 명령어"
- "특정 담당자만 아는 설정값"

**GitOps 도입 시 재구축:**
- ArgoCD Application 정의만 복원하면 전체 워크로드 자동 동기화

#### 멀티 노드/클러스터 확장 가능성

```
원칙: 단일 노드 구조가 멀티 노드/멀티 클러스터로 자연스럽게 확장되어야 한다.
```

**확장 시나리오:**

| 시나리오 | k3s 변경 범위 | 템플릿 참조 |
|---------|-------------|------------|
| 워커 노드 추가 | `k3s agent` 설치로 노드 조인 | `infra/_shared/scripts/k3s/join-agent.sh` |
| 동일 앱 Replica 확장 | Deployment의 `replicas` 값 변경 | `infra/k8s/overlays/` 패치 |
| 여러 프로젝트를 Namespace로 분리 | 각 프로젝트별 Namespace 생성 | `infra/k8s/base/namespaces/` |
| DB를 별도 서비스로 분리 | ExternalName Service 또는 외부 DB 연결 | ConfigMap/Secret 수정 |
| Ingress로 트래픽 분산 | Ingress Controller (Traefik 기본 포함) 설정 | `infra/k8s/base/ingress/` |
| HA 클러스터 구성 | 임베디드 etcd 또는 외부 DB로 k3s server HA | `infra/_shared/scripts/k3s/` |

**핵심:** App 레포는 전혀 수정하지 않고 Deploy 레포(k8s manifests)만으로 확장

**k3s 노드 확장 예시:**
```bash
# 워커 노드 추가 (서버에서 토큰 가져온 후)
curl -sfL https://get.k3s.io | K3S_URL=https://server:6443 K3S_TOKEN=xxx sh -
```

---

## 2. App Template 서브 아키텍처

### 2.1 app-template-repo의 목적

App Template은 **신규 앱 생성 시 복사해서 시작하는 표준 골격**이다.

**목적:**
1. 신규 앱 생성 시간 단축 (0에서 시작하지 않음)
2. 팀 내 일관된 프로젝트 구조 유지
3. CI/CD, 빌드, 테스트 파이프라인 표준화
4. 베스트 프랙티스 강제 적용

app-template 및 deploy-template에는 템플릿 버전 개념이 존재해야 하며, 어떤 템플릿에서 파생되었는지 추적 가능해야 한다. 구체적 구현 방식은 본 문서에서 정의하지 않는다.

**템플릿 내 참조 구조:**
```
현재 Kubernetes_k8s 템플릿:
app/
├── prj_01/          # App 템플릿 참조 예시 1
│   └── dockerfile
├── prj_02/          # App 템플릿 참조 예시 2
│   └── dockerfile
└── prj_03/          # App 템플릿 참조 예시 3
    └── dockerfile

실제 사용 시:
각 prj_*는 독립적인 Git 레포지토리로 분리
```

**사용 흐름:**
```
1. 현재 템플릿의 app/prj_* 구조 참조
2. 독립적인 app-repo 생성 (새 Git 레포)
3. 앱 이름, 설정, Dockerfile 구체화
4. 비즈니스 로직 구현
5. CI 설정 (.github/workflows/ 참조)
6. CI 자동으로 동작하여 GHCR에 이미지 푸시
```

### 2.2 필수 디렉터리 카테고리와 그 이유

#### 카테고리 1: 소스 코드 영역

**목적:** 실제 비즈니스 로직이 위치하는 곳

**포함 내용:**
- 메인 애플리케이션 코드
- 내부 라이브러리/모듈
- 진입점 (entrypoint)

**이 카테고리가 필요한 이유:**
- 코드와 설정의 명확한 분리
- IDE 지원, 린팅, 테스트 범위 설정 용이
- 빌드 시 COPY 범위 명확화

#### 카테고리 2: 빌드/패키징 영역

**목적:** 소스 코드를 실행 가능한 이미지로 변환하는 방법 정의

**포함 내용:**
- Dockerfile
- 의존성 정의 파일 (requirements.txt, package.json 등)
- 빌드 스크립트 (필요시)

**이 카테고리가 필요한 이유:**
- "이 앱을 어떻게 빌드하는가"에 대한 단일 진실 공급원
- CI에서 참조하는 빌드 정의
- 로컬 개발 환경과 프로덕션 환경의 일관성

#### 카테고리 3: CI/CD 파이프라인 영역

**목적:** 자동화된 빌드, 테스트, 배포 파이프라인 정의

**포함 내용:**
- GitHub Actions 워크플로우
- 테스트 실행 설정
- GHCR 푸시 설정

**이 카테고리가 필요한 이유:**
- 코드 푸시 → 이미지 생성의 자동화
- 테스트 강제 실행
- 이미지 태깅 전략 일관성

#### 카테고리 4: 설정 스키마 영역

**목적:** 애플리케이션이 필요로 하는 설정의 "형식"을 정의

**포함 내용:**
- 환경변수 목록 및 설명 (예: .env.example)
- 설정 파일 스키마
- 기본값 정의

**이 카테고리가 필요한 이유:**
- Deploy 레포에서 어떤 값을 제공해야 하는지 명세
- 누락된 설정 조기 발견
- 개발자 온보딩 시 참고 문서

#### 카테고리 5: 테스트 영역

**목적:** 코드 품질 보장

**포함 내용:**
- 단위 테스트
- 통합 테스트
- 테스트 픽스처/목 데이터

**이 카테고리가 필요한 이유:**
- CI에서 테스트 통과 여부 확인
- 리팩토링 안전성 확보
- 신규 기능의 회귀 방지

#### 카테고리 6: 문서 영역

**목적:** 앱의 사용법, 아키텍처, 개발 가이드 제공

**포함 내용:**
- README (프로젝트 개요)
- 아키텍처 설명
- 개발 환경 설정 가이드

**이 카테고리가 필요한 이유:**
- 신규 팀원 온보딩
- 의사결정 기록
- 외부 협업 시 참고

### 2.3 Dockerfile이 App 레포에 있어야 하는 이유

**핵심 논거:**

1. **소스 코드와 빌드 방법은 1:1 관계**
   - 코드가 변경되면 빌드 방법도 변경될 수 있음
   - 같은 커밋에서 코드와 Dockerfile이 함께 버전 관리됨

2. **CI 파이프라인의 단순화**
   - App 레포 하나만 체크아웃하면 빌드 가능
   - 외부 의존성 없이 자체 완결적

3. **롤백의 정확성**
   - v1.2.3 태그 체크아웃 → 그 시점의 정확한 Dockerfile 사용
   - 빌드 재현성 보장

4. **멀티 앱 환경에서의 독립성**
   - observer와 qts의 Dockerfile이 다를 수 있음
   - 각 앱이 자신의 빌드 방법을 소유

**만약 Deploy 레포에 있다면 발생하는 문제:**
```
시나리오: observer 앱 v1.3.0 배포
문제: Deploy 레포의 Dockerfile은 v1.2.0 기준으로 작성됨
결과: 빌드 실패 또는 런타임 오류
해결 불가: 어떤 Dockerfile이 어떤 앱 버전과 호환되는지 추적 불가
```

### 2.4 서로 다른 성격의 앱 수용 가능성

**질문: 다양한 유형의 프로젝트를 같은 템플릿으로?**

**답변: 가능하다. 템플릿은 "구조"를 정의하지 "내용"을 정의하지 않는다.**

| 요소 | 데이터 수집 앱 | 거래 실행 앱 | 웹 API 서버 | 템플릿이 정의하는 것 |
|------|------------|-----------|-----------|-------------------|
| 언어/런타임 | Python | Python | Node.js/Go | 언어별 빌드 패턴 |
| 실행 방식 | 상시 실행 데몬 | 스케줄/이벤트 기반 | HTTP 서버 | 진입점 구조 |
| 외부 연동 | API (읽기) | API (읽기/쓰기) | REST/GraphQL | API 클라이언트 위치 |
| DB 사용 | TimescaleDB | PostgreSQL | MySQL/MongoDB | DB 연결 패턴 |

**템플릿 예시:**
```
app/prj_01/  → 데이터 수집 앱 (Python, 상시 실행)
app/prj_02/  → 웹 API 서버 (Node.js, HTTP)
app/prj_03/  → 배치 작업 (Python, 스케줄 실행)
```

**템플릿이 강제하는 것:**
- 디렉터리 구조
- CI/CD 파이프라인 형식
- 환경변수 정의 방식
- 테스트 구조
- Dockerfile 위치

**템플릿이 강제하지 않는 것:**
- 비즈니스 로직
- 사용하는 라이브러리
- 실행 주기 (데몬 vs 배치)
- 외부 서비스 연동 방식
- 프로그래밍 언어 선택

---

## 3. Deploy Template 서브 아키텍처

### 3.1 deploy-template-repo의 역할 한정

Deploy Template은 **"k3s 클러스터에서 컨테이너를 어떻게 실행할 것인가"만 정의**한다.

**템플릿 내 구조:**
```
infra/
├── k8s/                        # [k3s] Kubernetes manifests
│   ├── base/                   # kustomize base (공통 리소스)
│   │   ├── namespaces/         # Namespace 정의
│   │   ├── deployments/        # Deployment 정의
│   │   ├── services/           # Service 정의
│   │   ├── configmaps/         # ConfigMap 정의
│   │   ├── secrets/            # Secret 참조 (실제 값은 SealedSecrets)
│   │   ├── pvc/                # PersistentVolumeClaim 정의
│   │   └── kustomization.yaml
│   └── overlays/               # 환경별 오버레이
│       ├── production/
│       │   ├── kustomization.yaml
│       │   └── patches/
│       └── staging/
├── helm/                       # [선택적] Helm charts
│   └── apps/
│       └── app-name/
│           ├── Chart.yaml
│           ├── values.yaml
│           └── templates/
├── argocd/                     # [선택적] GitOps Application 정의
│   └── applications/
├── _shared/                    # 공통 인프라 리소스
│   ├── monitoring/             # kube-prometheus-stack 설정
│   │   ├── values.yaml         # Helm values
│   │   └── dashboards/         # Grafana 대시보드 ConfigMap
│   ├── migrations/             # DB 마이그레이션 (Job으로 실행)
│   ├── secrets/                # SealedSecrets / SOPS 암호화
│   └── scripts/                # 배포, k3s 관리 스크립트
│       ├── deploy/             # kubectl/helm 배포 스크립트
│       ├── k3s/                # k3s 클러스터 관리
│       ├── migrate/            # 마이그레이션 Job 실행
│       ├── env/
│       ├── build/
│       └── oci/
└── README.md
```

**수행해야 하는 역할:**

| 역할 | 설명 | 템플릿 내 위치 |
|------|------|---------------|
| 컨테이너 오케스트레이션 | Deployment, ReplicaSet, Pod 관리 | `infra/k8s/base/deployments/` |
| 환경별 설정값 관리 | ConfigMap/Secret, kustomize overlay | `infra/k8s/overlays/`, `infra/_shared/secrets/` |
| 스토리지 정의 | PersistentVolumeClaim 정의 | `infra/k8s/base/pvc/` |
| 네트워크 구성 | Service, Ingress, NetworkPolicy | `infra/k8s/base/services/` |
| 배포 자동화 | kubectl apply, helm upgrade, ArgoCD | `infra/_shared/scripts/deploy/` |
| 모니터링 연동 | ServiceMonitor, kube-prometheus-stack | `infra/_shared/monitoring/` |

**수행하면 안 되는 역할:**

| 금지 역할 | 이유 | 템플릿 참고 |
|----------|------|------------|
| 애플리케이션 빌드 | App 레포의 책임 | `app/` 영역과 분리 |
| 비즈니스 로직 포함 | App 레포의 책임 | `app/` 영역과 분리 |
| 이미지 생성 | App 레포 CI의 책임 | `.github/workflows/`는 참조용 |
| 코드 테스트 | App 레포의 책임 | `tests/k8s/`는 manifest 테스트만 |

### 3.2 Kubernetes Manifest의 책임 범위

#### 포함해야 하는 것

```yaml
# 개념적 예시 - Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: observer
  namespace: prj-01
spec:
  replicas: 2
  selector:
    matchLabels:
      app: observer
  template:
    spec:
      containers:
      - name: observer
        image: ghcr.io/org/observer:v1.2.3  # 이미지 참조
        envFrom:
        - configMapRef:
            name: observer-config           # ConfigMap에서 환경변수
        - secretRef:
            name: observer-secrets          # Secret에서 민감 정보
        volumeMounts:
        - name: logs
          mountPath: /app/logs              # 볼륨 마운트
        readinessProbe:                     # 헬스체크
          httpGet:
            path: /health
            port: 8080
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
      volumes:
      - name: logs
        persistentVolumeClaim:
          claimName: observer-logs-pvc
---
# Service
apiVersion: v1
kind: Service
metadata:
  name: observer
spec:
  selector:
    app: observer
  ports:
  - port: 80
    targetPort: 8080
```

#### 포함하면 안 되는 것

```yaml
# ❌ 잘못된 예시
spec:
  containers:
  - name: app
    image: ghcr.io/org/app:latest    # ❌ latest 태그 (불변 태그 사용)
    command: ["python", "main.py"]   # ❌ 앱 실행 방식 (이미지에서 정의)
```

**k3s/Kubernetes에서도 빌드는 분리:**
- 클러스터에서 빌드하지 않음 (kaniko 등 예외적 경우 제외)
- CI에서 빌드된 이미지를 GHCR에서 pull
- 불변 이미지 태그로 롤백 용이

### 3.3 환경 변수, 스토리지, 네트워크 정의 수준

#### 환경 변수 (ConfigMap/Secret)

**계층 구조:**
```
Level 1: kustomize base의 기본 ConfigMap
    ↓
Level 2: kustomize overlay의 환경별 패치 (production/, staging/)
    ↓
Level 3: Helm values 오버라이드 (values-prod.yaml)
    ↓
Level 4: SealedSecrets / External Secrets (민감 정보)
```

**환경 변수 분류:**

| 분류 | 예시 | k8s 리소스 | 템플릿 위치 |
|------|------|-----------|------------|
| 공개 설정 | LOG_LEVEL, TIMEZONE | ConfigMap | `infra/k8s/base/configmaps/` |
| 환경별 설정 | DB_HOST, API_ENDPOINT | ConfigMap (overlay) | `infra/k8s/overlays/{env}/` |
| 민감 정보 | DB_PASSWORD, API_KEY | Secret (SealedSecrets) | `infra/_shared/secrets/sealed/` |

#### 스토리지 (PersistentVolumeClaim)

**정의 원칙:**
- PVC는 `infra/k8s/base/pvc/`에서 정의
- StorageClass로 스토리지 유형 추상화
- 환경별로 용량/StorageClass 오버라이드

```yaml
# infra/k8s/base/pvc/observer-db-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: observer-db-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path  # k3s 기본 StorageClass
  resources:
    requests:
      storage: 10Gi

# infra/k8s/overlays/production/patches/pvc-patch.yaml
- op: replace
  path: /spec/resources/requests/storage
  value: 100Gi
```

#### 네트워크 (Service/Ingress)

**정의 수준:**
- 내부 통신: Service (ClusterIP) - 클러스터 내부만
- 외부 노출: Service (LoadBalancer/NodePort) 또는 Ingress
- 서비스 간 통신: `{service-name}.{namespace}.svc.cluster.local`

```yaml
# 내부 통신 예시
apiVersion: v1
kind: Service
metadata:
  name: db
  namespace: prj-01
spec:
  type: ClusterIP
  selector:
    app: postgresql
  ports:
  - port: 5432
---
# 외부 노출 (Ingress)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: observer-ingress
spec:
  rules:
  - host: observer.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: observer
            port:
              number: 80
```

### 3.4 단일 노드 → 멀티 노드/클러스터 확장 시 구조 유지

#### 시나리오 1: Replica 수평 확장 (동일 클러스터)

```yaml
# infra/k8s/overlays/production/patches/replicas-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: observer
spec:
  replicas: 3  # 1 → 3으로 확장
```

**변경 범위:** kustomize patch 추가, App 레포 수정 없음

#### 시나리오 2: 프로젝트별 Namespace 분리

```
infra/k8s/
├── base/                   # 공통 리소스
│   ├── namespaces/
│   │   ├── prj-01.yaml     # Namespace: prj-01
│   │   ├── prj-02.yaml     # Namespace: prj-02
│   │   └── monitoring.yaml # Namespace: monitoring
│   ├── deployments/
│   └── services/
└── overlays/
    ├── production/
    │   ├── prj-01/         # 프로젝트 1 프로덕션 설정
    │   └── prj-02/         # 프로젝트 2 프로덕션 설정
    └── staging/
```

**변경 범위:** Namespace 정의 추가, 각 overlay에서 namespace 지정

#### 시나리오 3: 멀티 노드 클러스터 확장

```bash
# 워커 노드 추가 (k3s agent)
# 기존 manifests 변경 없이 스케줄링 자동 분산

# HA 구성 (k3s server 다중화)
# 첫 번째 서버 (임베디드 etcd)
curl -sfL https://get.k3s.io | sh -s - server --cluster-init

# 추가 서버
curl -sfL https://get.k3s.io | K3S_TOKEN=xxx sh -s - server --server https://server1:6443
```

**핵심 원칙:**
- 구조 변경은 Deploy 레포(`infra/k8s/`)에서만
- App 레포의 이미지는 동일하게 사용
- kustomize base 재사용, overlay로 환경별 설정
- Kubernetes 스케줄러가 자동으로 노드 분산

#### 시나리오 4: Ingress로 트래픽 라우팅

```yaml
# infra/k8s/base/ingress/main-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: main-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  tls:
  - hosts:
    - "*.example.com"
    secretName: wildcard-cert
  rules:
  - host: prj-01.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prj-01
            port:
              number: 80
  - host: prj-02.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prj-02
            port:
              number: 80
```

---

## 4. 프로젝트 확장성 검토

### 4.1 다양한 유형의 프로젝트 특성

| 특성 | 데이터 수집 앱 | 거래 실행 앱 | 웹 API 서버 | 배치 작업 |
|------|------------|-----------|-----------|----------|
| **핵심 기능** | 시장 데이터 수집, 저장, 분석 | 매매 전략 실행, 주문 관리 | REST/GraphQL API 제공 | 주기적 데이터 처리 |
| **실행 특성** | 상시 실행 (24/7) | 시장 시간 또는 전략 조건에 따라 | 상시 실행 (HTTP 서버) | 스케줄 기반 (cron) |
| **데이터 흐름** | 외부 → 내부 (수집) | 내부 → 외부 (주문) | 양방향 (요청/응답) | 내부 → 내부 (ETL) |
| **실패 영향** | 데이터 손실 (복구 가능) | 금전적 손실 (복구 불가) | 서비스 중단 | 작업 재실행 |
| **리소스 패턴** | 일정한 부하 | 변동적 (시장 변동성에 따라) | 트래픽에 따라 변동 | 실행 시 집중 |
| **업데이트 빈도** | 상대적으로 낮음 | 전략 변경 시 빈번 | 기능 추가 시 | 로직 변경 시 |

**템플릿 적용 예시:**
```
app/prj_01/  → 데이터 수집 앱 (24/7 데몬)
app/prj_02/  → 웹 API 서버 (HTTP 서버)
app/prj_03/  → 배치 작업 (cron 스케줄)
```

### 4.2 실행 패턴별 컨테이너 설계

#### 패턴 1: 상시 실행 서비스 (데이터 수집, API 서버)

```
실행 패턴:
├── 메인 워커 (상시)
│   └── WebSocket/HTTP 연결 유지, 데이터 처리
├── 집계/처리 워커 (주기적)
│   └── 주기적 데이터 집계 및 변환
└── 모니터링 워커 (상시 또는 주기적)
    └── 헬스체크, 메트릭 수집
```

**컨테이너 설계:**
- 단일 장기 실행 프로세스 또는 내부 스케줄러
- 재시작 정책: `unless-stopped` 또는 `always`
- 헬스체크: HTTP endpoint 또는 프로세스 상태 확인
- 리소스 제한: CPU/Memory limits 설정

#### 패턴 2: 이벤트 기반 실행 (거래, 알림)

```
실행 패턴:
├── 이벤트 리스너 (상시 대기)
│   └── 시그널/메시지 대기, 조건 충족 시 실행
├── 작업 처리자 (상시)
│   └── 작업 상태 추적, 결과 확인
├── 모니터링 (상시)
│   └── 시스템 상태 모니터링
└── 배치 작업 (필요시)
    └── 필요 시 실행, 완료 후 종료
```

**컨테이너 설계:**
- 핵심 서비스는 상시 실행
- 배치 작업은 별도 컨테이너 또는 Job
- 재시작 정책: `always` (중단 최소화)
- 헬스체크: 외부 연결 상태, 작업 시스템 상태
- 높은 가용성 요구 시 다중 인스턴스 고려

#### 패턴 3: 스케줄 기반 배치 (ETL, 보고서)

```
실행 패턴:
└── 배치 작업 (스케줄 실행)
    ├── 데이터 추출
    ├── 변환 처리
    └── 결과 저장/전송
```

**컨테이너 설계:**
- 스케줄 기반 배치 워크로드는 Kubernetes CronJob 리소스로 구현한다.
- Cron 또는 외부 스케줄러로 실행
- 재시작 정책: `no` (작업 완료 시 종료)
- 실패 시 재시도 로직 구현
- 로그 및 결과 저장 필수

### 4.3 DB 분리 필요성

**분리를 권장하는 이유:**

| 관점 | 분리 시 장점 |
|------|-------------|
| **성능** | observer의 대량 쓰기가 qts 읽기에 영향 안 줌 |
| **장애 격리** | DB 장애 시 영향 범위 제한 |
| **백업 정책** | 데이터 특성에 맞는 백업 주기 |
| **스키마 변경** | 독립적 마이그레이션 |

**공유해도 되는 조건:**

| 조건 | 설명 |
|------|------|
| 초기 단계 | 트래픽이 적고 복잡성을 줄이고 싶을 때 |
| 강한 데이터 의존성 | observer 데이터를 qts가 실시간 참조해야 할 때 |
| 리소스 제약 | 서버 비용 최소화가 우선일 때 |

**권장 구조:**

```
Phase 1 (초기): 단일 DB
├── project_1 schema
├── project_2 schema
└── shared schema

Phase 2 (성장): 논리적 분리
├── project_1 DB (같은 서버, 다른 인스턴스/포트)
├── project_2 DB (같은 서버, 다른 인스턴스/포트)
└── shared DB (공통 데이터)

Phase 3 (확장): 물리적 분리
├── project_1 DB 서버 (독립 서버)
├── project_2 DB 서버 (독립 서버)
└── shared DB 서버 (공유 서버)
```

**템플릿 내 DB 구조 참조:**
```
infra/_shared/migrations/
├── 001_create_scalp_tables.sql      # 프로젝트 1 스키마
├── 002_create_swing_tables.sql      # 프로젝트 2 스키마
├── 003_create_portfolio_tables.sql  # 공통 스키마
└── 004_create_analysis_tables.sql   # 분석 스키마
```

### 4.4 동일 서버 공존 vs 분리

#### 공존 가능한 경우

```
조건:
- 리소스 충분 (CPU, RAM, 디스크 I/O)
- 장애 영향이 수용 가능
- 운영 복잡성 최소화 우선

구조 (템플릿 기본 구조):
[단일 서버]
├── prj-01 컨테이너         (데이터 수집 앱)
├── prj-02 컨테이너         (웹 API 서버)
├── prj-03 컨테이너         (배치 작업)
├── postgresql 컨테이너     (공유 DB)
└── monitoring 스택
    ├── prometheus
    ├── grafana
    └── alertmanager
```

**공존 시 주의사항:**
- 리소스 제한 설정 필수 (CPU, 메모리 limits)
- 네트워크 격리 (프로젝트별 네트워크 또는 공통 네트워크)
- 볼륨 경로 분리 (`/data/prj-01`, `/data/prj-02`, `/data/prj-03`)
#### 분리가 필요한 경우

```
조건:
- 특정 앱 장애가 심각한 영향 초래
- 한 앱의 부하가 다른 앱 성능에 영향
- 규제/컴플라이언스 요구사항
- 지리적 분산 필요 (레이턴시 최적화)

구조 (확장된 구조):
[프로젝트 1 서버]         [프로젝트 2 서버]
├── prj-01               ├── prj-02
├── prj-01-db            ├── prj-02-db
└── monitoring           └── monitoring

[공유 인프라 서버]
├── 로그 집계
├── 메트릭 저장 (Prometheus/Grafana)
├── 알림 시스템 (Alertmanager)
└── 공유 DB (필요시)
```

**분리 시 데이터 동기화:**
- 프로젝트 간 통신: 메시지 큐 (Redis, RabbitMQ) 또는 REST API
- 실시간 데이터는 pub/sub 패턴
- 히스토리 데이터는 API 조회 또는 읽기 전용 복제
- 공통 모니터링은 중앙 서버로 메트릭 전송

**템플릿 확장 방법:**
```
현재 (단일 서버):
infra/_shared/ 구조 활용

확장 (멀티 서버):
infra/
├── _shared/              # 공통 리소스 재사용
├── project-1/            # 프로젝트 1 전용
└── project-2/            # 프로젝트 2 전용
```

---

## 5. 아키텍처 의사결정 요약

### 5.1 이 아키텍처를 선택한 이유

#### 결정 1: App 레포와 Deploy 레포 분리

**선택 이유:**
- 빌드 버전과 배포 버전의 독립적 관리
- 동일 이미지의 다중 환경 배포
- 롤백 단순화 (이미지 태그 교체만으로)
- 책임 분리로 인한 인지 부하 감소

**근거:**
- GitOps 원칙과 일치
- 업계 표준 (Kubernetes 환경에서도 동일 패턴)
- 팀 규모 확장 시 역할 분담 용이

#### 결정 2: GHCR을 이미지 레지스트리로

**선택 이유:**
- GitHub Actions와 네이티브 통합
- 무료 사용량 충분 (개인/소규모)
- 인증이 GitHub 토큰으로 통합
- 프라이빗 이미지 지원

**근거:**
- 별도 레지스트리 운영 부담 제거
- 기존 GitHub 워크플로우와 자연스러운 통합

#### 결정 3: 템플릿 기반 레포 생성

**선택 이유:**
- 신규 앱/환경 생성 시 일관성 보장
- 베스트 프랙티스 강제
- 초기 설정 시간 단축

**근거:**
- 운영 경험 축적의 재활용
- "바퀴 재발명" 방지
- 팀 온보딩 시간 단축

#### 결정 4: 컨테이너 기반 배포

**선택 이유:**
- 환경 일관성 (개발 = 프로덕션)
- 의존성 격리
- 리소스 제한 가능
- 빠른 배포/롤백

**근거:**
- 서버 OS 업데이트와 앱 독립
- 멀티 앱 공존 용이
- 확장성 기반 마련

#### 배포 도구 사용 가이드 (권장 순서)

배포 및 매니페스트 관리 시 다음 순서를 권장한다(필수 아님). **기본**: Kustomize로 매니페스트와 환경별 오버레이 관리. **재사용·추상화가 필요할 때**: Helm을 선택적으로 사용. **운영 성숙도가 높아질 때**: ArgoCD 등 GitOps 도구를 선택적으로 도입.

### 5.2 버린 선택지

#### 버린 선택 1: 모노레포 (App + Deploy 통합)

```
❌ app-deploy-monorepo/
   ├── src/
   ├── docker/
   └── deploy/
```

**채택하지 않은 이유:**
- 배포 설정 변경 시 앱 CI 트리거됨
- 환경별 브랜치 분기 필요 → 복잡성 폭발
- 이미지 버전과 배포 버전 결합 → 롤백 어려움

#### 버린 선택 2: 서버에서 직접 빌드

```
❌ 서버에서:
   git pull
   docker build
   docker run
```

**채택하지 않은 이유:**
- 빌드 환경 차이로 인한 "내 서버에서는 되는데" 문제
- 서버에 빌드 도구 설치 필요 → 공격 표면 증가
- 빌드 시간으로 인한 배포 지연
- 디스크 공간 낭비 (빌드 캐시)

#### 버린 선택 3: Docker Hub 사용

**채택하지 않은 이유:**
- 무료 tier의 프라이빗 이미지 제한
- GitHub Actions와의 통합이 GHCR보다 복잡
- 두 개의 인증 시스템 관리 필요

#### 결정 4: k3s (경량 Kubernetes) 채택

**채택 이유:**
- 단일 바이너리로 빠른 설치 (< 1분)
- 낮은 리소스 요구사항 (512MB RAM 최소)
- 완전한 Kubernetes API 호환성
- 내장 Traefik Ingress, Local Path Provisioner
- 엣지/IoT/개발 환경부터 프로덕션까지 확장 가능
- GitOps (ArgoCD, Flux) 도입 용이

**Docker Compose 대신 k3s를 선택한 이유:**
- 선언적 상태 관리 (desired state → actual state 자동 조정)
- 자동 롤아웃/롤백, 헬스체크 기반 재시작
- Namespace로 프로젝트 격리
- Horizontal Pod Autoscaler로 자동 스케일링
- 멀티 노드 확장이 자연스러움

#### 버린 선택 5: Ansible/Terraform 전면 도입 (현 시점)

**채택하지 않은 이유:**
- k3s 설치가 충분히 단순 (curl one-liner)
- Kubernetes manifests가 인프라 선언적 관리 역할
- 클러스터 수/복잡도 증가 시 점진적 도입 가능
- 현재는 k3s + kubectl/helm + 스크립트로 충분

#### 버린 선택 6: Docker Compose 유지

**채택하지 않은 이유:**
- 멀티 노드 확장 시 별도 도구 필요 (Docker Swarm 등)
- 선언적 상태 관리 부재 (desired state → actual state)
- 헬스체크 기반 자동 복구가 제한적
- GitOps 워크플로우 통합이 어려움
- Kubernetes 생태계 도구 활용 불가

### 5.3 코드로 내려가도 되는 시점의 기준

#### 필수 선행 조건

| 조건 | 확인 방법 |
|------|----------|
| 책임 분리 합의 | "이건 App 레포에, 이건 Deploy 레포에" 즉답 가능 |
| 디렉터리 구조 확정 | 카테고리별 용도 설명 가능 |
| CI/CD 흐름 이해 | 코드 푸시 → 이미지 생성 → 배포 흐름 그릴 수 있음 |
| 환경 변수 분류 기준 | 민감/비민감, 공통/환경별 구분 가능 |
| 볼륨 전략 확정 | 어떤 데이터를 어디에 저장할지 결정 |

#### 템플릿 사용 순서

```
Phase 1: 템플릿 복사 및 이해
├── Kubernetes_k8s 템플릿 전체 복사
├── 디렉터리 구조 이해
│   ├── app/ - 앱 레포 참조 구조
│   ├── infra/k8s/ - k8s manifests
│   ├── infra/helm/ - Helm charts (선택적)
│   ├── infra/_shared/ - 공통 리소스
│   ├── docs/ - 아키텍처 문서
│   └── tests/k8s/ - manifest 테스트
└── README 및 문서 읽기

Phase 2: App 레포 분리
├── app/prj_01 → 독립 Git 레포 생성
├── Dockerfile 구체화 (언어, 의존성)
├── 비즈니스 로직 구현
├── .github/workflows/ 복사 및 수정 (CI/CD)
├── readinessProbe/livenessProbe용 /health 엔드포인트 구현
└── 이미지 빌드 및 GHCR 푸시 확인

Phase 3: k3s 클러스터 준비
├── k3s 설치: curl -sfL https://get.k3s.io | sh -
├── kubectl 설정: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
├── GHCR 인증: kubectl create secret docker-registry ghcr-secret ...
└── StorageClass 확인 (local-path 기본 제공)

Phase 4: Deploy 레포 구성
├── infra/k8s/ 기반으로 deploy-repo 생성
├── infra/k8s/base/ kustomize base 구성
│   ├── Deployment, Service, ConfigMap 정의
│   └── PVC 정의
├── infra/k8s/overlays/ 환경별 오버레이 구성
├── _shared/secrets/ SealedSecrets 또는 SOPS로 시크릿 관리
└── _shared/monitoring/ kube-prometheus-stack 설정

Phase 5: 첫 배포 및 검증
├── kubectl apply -k infra/k8s/overlays/staging/
├── kubectl rollout status deployment/app-name
├── kubectl get pods,svc,pvc -n prj-01
├── 헬스체크 확인: kubectl exec -it pod/... -- curl localhost:8080/health
└── 모니터링 대시보드 접속 확인

Phase 6: 프로젝트 확장
├── 추가 App 레포 생성 (prj_02, prj_03)
├── 각 프로젝트별 Namespace 생성
├── kustomize overlay로 환경별 설정 분리
├── Ingress로 트래픽 라우팅 설정
└── (선택) ArgoCD Application으로 GitOps 설정
```

#### 코드 작성을 멈춰야 하는 신호

- "이 설정 어디에 넣어야 하지?" 고민이 반복됨
- 임시 해결책이 누적됨 ("일단 여기에...")
- 배포할 때마다 수동 작업이 필요함
- 롤백에 30분 이상 걸림

**위 신호가 나타나면:** 코드 작성을 멈추고 아키텍처 문서로 돌아와 설계 재검토

---

## 부록 A: 문서 간 교차 참조 전체 매핑

### A.1 문서 계층 및 역할

| 문서 | ID | 역할 | 참조 방향 |
|-----|-------|------|---------|
| k8s_architecture.md | ARCH-DEPLOY-001 | 메인 아키텍처 (통합 원칙) | 하위 문서 2개 참조 |
| k8s_app_architecture.md | ARCH-APP-SUB-001 | App 레포 상세 | 메인 & Deploy Sub 참조 |
| k8s_sub_architecture.md | ARCH-DEPLOY-SUB-001 | Deploy 레포 상세 | 메인 & App Sub 참조 |

### A.2 주요 개념 매핑

| 개념 | 메인 (본 문서) | App Sub | Deploy Sub |
|------|-------------|---------|-----------|
| **책임 분리** | 1.1절 원칙 정의 | 2절 App 책임 구체화 | 1.2절 Deploy 책임 구체화 |
| **GHCR 이미지** | 1.2절 CI/CD 흐름 | 4절 빌드/태깅 전략 | 3절 이미지 핸들링 |
| **환경변수** | 1.1절 설정 스키마 vs 값 | 5.2절 스키마 정의 | 2.2절 값 제공 |
| **디렉터리 구조** | 2절, 3절 개요 | 3절 App 레포 구조 | 2절 Deploy 레포 구조 |
| **확장성** | 4절 프로젝트 확장 | 6절 공통 원칙 | 5절 멀티 서버 확장 |

### A.3 템플릿 구조와의 연결

| 템플릿 경로 | 메인 문서 참조 | App Sub 참조 | Deploy Sub 참조 |
|-----------|-------------|------------|---------------|
| `app/prj_*/` | 2절 (App Template) | 3.1절 (디렉터리 구조) | - |
| `infra/_shared/` | 3절 (Deploy Template) | - | 2.2절 (루트 구조) |
| `infra/_shared/monitoring/` | 1.3절 (볼륨 경로) | - | 2.2절 (_shared/) |
| `infra/_shared/scripts/` | 3.3절 (배포 자동화) | - | 2.2절 (scripts/) |
| `docs/arch/` | 본 문서 | 하위 문서 | 하위 문서 |

### A.4 책임 흐름 다이어그램

```
[개발자 코드 푸시]
         │
         ▼
┌────────────────────────────┐
│   App Architecture         │ → [[k8s_app_architecture.md]]
│   (ARCH-APP-SUB-001)            │
│                            │
│  ├── 소스 코드 관리         │   책임:
│  ├── Dockerfile 작성       │   - 이미지 생산
│  ├── CI 빌드/테스트        │   - 환경변수 스키마 정의
│  └── GHCR 푸시            │   - 품질 보증
└────────────────────────────┘
         │
         │ (GHCR 이미지 태그)
         │ ghcr.io/org/app:v1.2.3
         │
         ▼
┌────────────────────────────┐
│  Deploy Sub Architecture   │ → [[k8s_sub_architecture.md]]
│  (ARCH-DEPLOY-SUB-001)      │
│                            │
│  ├── k8s manifest 정의     │   책임:
│  ├── ConfigMap/Secret 관리 │   - 이미지 소비
│  ├── kubectl/helm 배포     │   - 환경변수 값 제공
│  └── ServiceMonitor 연동   │   - 운영 자동화
└────────────────────────────┘
         │
         ▼
   [k3s Cluster]
```

**연결 인터페이스:**
- **유일한 인터페이스**: GHCR 이미지 태그 (예: `ghcr.io/org/app:v1.2.3`)
- **환경변수**: App의 스키마 → Deploy의 ConfigMap/Secret
- **포트**: App의 내부 포트 → Deploy의 Service/Ingress

### A.5 문서 읽기 가이드

**시나리오 1: 아키텍처 전체 이해**
1. 본 문서 (k8s_architecture.md) 전체 읽기
2. k8s_app_architecture.md 1-5절 읽기
3. k8s_sub_architecture.md 1-3절 읽기

**시나리오 2: App 개발자 관점**
1. 본 문서 1.1절 (책임 분리 원칙)
2. k8s_app_architecture.md 전체
3. k8s_sub_architecture.md 3절 (이미지 핸들링) - Deploy가 어떻게 이미지를 사용하는지 이해

**시나리오 3: DevOps/운영자 관점**
1. 본 문서 1.3절 (서버 기준 철학)
2. k8s_sub_architecture.md 전체
3. k8s_app_architecture.md 5절 (인터페이스 규칙) - App이 무엇을 제공하는지 이해

**시나리오 4: 템플릿 활용**
1. 본 문서 전체 (원칙 학습)
2. `app/prj_*/` 구조 확인 → k8s_app_architecture.md 3절 참조
3. `infra/` 구조 확인 → k8s_sub_architecture.md 2절 참조
4. 부록 D (체크리스트) 활용

---

## 부록 B: 현재 템플릿 구조 요약

**상세 내용은:**
- App 구조 → [[k8s_app_architecture.md]] 3절
- Deploy 구조 → [[k8s_sub_architecture.md]] 2절

본 Kubernetes_k8s 템플릿의 실제 디렉터리 구조 (k3s 기반):

```
Kubernetes_k8s/
├── app/                                    # App 레포 참조 구조
│   ├── prj_01/dockerfile                   # 프로젝트 1 Dockerfile 예시
│   ├── prj_02/dockerfile                   # 프로젝트 2 Dockerfile 예시
│   └── prj_03/dockerfile                   # 프로젝트 3 Dockerfile 예시
│
├── infra/                                  # Deploy 레포 구조
│   ├── k8s/                                # [k3s] Kubernetes manifests
│   │   ├── base/                           # kustomize base
│   │   │   ├── namespaces/                 # Namespace 정의
│   │   │   ├── deployments/                # Deployment 정의
│   │   │   ├── services/                   # Service 정의
│   │   │   ├── configmaps/                 # ConfigMap 정의
│   │   │   ├── secrets/                    # Secret 참조
│   │   │   ├── pvc/                        # PersistentVolumeClaim
│   │   │   └── kustomization.yaml
│   │   └── overlays/                       # 환경별 오버레이
│   │       ├── production/
│   │       │   ├── kustomization.yaml
│   │       │   └── patches/
│   │       └── staging/
│   ├── helm/                               # [선택적] Helm charts
│   │   └── apps/
│   ├── argocd/                             # [선택적] GitOps Application
│   │   └── applications/
│   ├── _shared/                            # 공통 인프라 리소스
│   │   ├── monitoring/                     # kube-prometheus-stack 설정
│   │   │   ├── values.yaml                 # Helm values
│   │   │   ├── dashboards/                 # Grafana 대시보드 ConfigMap
│   │   │   └── README.md
│   │   ├── migrations/                     # DB 마이그레이션
│   │   │   ├── 001_create_scalp_tables.sql
│   │   │   └── ...
│   │   ├── secrets/                        # SealedSecrets / SOPS
│   │   │   ├── sealed/                     # 암호화된 시크릿
│   │   │   └── README.md
│   │   ├── scripts/                        # 공통 스크립트
│   │   │   ├── build/                      # 빌드 태그 생성
│   │   │   ├── deploy/                     # kubectl/helm 배포 스크립트
│   │   │   ├── k3s/                        # k3s 클러스터 관리
│   │   │   ├── env/                        # 환경 설정
│   │   │   ├── migrate/                    # 마이그레이션 Job 실행
│   │   │   └── oci/                        # OCI 프로비저닝
│   │   └── README.md
│   └── README.md
│
├── docs/                                   # 아키텍처 문서
│   └── arch/
│       ├── k8s_architecture.md          # 본 문서
│       ├── k8s_app_architecture.md
│       └── k8s_sub_architecture
│
├── tests/                                  # 테스트 구조 참조
│   ├── unit/
│   ├── integration/
│   ├── smoke/
│   ├── perf/
│   └── k8s/                                # k8s manifest 테스트
│       ├── lint/                           # kubeconform, kubeval
│       └── e2e/                            # 로컬 k3d 기반 E2E
│
├── .github/                                # CI/CD 워크플로우
│   └── copilot-instructions.md
│
├── .gitignore
└── README.md
```

**핵심 특징:**
1. **app/** - App 레포 구조 참조용 (실제로는 독립 Git 레포)
2. **infra/k8s/** - kustomize 기반 Kubernetes manifests
3. **infra/helm/** - 선택적 Helm charts
4. **infra/_shared/** - 모든 환경에서 재사용하는 공통 리소스
5. **docs/arch/** - 아키텍처 설계 원칙 및 가이드

**스크립트 상세:**
- **build/**: `generate_build_tag.ps1`, `generate_build_tag.sh` - 빌드 태그 생성
- **deploy/**: `k8s-deploy.sh`, `helm-deploy.sh`, `check_health.sh` - k8s 배포 자동화
- **k3s/**: `install.sh`, `join-agent.sh`, `backup.sh` - k3s 클러스터 관리
- **env/**: `setup_env_secure.sh` - 환경 변수 보안 설정
- **migrate/**: `run-migration-job.sh` - 마이그레이션 Job 실행
- **oci/**: `oci_launch_instance.ps1`, `cloud-init-k3s.yaml` - OCI k3s 프로비저닝

---

## 부록 C: 템플릿 디렉터리 매핑

**상세 매핑은:**
- App 레포 매핑 → [[k8s_app_architecture.md]] 부록 A.3
- Deploy 레포 매핑 → [[k8s_sub_architecture.md]] 부록 A.3

본 템플릿과 실제 프로젝트 구조의 매핑 (k3s 기반):

| 템플릿 경로 | 실제 프로젝트 | 용도 | 비고 |
|-----------|-------------|------|------|
| `app/prj_01/` | `your-app-repo/` | App 레포 (독립 Git 레포) | 템플릿은 참조용, 실제로는 분리 |
| `app/prj_02/` | `another-app-repo/` | 다른 App 레포 | 각 앱은 독립 레포 |
| `infra/k8s/base/` | `deploy-repo/k8s/base/` | kustomize base | 공통 k8s manifests |
| `infra/k8s/overlays/` | `deploy-repo/k8s/overlays/` | 환경별 오버레이 | production, staging |
| `infra/helm/` | `deploy-repo/helm/` | Helm charts | 선택적 사용 |
| `infra/argocd/` | `deploy-repo/argocd/` | GitOps Application | 선택적 사용 |
| `infra/_shared/` | `deploy-repo/_shared/` | 공통 인프라 리소스 | 그대로 사용 |
| `infra/_shared/monitoring/` | `deploy-repo/_shared/monitoring/` | kube-prometheus-stack | Helm values |
| `infra/_shared/secrets/` | `deploy-repo/_shared/secrets/` | SealedSecrets/SOPS | 암호화하여 Git 추적 |
| `infra/_shared/scripts/k3s/` | `deploy-repo/_shared/scripts/k3s/` | k3s 클러스터 관리 | 설치, 노드 추가, 백업 |
| `.github/workflows/` | `app-repo/.github/workflows/` | CI/CD 파이프라인 | App 레포로 복사 |
| `tests/k8s/` | `deploy-repo/tests/k8s/` | manifest 테스트 | kubeconform, E2E |
| `docs/arch/` | `deploy-repo/docs/` | 아키텍처 문서 | 참조 문서, 프로젝트별 커스터마이징 |

**k3s 환경 사용 가이드:**
1. **App 레포 생성**: `app/prj_*` 구조 참조, /health 엔드포인트 구현
2. **k3s 클러스터 준비**: `scripts/k3s/install.sh` 또는 직접 설치
3. **Deploy 레포 구성**: `infra/k8s/` 기반으로 manifests 구성
4. **시크릿 관리**: SealedSecrets 또는 SOPS로 암호화
5. **배포**: `kubectl apply -k` 또는 ArgoCD 동기화

---

## 부록 D: 용어 정의

| 용어 | 정의 |
|------|------|
| App 레포 | 애플리케이션 소스 코드와 빌드 정의를 포함하는 Git 저장소 |
| Deploy 레포 | 클러스터/환경별 배포 설정을 포함하는 Git 저장소 |
| GHCR | GitHub Container Registry, 컨테이너 이미지 저장소 |
| 이미지 태그 | 컨테이너 이미지의 버전 식별자 (예: v1.2.3) |
| k3s | Rancher에서 개발한 경량 Kubernetes 배포판, 단일 바이너리 |
| kustomize | Kubernetes manifest를 환경별로 커스터마이징하는 도구 |
| Helm | Kubernetes 패키지 관리자, chart로 앱을 패키징 |
| Deployment | Kubernetes에서 Pod를 선언적으로 관리하는 리소스 |
| Service | Kubernetes에서 Pod 집합에 대한 네트워크 접근을 제공하는 리소스 |
| ConfigMap | Kubernetes에서 비밀이 아닌 설정 데이터를 저장하는 리소스 |
| Secret | Kubernetes에서 민감한 정보를 저장하는 리소스 |
| PVC | PersistentVolumeClaim, 영속 스토리지 요청 |
| Ingress | Kubernetes에서 HTTP/HTTPS 외부 접근을 관리하는 리소스 |
| SealedSecrets | Secret을 암호화하여 Git에 안전하게 저장하는 도구 |
| ArgoCD | Kubernetes용 GitOps CD 도구 |
| readinessProbe | Pod가 트래픽을 받을 준비가 되었는지 확인하는 헬스체크 |
| livenessProbe | Pod가 살아있는지 확인하고 죽으면 재시작하는 헬스체크 |
| 템플릿 레포 | 신규 프로젝트 생성 시 참조하는 표준 구조 레포 (본 Kubernetes_k8s) |
| 공통 리소스 | 모든 환경에서 재사용 가능한 인프라 설정 (`_shared/`) |

---

## 부록 E: 실제 프로젝트 체크리스트 (k3s 기반)

**관련 문서:**
- App 레포 구성 → [[k8s_app_architecture.md]] 전체
- Deploy 레포 구성 → [[k8s_sub_architecture.md]] 전체

템플릿을 기반으로 실제 프로젝트 구성 시 확인 사항:

### App 레포 구성
- [ ] 템플릿의 `app/prj_*` 구조 참조하여 새 Git 레포 생성
- [ ] Dockerfile 작성 (언어, 의존성, 빌드 스크립트)
- [ ] 비즈니스 로직 구현
- [ ] `/health` 및 `/ready` 엔드포인트 구현 (k8s Probe용)
- [ ] `.env.example` 작성 (환경 변수 스키마)
- [ ] CI/CD 워크플로우 설정 (`.github/workflows/`)
- [ ] 단위 테스트, 통합 테스트 구현
- [ ] Graceful shutdown 구현 (SIGTERM 처리)
- [ ] README 작성 (앱 설명, 로컬 실행 방법)

### k3s 클러스터 준비
- [ ] k3s 설치: `curl -sfL https://get.k3s.io | sh -`
- [ ] kubectl 설정: `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml`
- [ ] GHCR 인증 Secret 생성: `kubectl create secret docker-registry ghcr-secret ...`
- [ ] StorageClass 확인: `kubectl get storageclass`
- [ ] (선택) 워커 노드 추가: `k3s agent` 설치
- [ ] (선택) Ingress Controller 확인 (Traefik 기본 포함)

### Deploy 레포 구성
- [ ] 템플릿의 `infra/k8s/` 기반으로 deploy-repo 생성
- [ ] `k8s/base/` kustomize base 구성
  - [ ] Namespace 정의
  - [ ] Deployment 정의 (이미지, 리소스, Probe)
  - [ ] Service 정의
  - [ ] ConfigMap 정의
  - [ ] PVC 정의
  - [ ] kustomization.yaml 작성
- [ ] `k8s/overlays/production/` 환경별 오버레이 구성
- [ ] `_shared/secrets/` SealedSecrets 또는 SOPS 설정
- [ ] `_shared/monitoring/` kube-prometheus-stack values 설정
- [ ] `_shared/scripts/deploy/` k8s 배포 스크립트 확인

### 첫 배포 및 검증
- [ ] `kubectl apply -k infra/k8s/overlays/staging/`
- [ ] `kubectl rollout status deployment/app-name -n namespace`
- [ ] `kubectl get pods,svc,pvc -n namespace`
- [ ] 헬스체크 확인: Probe 상태, 로그 확인
- [ ] (선택) Ingress 설정 및 외부 접근 확인
- [ ] 모니터링 대시보드 접속 확인

### 운영 준비
- [ ] 백업 정책 수립 (PVC 백업, etcd 스냅샷)
- [ ] 롤백 절차 문서화: `kubectl rollout undo`
- [ ] 알림 설정 (Alertmanager)
- [ ] 로그 수집 설정 (stdout → 로그 수집기)
- [ ] Resource Limits/Requests 튜닝
- [ ] (선택) HPA (Horizontal Pod Autoscaler) 설정
- [ ] (선택) PodDisruptionBudget 설정
- [ ] (선택) ArgoCD Application으로 GitOps 전환

---

## 6. k3s 아키텍처 선택 이유

### 6.1 k3s란?

k3s는 Rancher에서 개발한 **경량 Kubernetes 배포판**으로, 다음 특징을 가진다:

| 특징 | 설명 |
|------|------|
| 단일 바이너리 | ~60MB 크기의 단일 실행 파일 |
| 빠른 설치 | 30초 이내 설치 완료 |
| 낮은 리소스 | 512MB RAM, 1 CPU 최소 요구사항 |
| 완전한 호환성 | Kubernetes API 100% 호환 |
| 내장 컴포넌트 | Traefik, CoreDNS, Local Path Provisioner 포함 |
| 인증 완료 | CNCF 인증 Kubernetes 배포판 |

### 6.2 k3s를 선택한 이유

#### Docker Compose 대비 장점

| 관점 | Docker Compose | k3s |
|------|---------------|-----|
| **선언적 관리** | 명령 실행 필요 (`up -d`) | 자동 상태 조정 (desired → actual) |
| **자동 복구** | 수동 또는 스크립트 필요 | livenessProbe 기반 자동 재시작 |
| **수평 확장** | 수동 설정 필요 | `replicas` 값 변경으로 즉시 확장 |
| **롤링 업데이트** | 다운타임 발생 가능 | 무중단 롤링 업데이트 |
| **롤백** | 이전 태그로 수동 변경 | `kubectl rollout undo` 한 줄 |
| **시크릿 관리** | .env 파일 (평문) | Secret (base64) + SealedSecrets (암호화) |
| **네트워크 격리** | Docker network | NetworkPolicy로 세밀한 제어 |
| **멀티 노드** | Docker Swarm 등 별도 도구 | `k3s agent`로 즉시 노드 추가 |
| **생태계** | 제한적 | Helm, ArgoCD, Prometheus Operator 등 |

#### 언제 k3s가 적합한가?

- 단일 서버에서 시작하지만 **확장 가능성**을 원할 때
- **GitOps** 워크플로우를 도입하고 싶을 때
- **선언적 인프라 관리**가 필요할 때
- Kubernetes 생태계 도구를 활용하고 싶을 때
- 개발/스테이징/프로덕션 환경 **일관성**을 원할 때

### 6.3 k3s 아키텍처 개요

```
[k3s Cluster]
├── Control Plane (k3s server)
│   ├── API Server
│   ├── Controller Manager
│   ├── Scheduler
│   ├── etcd (임베디드 또는 외부)
│   └── kubelet
│
├── Worker Nodes (k3s agent) - 선택적
│   └── kubelet
│
├── 내장 컴포넌트
│   ├── Traefik (Ingress Controller)
│   ├── CoreDNS (서비스 디스커버리)
│   ├── Local Path Provisioner (동적 PV 프로비저닝)
│   └── Flannel (CNI - 네트워킹)
│
└── 워크로드
    ├── Namespace: prj-01
    │   ├── Deployment → ReplicaSet → Pod
    │   ├── Service (ClusterIP/LoadBalancer)
    │   ├── ConfigMap, Secret
    │   └── PVC → PV
    └── Namespace: monitoring
        └── kube-prometheus-stack
```

---

## 7. Kubernetes 핵심 개념 매핑

### 7.1 Docker Compose → Kubernetes 개념 매핑

아래 매핑은 Docker Compose에서 전환하는 독자를 위한 참고용이며, 본 아키텍처의 운영 런타임은 k3s/Kubernetes만 대상으로 한다.

| Docker Compose | Kubernetes | 설명 |
|---------------|------------|------|
| `services:` | Deployment + Service | Pod 관리 + 네트워크 노출 |
| `image:` | `spec.containers[].image` | 컨테이너 이미지 |
| `environment:` | ConfigMap, Secret | 환경변수 주입 |
| `volumes:` | PVC + volumeMounts | 영속 스토리지 |
| `ports:` | Service (NodePort/LoadBalancer) | 포트 노출 |
| `networks:` | Service (ClusterIP) + NetworkPolicy | 내부 통신, 네트워크 격리 |
| `depends_on:` | initContainers, readinessProbe | 시작 순서, 준비 상태 |
| `restart: always` | `restartPolicy: Always` | 재시작 정책 |
| `healthcheck:` | readinessProbe, livenessProbe | 헬스체크 |
| `deploy.replicas:` | `spec.replicas` | 복제본 수 |
| `deploy.resources:` | `resources.requests/limits` | 리소스 제한 |

### 7.2 파일 구조 매핑

| Docker Compose | Kubernetes (kustomize) |
|---------------|------------------------|
| `docker-compose.yml` | `k8s/base/deployments/*.yaml` |
| `.env` | `k8s/base/configmaps/*.yaml` |
| `.env.local` (시크릿) | `k8s/base/secrets/*.yaml` + SealedSecrets |
| `docker-compose.override.yml` | `k8s/overlays/{env}/patches/*.yaml` |
| 없음 (수동 관리) | `kustomization.yaml` (리소스 조합) |

### 7.3 명령어 매핑

| Docker Compose | Kubernetes (kubectl) |
|---------------|---------------------|
| `docker-compose up -d` | `kubectl apply -k overlays/production/` |
| `docker-compose down` | `kubectl delete -k overlays/production/` |
| `docker-compose ps` | `kubectl get pods,svc,deploy -n namespace` |
| `docker-compose logs app` | `kubectl logs -f deployment/app -n namespace` |
| `docker-compose exec app sh` | `kubectl exec -it pod/app-xxx -- sh` |
| `docker-compose pull` | `kubectl rollout restart deployment/app` |
| 없음 | `kubectl rollout undo deployment/app` (롤백) |
| 없음 | `kubectl scale deployment/app --replicas=3` (스케일) |

### 7.4 배포 흐름 비교

**Docker Compose 배포:**
```bash
# 이미지 pull
docker-compose pull

# 서비스 시작/재시작
docker-compose up -d

# 상태 확인
docker-compose ps
```

**k3s/Kubernetes 배포:**
```bash
# 이미지 태그 업데이트 (kustomize)
cd infra/k8s/overlays/production
kustomize edit set image ghcr.io/org/app=ghcr.io/org/app:v1.2.3

# 배포 적용
kubectl apply -k .

# 롤아웃 상태 확인 (자동으로 이미지 pull)
kubectl rollout status deployment/app -n prj-01

# Pod 상태 확인
kubectl get pods -n prj-01
```

---
