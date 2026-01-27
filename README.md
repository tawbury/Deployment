# Kubernetes K8s 템플릿 프로젝트

이 프로젝트는 Kubernetes 및 컨테이너 기반 인프라 구축을 위한 템플릿 프로젝트입니다. Docker Compose부터 Kubernetes까지 확장 가능한 구조로 설계되었습니다.

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

- **공통 인프라 리소스**: 모든 환경에서 재사용 가능한 모니터링 및 데이터베이스 설정
- **다중 환경 지원**: 로컬 개발, OCI 배포, 향후 Kubernetes 배포 지원
- **확장 가능한 구조**: 점진적으로 Kubernetes로 전환 가능한 아키텍처
- **모니터링 스택**: Prometheus, Grafana, Alertmanager 통합
- **데이터베이스 마이그레이션**: PostgreSQL 기반 스키마 관리

## 프로젝트 구조

```
Kubernetes_k8s/
├── infra/                          # 인프라 설정
│   ├── _shared/                    # 공통 리소스 (모든 환경 공통)
│   │   ├── monitoring/             # 모니터링 스택 설정
│   │   │   ├── prometheus.yml
│   │   │   ├── alertmanager.yml
│   │   │   ├── prometheus_alerting_rules.yaml
│   │   │   ├── grafana_dashboard.json
│   │   │   ├── grafana_datasources.yml
│   │   │   └── docker-compose.yml
│   │   ├── migrations/            # DB 마이그레이션 스크립트
│   │   │   ├── 001_create_scalp_tables.sql
│   │   │   ├── 002_create_swing_tables.sql
│   │   │   └── 003_create_portfolio_tables.sql
│   │   ├── secrets/               # 민감한 정보 (환경 변수, 인증서 등)
│   │   │   ├── .env.prod          # 프로덕션 환경 변수 (Git에 커밋되지 않음)
│   │   │   └── README.md
│   │   ├── scripts/               # 공통 스크립트
│   │   │   ├── deploy/            # 배포 (deploy.ps1, server_deploy.sh 등)
│   │   │   ├── migrate/           # DB 마이그레이션 (migrate.sh)
│   │   │   ├── docker/            # Docker/Compose 헬퍼
│   │   │   ├── env/               # 환경 설정 (setup_env_secure.sh 등)
│   │   │   └── README.md
│   │   └── README.md
│   │
│   └── oci_deploy/                # OCI 배포 전용 설정
│       ├── docker-compose.prod.yml
│       ├── .env.prod.example
│       └── README_APP_LEGACY.md
│
├── .ai/                            # AI 시스템 설정 (다중 에이전트 시스템)
│   ├── agents/                     # AI 에이전트 정의
│   ├── skills/                     # 에이전트 스킬
│   ├── workflows/                  # 워크플로우 정의
│   └── README.md
│
├── .github/                        # GitHub Actions 워크플로우
│   └── workflows/
│       ├── build-push-tag.yml
│       └── deploy-tag.yml
│
├── mcp-cli/                        # MCP CLI 도구
│   └── README.md
│
└── README.md                        # 이 파일
```

## 빠른 시작

### 1. 사전 요구사항

- Docker & Docker Compose
- PostgreSQL (또는 Docker로 실행)
- (선택) OCI CLI (OCI 배포 시)

### 2. 모니터링 스택 실행

```bash
# 모니터링 스택만 독립 실행
cd infra/_shared/monitoring
docker-compose up -d
```

접속:
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000 (기본 계정: admin/admin)
- Alertmanager: http://localhost:9093

### 3. 전체 스택 실행 (OCI 배포)

```bash
# 환경 변수 설정
cd infra/oci_deploy
cp .env.prod.example ../_shared/secrets/.env.prod
# ../_shared/secrets/.env.prod 파일 편집

# 전체 스택 실행
docker-compose -f docker-compose.prod.yml --env-file ../_shared/secrets/.env.prod up -d
```

## 주요 구성 요소

### 인프라 레이어 (`infra/`)

#### 공통 리소스 (`infra/_shared/`)

**모니터링 스택**
- **Prometheus**: 메트릭 수집 및 저장
- **Grafana**: 대시보드 및 시각화
- **Alertmanager**: 알림 관리 및 라우팅

**데이터베이스 마이그레이션**
- Scalp Trading (Track B) 테이블
- Swing Trading (Track A) 테이블
- 포트폴리오 및 리밸런싱 테이블

**Secrets (민감한 정보)**
- 환경 변수 파일 (`.env.prod`, `.env.dev` 등)
- SSL 인증서
- SSH 키
- 클라우드 인증 정보

**Scripts (공통 스크립트)**
- deploy/: 배포 (deploy.ps1, server_deploy.sh 등)
- migrate/: DB 마이그레이션 (migrate.sh)
- docker/: Docker/Compose 헬퍼
- env/: 환경 설정 (setup_env_secure.sh 등)

자세한 내용은 [`infra/_shared/README.md`](infra/_shared/README.md) 참조

#### 환경별 설정

