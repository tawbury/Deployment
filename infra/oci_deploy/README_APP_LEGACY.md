# OCI (Oracle Cloud Infrastructure) 배포 가이드

## 개요

이 가이드는 Azure Container Instances에서 Oracle Cloud Infrastructure(OCI)로의 Observer 애플리케이션 마이그레이션을 설명합니다.

**마이그레이션 목표:**
- Azure ACI → OCI Compute/Container Instances로 전환
- 기존 애플리케이션 로직 유지
- PostgreSQL 데이터베이스 연동
- Prometheus/Grafana 모니터링 구축

---

## 📁 파일 구조

```
app/oci_deploy/
├── README.md                          # 이 파일
├── monitoring/                         # 모니터링 설정
│   ├── prometheus.yml                 # Prometheus 스크래이퍼 설정
│   ├── alertmanager.yml               # AlertManager 알림 규칙
│   ├── prometheus_alerting_rules.yaml  # 알림 규칙 정의
│   ├── grafana_dashboard.json          # Grafana 대시보드
│   └── grafana_datasources.yml         # Grafana 데이터소스
│
├── migrations/                         # DB 마이그레이션 스크립트
│   ├── 001_create_scalp_tables.sql     # Scalp Trading 테이블
│   ├── 002_create_swing_tables.sql     # Swing Trading 테이블
│   └── 003_create_portfolio_tables.sql # 포트폴리오 테이블
│
└── secrets/                            # 민감 정보 (gitignore)
    └── (로컬에서 관리)
```

**관련 파일:**
- `app/observer/requirements.txt` - Python 의존성
- `app/observer/Dockerfile` - 컨테이너 이미지
- `app/observer/env.template` - 환경 변수 템플릿
- `scripts/deploy/setup_env_secure.sh` - 환경 설정 스크립트
- `scripts/deploy/migrate.sh` - DB 마이그레이션 실행 스크립트

---

## 🚀 배포 사전 요구사항

### 로컬 환경
- Docker & Docker Compose
- OCI CLI (설치: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)
- OCI 계정 및 API 키 생성

### OCI 리소스
- OCI Container Registry (OCIR)
- OCI Compute Instance 또는 Container Instances
- OCI MySQL Database 또는 PostgreSQL Database
- OCI Virtual Cloud Network (VCN)

### 필수 정보 수집
```bash
# OCI 테넌시 정보
TENANCY_OCID="ocid1.tenancy.oc1..."
USER_OCID="ocid1.user.oc1..."
COMPARTMENT_OCID="ocid1.compartment.oc1..."

# 리전 정보 (예: ap-tokyo-1)
OCI_REGION="ap-tokyo-1"

# OCIR 리포지토리 (예: region/tenancy/observer)
OCIR_REPOSITORY="nrt.ocir.io/axxxxx/observer"
```

---

## 📋 배포 단계

### 1단계: 환경 설정

```bash
# .env 파일 생성 (app/observer/.env)
cp app/observer/env.template app/observer/.env

# 필수 환경 변수 설정
export QTS_OBSERVER_STANDALONE=1
export OBSERVER_DATA_DIR=/app/data/observer
export OBSERVER_LOG_DIR=/app/logs
export PYTHONPATH=/app/src:/app

# OCI 관련 환경 변수
export DOCKER_REGISTRY="${OCIR_REPOSITORY}"
export OCI_REGION="ap-tokyo-1"
```

### 2단계: Docker 이미지 빌드 및 푸시

```bash
# 1. 이미지 빌드
cd app/observer
docker build -f ../infra/docker/Dockerfile -t ${DOCKER_REGISTRY}:latest .

# 2. OCI에 로그인
docker login nrt.ocir.io  # 리전에 맞게 수정 (ap, eu, ca 등)
# 사용자명: <tenancy-name>/<username>
# 비밀번호: OCI 사용자 API 토큰

# 3. 이미지 푸시
docker push ${DOCKER_REGISTRY}:latest

# 4. 이미지 확인
oci artifacts container image list \
  --compartment-id ${COMPARTMENT_OCID} \
  --region ${OCI_REGION}
```

### 3단계: OCI에 리소스 배포

#### 3.1 PostgreSQL 데이터베이스 설정

```bash
# OCI MySQL 또는 PostgreSQL Database 서비스를 통해 DB 생성
# 또는 Compute Instance에 PostgreSQL 설치

# DB 연결 정보
export DB_HOST="<rds-endpoint>"
export DB_PORT="5432"
export DB_NAME="observer_db"
export DB_USER="postgres"
export DB_PASSWORD="<secure-password>"  # .env에 저장
```

#### 3.2 DB 마이그레이션 실행

```bash
# 로컬에서 실행 (OCI로 배포 전)
scripts/deploy/migrate.sh \
  --host ${DB_HOST} \
  --port ${DB_PORT} \
  --database ${DB_NAME} \
  --user ${DB_USER}

# 또는 마이그레이션 스크립트 직접 실행
psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} < app/oci_deploy/migrations/001_create_scalp_tables.sql
psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} < app/oci_deploy/migrations/002_create_swing_tables.sql
psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} < app/oci_deploy/migrations/003_create_portfolio_tables.sql
```

#### 3.3 OCI Container Instances 배포