- **`infra/oci_deploy/`**: Oracle Cloud Infrastructure 배포 설정
  - 자세한 내용은 [`infra/oci_deploy/README_APP_LEGACY.md`](infra/oci_deploy/README_APP_LEGACY.md) 참조

### AI 시스템 (`.ai/`)

다중 에이전트 AI 시스템으로 다음을 포함합니다:

- **에이전트**: Developer, HR, PM, Finance, Contents-Creator
- **스킬 시스템**: 모듈화된 스킬 기반 작업 처리
- **워크플로우**: 통합 개발, 콘텐츠 생성, 재무 관리 등

자세한 내용은 [`.ai/README.md`](.ai/README.md) 참조

### CI/CD (`.github/workflows/`)

- **build-push-tag.yml**: 이미지 빌드 및 푸시
- **deploy-tag.yml**: 태그 기반 배포

## 인프라 설정

### 모니터링 설정

모니터링 설정은 `infra/_shared/monitoring/`에 위치하며, 모든 환경에서 공통으로 사용됩니다.

**주요 파일:**
- `prometheus.yml`: Prometheus 스크래이퍼 설정
- `alertmanager.yml`: Alertmanager 라우팅 규칙
- `prometheus_alerting_rules.yaml`: 알림 규칙 정의
- `grafana_dashboard.json`: Grafana 대시보드
- `grafana_datasources.yml`: Grafana 데이터소스 설정

**Docker Compose에서 사용:**
```yaml
volumes:
  - ../_shared/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
  - ../_shared/monitoring/prometheus_alerting_rules.yaml:/etc/prometheus/rules.yaml
  - ../_shared/monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml
  - ../_shared/monitoring/grafana_dashboard.json:/etc/grafana/provisioning/dashboards/observer.json
  - ../_shared/monitoring/grafana_datasources.yml:/etc/grafana/provisioning/datasources/datasources.yml
```

### 데이터베이스 마이그레이션

마이그레이션 스크립트는 `infra/_shared/migrations/`에 위치합니다.

**Docker Compose에서 사용:**
```yaml
volumes:
  - ../_shared/migrations:/docker-entrypoint-initdb.d
```

**수동 실행:**
```bash
psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} < infra/_shared/migrations/001_create_scalp_tables.sql
psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} < infra/_shared/migrations/002_create_swing_tables.sql
psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} < infra/_shared/migrations/003_create_portfolio_tables.sql
```

## 배포 가이드

### 로컬 개발 환경

```bash
# 모니터링 스택만 실행
cd infra/_shared/monitoring
docker-compose up -d
```

### OCI 배포

1. 환경 변수 설정
   ```bash
   cd infra/oci_deploy
   cp .env.prod.example .env.prod
   # .env.prod 파일 편집
   ```

2. Docker Compose로 배포
   ```bash
   docker-compose -f docker-compose.prod.yml up -d
   ```

자세한 배포 가이드는 [`infra/oci_deploy/README_APP_LEGACY.md`](infra/oci_deploy/README_APP_LEGACY.md) 참조

### Kubernetes 배포 (향후)

향후 Kubernetes 환경으로 전환할 때:
- `infra/_shared/monitoring/`의 설정 파일을 ConfigMap으로 변환
- `infra/_shared/migrations/`를 InitContainer나 Job으로 실행
- `infra/_shared/secrets/`의 환경 변수를 Secret 리소스로 변환
- 동일한 설정 파일을 재사용하여 일관성 유지

## 개발 가이드

### 프로젝트 구조 설계 원칙

1. **공통 리소스 통합**: 모든 환경에서 사용하는 리소스는 `infra/_shared/`에 위치
2. **환경별 분리**: 환경별 설정은 각 디렉토리(`oci_deploy/`, 향후 `k8s/` 등)에서 관리
3. **점진적 확장**: Docker Compose에서 시작하여 Kubernetes로 자연스럽게 전환 가능

### 파일 수정 시 주의사항

- **`infra/_shared/`의 파일 수정**: 모든 환경에 영향을 미치므로 신중하게 수정
- **환경별 커스터마이징**: 각 환경 디렉토리에서 오버라이드하여 관리
- **경로 참조**: 상대 경로(`../_shared/`)를 사용하여 일관성 유지

## 📚 추가 문서

- [공통 인프라 리소스 가이드](infra/_shared/README.md)
- [OCI 배포 가이드](infra/oci_deploy/README_APP_LEGACY.md)
- [AI 시스템 가이드](.ai/README.md)
- [MCP CLI 가이드](mcp-cli/README.md)

## 🔄 변경 이력

| 날짜 | 버전 | 변경 사항 |
|------|------|---------|
| 2026-01-27 | v1.0 | 초기 템플릿 구조 생성 및 리팩토링 완료 |
| 2026-01-27 | v1.1 | 공통 리소스를 `infra/_shared/`로 통합 |

## 📝 라이선스

이 템플릿은 프로젝트 내부 사용을 위한 것입니다.

## 🤝 기여

프로젝트 개선을 위한 제안이나 버그 리포트는 이슈로 등록해주세요.

---

**마지막 업데이트**: 2026-01-27