```bash
# OCI CLI를 통한 배포
oci container-instances container-instance create \
  --display-name "observer-app" \
  --compartment-id ${COMPARTMENT_OCID} \
  --containers '[
    {
      "imageName": "'${DOCKER_REGISTRY}':latest",
      "displayName": "observer",
      "environment": {
        "QTS_OBSERVER_STANDALONE": "1",
        "OBSERVER_DATA_DIR": "/app/data/observer",
        "OBSERVER_LOG_DIR": "/app/logs",
        "PYTHONPATH": "/app/src:/app",
        "DB_HOST": "'${DB_HOST}'",
        "DB_PORT": "'${DB_PORT}'",
        "DB_NAME": "'${DB_NAME}'",
        "DB_USER": "'${DB_USER}'"
      }
    }
  ]' \
  --region ${OCI_REGION}
```

**또는 Terraform을 이용한 배포:**

```bash
# terraform/ 디렉토리에서
cd terraform
terraform init
terraform plan
terraform apply
```

### 4단계: 모니터링 설정

#### 4.1 Prometheus 배포

```bash
# Prometheus 컨테이너 실행
docker run -d \
  --name prometheus \
  -p 9090:9090 \
  -v $(pwd)/app/oci_deploy/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus:latest
```

#### 4.2 Grafana 배포

```bash
# Grafana 컨테이너 실행
docker run -d \
  --name grafana \
  -p 3000:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  grafana/grafana:latest

# 데이터소스 및 대시보드 자동 로드 설정
# 필요시 grafana_datasources.yml, grafana_dashboard.json을 Grafana에 임포트
```

#### 4.3 AlertManager 배포

```bash
# AlertManager 컨테이너 실행
docker run -d \
  --name alertmanager \
  -p 9093:9093 \
  -v $(pwd)/app/oci_deploy/monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml \
  prom/alertmanager:latest
```

---

## 🔍 배포 후 검증

### 헬스체크

```bash
# Observer 애플리케이션 상태 확인
curl -s http://<oci-instance-ip>:8000/health || echo "헬스체크 실패"

# Prometheus 상태 확인
curl -s http://<oci-instance-ip>:9090/-/healthy

# Grafana 대시보드 접근
# 브라우저: http://<oci-instance-ip>:3000
```

### 로그 확인

```bash
# OCI Compute Instance 또는 Container Instance에서
docker logs -f observer

# 또는 로그 파일 직접 확인
tail -f /app/logs/observer.log
```

### DB 연결 확인

```bash
# PostgreSQL 연결 테스트
psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} -c "SELECT 1;"

# 테이블 생성 확인
psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} -c "\dt"
```

---

## 🔐 보안 고려사항

### 1. 환경 변수 관리
- `.env` 파일은 `.gitignore`에 포함 (절대 커밋 금지)
- OCI Vault를 통한 시크릿 관리 권장
- API 키는 OCI IAM Policy를 통해 최소 권한 원칙 적용

### 2. 네트워크 보안
- VCN 보안 그룹(Security Lists) 설정
- DB 포트는 애플리케이션만 접근 가능하도록 제한
- Prometheus/Grafana는 내부 네트워크만 허용

### 3. 이미지 보안
- 정기적인 기본 이미지 업데이트
- 컨테이너 취약점 스캔 (OCI Container Registry 기능)
- 불필요한 패키지 제거 (최소 이미지 유지)

---

## 🛠️ 트러블슈팅

### 이미지 푸시 실패
```bash
# 원인: OCIR 인증 실패
# 해결
docker logout nrt.ocir.io
docker login nrt.ocir.io
# 사용자명: <tenancy-name>/<username>
# 비밀번호: OCI API 토큰 (OCI Console에서 재발급)
```

### DB 마이그레이션 실패
```bash
# 원인: DB 연결 불가
# 해결
psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} -c "SELECT 1;"

# 또는 OCI Console에서 DB 연결 설정 확인
# - VCN과 Subnet 확인
# - Security List 규칙 확인
# - 방화벽 설정 확인
```

### 컨테이너 실행 실패
```bash
# 로그 확인
docker logs observer

# 환경 변수 확인
docker inspect observer | grep -A 20 "Env"

# 리소스 한계 확인
docker stats
```

### Prometheus 메트릭 수집 실패
```bash
# Prometheus UI에서 Targets 확인
# http://<oci-instance-ip>:9090/targets

# 애플리케이션이 메트릭을 노출하고 있는지 확인
curl http://<oci-instance-ip>:8000/metrics
```

---

## 📚 참고 자료

- [OCI 공식 문서](https://docs.oracle.com/en-us/iaas/)
- [OCI CLI 참조](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/)
- [Docker 공식 문서](https://docs.docker.com/)
- [Prometheus 문서](https://prometheus.io/docs/)
- [Grafana 문서](https://grafana.com/docs/)

---

## 📝 변경 이력

| 날짜 | 버전 | 변경 사항 |
|------|------|---------|
| 2026-01-24 | v1.0 | 초판 작성 - Azure에서 OCI로 마이그레이션 가이드 |

---

## ❓ 도움말

문제가 발생하거나 추가 정보가 필요하면:
1. 로그 파일 확인 (`/app/logs/`)
2. OCI Console에서 리소스 상태 확인
3. OCI Support에 문의
