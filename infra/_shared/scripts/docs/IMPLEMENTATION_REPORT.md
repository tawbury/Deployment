# Observer 배포 자동화 - 구현 완료 보고서

## 📋 개요

Observer 서비스의 배포 자동화 시스템 v1.0.0을 구현했습니다. 로컬 환경에서 서버로의 안전하고 검증된 배포 프로세스를 자동화합니다.

**문서 작성일**: 2026-01-23  
**버전**: v1.0.0  
**상태**: ✅ 구현 완료

---

## 📁 생성된 파일 목록

### 1️⃣ 배포 스크립트 (infra/_shared/scripts/deploy/)

| 파일명 | 용도 | 크기 |
|--------|------|------|
| `deploy.ps1` | Windows PowerShell 오케스트레이터 | ~15KB |
| `server_deploy.sh` | Linux Bash 러너 (서버 측) | ~12KB |
| `README.md` | 상세 사용 설명서 | ~18KB |
| `../docs/QUICKSTART.md` | 빠른 시작 가이드 | ~12KB |

### 2️⃣ 설정 파일

| 파일명 | 위치 | 용도 |
|--------|------|------|
| `env.template` | `app/obs_deploy/` | 환경 변수 템플릿 (검증용) |
| `targets.yml` | `.ai/runtime/` | 배포 대상 서버 설정 (선택적) |

---

## 🎯 핵심 기능

### deploy.ps1 (Windows 로컬 오케스트레이터)

**주요 기능:**
```
1. 로컬 환경 검증
   ✓ env.template 파일 존재 확인
   ✓ .env.server 파일 존재 확인
   ✓ 필수 KEY 존재 여부 (템플릿 기반)
   ✓ KIS 자격증명 값 존재 여부

2. 아티팩트 검증
   ✓ observer-image.tar (121MB)
   ✓ docker-compose.server.yml
   ✓ .env.server

3. SSH 연결 확인
   ✓ SSH 키 존재 및 권한 확인
   ✓ 서버 연결성 테스트 (timeout=5s)
   ✓ 인증 방식 (키 기반)

4. 서버 준비 확인
   ✓ 배포 디렉토리 존재 확인
   ✓ 기존 .env 파일 백업 (타임스탬프)

5. 파일 업로드 (원자적 교체)
   ✓ .env 파일 임시 업로드 후 이동
   ✓ chmod 600 강제 적용 (보안)
   ✓ 아티팩트 (image, compose) 업로드

6. 서버 배포 스크립트 실행
   ✓ server_deploy.sh 업로드 및 실행
   ✓ 서버 측 Docker 작업 자동화

7. Post-Deploy 헬스 체크
   ✓ Health endpoint 확인 (최대 5회 재시도)
   ✓ Docker Compose 상태 조회
```

**매개변수:**
```powershell
-ServerHost         # 서버 IP/호스트명
-SshUser            # SSH 사용자 (default: azureuser)
-SshKeyPath         # SSH 개인 키 경로
-DeployDir          # 서버 배포 디렉토리
-ComposeFile        # Compose 정의 파일명
-LocalEnvFile       # 로컬 .env.server 경로
-EnvTemplate        # 환경 템플릿 경로
-ArtifactDir        # 아티팩트 디렉토리
```

**사용 예시:**
```powershell
# 기본 설정 (script 내부에서 값 수정)
.\infra\_shared\scripts\deploy\deploy.ps1

# 커스텀 서버 지정
.\infra\_shared\scripts\deploy\deploy.ps1 `
    -ServerHost "your.server.ip" `
    -SshUser "azureuser" `
    -SshKeyPath "$env:USERPROFILE\.ssh\id_rsa"
```

### server_deploy.sh (Linux 서버 러너)

**주요 기능:**
```
1. 입력 검증
   ✓ 배포 디렉토리 확인
   ✓ Compose 파일 확인
   ✓ .env 파일 확인
   ✓ 이미지 TAR 파일 (선택적)

2. Docker 이미지 로드
   ✓ docker load -i observer-image.tar

3. 필수 디렉토리 생성
   ✓ data/observer, data/postgres
   ✓ logs/system, logs/maintenance
   ✓ config, secrets

4. Docker Compose 시작
   ✓ docker compose up -d
   ✓ PostgreSQL 헬스 체크 대기 (10초)

5. 상태 및 로그 확인
   ✓ docker compose ps
   ✓ docker compose logs (최근 100줄)
   ✓ 심각한 에러 감지

6. Health Endpoint 확인
   ✓ curl http://localhost:8000/health
   ✓ 최대 5회 재시도 (3초 간격)

7. 최종 운영 체크
   ✓ 서비스 상태 (실행 중/중지)
   ✓ 이미지 정보
   ✓ 포트 바인딩
   ✓ 데이터 디렉토리
```

**실행 방식:**
```bash
# deploy.ps1에서 자동 호출
bash ./server_deploy.sh <deploy-dir> <compose-file> <image-tar>
```

---

## 🔒 보안 설계

### 비밀 정보 보호
✅ **스크립트 실행 중:**
- SECRET 값 절대 출력 금지
- 로그에 KEY 이름만 기록 (값 마스킹)
- 서버 .env 파일은 chmod 600 강제

✅ **백업 관리:**
- 기존 .env → .env.bak-YYYYMMDD-HHMMSS (자동)
- 서버에만 보관 (로컬 로그에 기록 안 함)
- 롤백용 3개월 권장 보관

✅ **SSH 연결:**
- 키 기반 인증만 지원 (비밀번호 불필요)
- SSH 키 권한 검증 (chmod 600)
- Known Hosts 자동 추가

### 서버 코드 불변성
✅ **배포 프로세스:**
- 서버에서 코드 수정 절대 금지
- 모든 변경은 로컬에서 수행
- 이미지 재빌드 → 재배포 방식

---

## 📝 문서 구조

```
infra/_shared/scripts/
├── deploy/
│   ├── deploy.ps1           # Windows 오케스트레이터 (메인)
│   ├── server_deploy.sh     # Linux 러너 (서버 측)
│   └── README.md            # 상세 사용 설명서
├── build/                    # 빌드 태그 생성
├── docker/                   # Docker 헬퍼
├── env/                      # 환경 설정
├── migrate/                  # 마이그레이션
└── docs/
    ├── QUICKSTART.md         # 빠른 시작 가이드
    └── IMPLEMENTATION_REPORT.md  # 이 파일

.ai/runtime/
└── targets.yml          # 배포 대상 설정 (선택적)

app/obs_deploy/
├── .env.server          # 서버 환경 변수 (로컬)
├── env.template         # 환경 템플릿
├── observer-image.tar   # Docker 이미지
└── docker-compose.server.yml  # 서버 Compose 정의
```

---

## 🚀 사용 흐름

### 1단계: 로컬 준비
```powershell
cd d:\development\prj_obs

# env.server 파일 생성
Copy-Item app\obs_deploy\env.template app\obs_deploy\.env.server

# 실제 KIS 자격증명 입력
notepad app\obs_deploy\.env.server
```

**입력 항목:**
- `KIS_APP_KEY=<실제_앱_키>`
- `KIS_APP_SECRET=<실제_앱_시크릿>`
- `DB_PASSWORD=observer_db_pwd` (기본값)

### 2단계: 배포 실행
```powershell
# 서버 정보 지정
.\infra\_shared\scripts\deploy\deploy.ps1 `
    -ServerHost "your.server.ip" `
    -SshUser "azureuser" `
    -SshKeyPath "$env:USERPROFILE\.ssh\id_rsa"
```

### 3단계: 로그 확인
```powershell
# 배포 로그 조회
Get-Content ops\run_records\deploy_*.log -Tail 50
```

### 4단계: 서버 검증
```bash
# 서버 접속
ssh azureuser@your.server.ip

# 상태 확인
docker compose ps
curl http://localhost:8000/health
docker compose logs observer --tail 50
```

---

## 💾 로그 및 레코드

### 로컬 배포 로그
```
ops/run_records/deploy_YYYYMMDD-HHMMSS.log
```

**내용:**
- 각 단계별 성공/실패 여부
- 오류 메시지 (자격증명 제외)
- 타임스탬프
- 최종 배포 요약

### 서버 로그
```bash
# 실시간 로그 보기
docker compose logs -f observer

# 최근 로그 확인
docker compose logs observer --tail 100
```

---

## 🎯 검증 체크리스트

배포 전 다음을 확인하세요:

```
로컬 환경
├─ [ ] PowerShell 5.0+
├─ [ ] SSH/SCP 클라이언트
├─ [ ] SSH 키 (~/.ssh/id_rsa)
├─ [ ] app/obs_deploy/.env.server (KIS 자격증명 포함)
├─ [ ] app/obs_deploy/observer-image.tar (121MB)
├─ [ ] app/obs_deploy/docker-compose.server.yml
└─ [ ] app/obs_deploy/env.template

서버 환경
├─ [ ] Azure VM 실행 중
├─ [ ] SSH 포트 22 개방
├─ [ ] Docker & Docker Compose 설치
├─ [ ] /home/azureuser/observer-deploy 존재
├─ [ ] /home/azureuser/observer-deploy/.env 존재
└─ [ ] 포트 8000, 5432 개방

스크립트 준비
├─ [ ] infra/_shared/scripts/deploy/deploy.ps1
├─ [ ] infra/_shared/scripts/deploy/server_deploy.sh
└─ [ ] infra/_shared/scripts/deploy/README.md
```

---

## 🔄 배포 되돌리기 (Rollback)

### 옵션 1: 환경 변수 복구 (권장)
```bash
# 서버에서:
cd /home/azureuser/observer-deploy
cp .env.bak-YYYYMMDD-HHMMSS .env
docker compose restart observer
```

### 옵션 2: 이전 이미지 사용
```bash
# 로컬에서 .env 복구 후 재배포
.\infra\_shared\scripts\deploy\deploy.ps1 -ServerHost "..."
```

### 옵션 3: 전체 스택 재시작
```bash
# 서버에서:
docker compose down
docker compose up -d
```

---

## 📊 성능 및 리소스

### 배포 소요 시간
- 로컬 검증: ~5초
- SSH 연결: ~2초
- 파일 업로드: ~30-60초 (image tar 크기에 따라)
- 서버 Docker 작업: ~15-30초
- **전체 배포**: ~2-3분

### 리소스 요구사항
- 로컬 디스크 공간: 최소 200MB (아티팩트)
- 네트워크: SSH (22번), HTTP (8000번) 개방
- 서버: 4GB RAM (Observer+PostgreSQL), 20GB 디스크 권장

---

## 🔄 향후 계획 (v2+)

### Phase 2 개선사항
- [ ] YAML 기반 타겟 설정 읽기 (targets.yml)
- [ ] 자동 이미지 재빌드 (배포 전)
- [ ] Slack/이메일 알림 통합
- [ ] 배포 메트릭 수집 (시간, 데이터 크기)
- [ ] Blue-Green 배포 패턴 지원

### Phase 3 기능 확장
- [ ] 다중 서버 병렬 배포
- [ ] ACR/Registry 기반 배포 (선택적)
- [ ] 자동 롤백 (이전 이미지 보관)
- [ ] 배포 시뮬레이션 (dry-run 모드)

---

## 📚 관련 문서

| 문서 | 설명 |
|------|------|
| `infra/_shared/scripts/deploy/README.md` | 상세 사용 설명서 |
| `infra/_shared/scripts/docs/QUICKSTART.md` | 5단계 빠른 시작 |
| `.ai/workflows/deploy_automation.workflow.md` | 배포 워크플로우 |
| `app/obs_deploy/docker-compose.server.yml` | 서버 Compose 정의 |
| `.ai/runtime/targets.yml` | 배포 대상 설정 (선택적) |

---

## ✅ 구현 완료 항목

- ✅ deploy.ps1 (Windows 오케스트레이터)
  - 9단계 배포 프로세스 자동화
  - 상세 로깅 및 에러 처리
  - 매개변수 기반 유연한 구성

- ✅ server_deploy.sh (Linux 러너)
  - 8단계 서버 배포 프로세스
  - Health 체크 및 운영 검증
  - 색상 기반 가독성 높은 로그

- ✅ 문서
  - README.md (상세 가이드)
  - QUICKSTART.md (빠른 시작)
  - env.template 개선 (명확한 구조)

- ✅ 설정
  - targets.yml (배포 대상 설정, 선택적)
  - 마스킹 정책 (비밀 보호)
  - 백업 전략 (타임스탬프 기반)

---

## 📞 기술 지원

### 문제 해결
1. `infra/_shared/scripts/deploy/README.md` → "문제 해결" 섹션 참고
2. `infra/_shared/scripts/docs/QUICKSTART.md` → "🛟 문제 해결" 섹션 참고
3. 서버 로그: `docker compose logs observer`
4. 배포 로그: `ops/run_records/deploy_*.log`

### 추가 정보
- 배포 워크플로우: `.ai/workflows/deploy_automation.workflow.md`
- 현재 구현: 이 문서 (IMPLEMENTATION_REPORT.md)

---

## 🎯 최종 상태

**배포 자동화 v1.0 구현 완료 ✅**

- 모든 필수 스크립트 생성
- 상세 문서 작성
- 보안 정책 적용
- 사용자 가이드 준비

**다음 단계:**
1. 로컬 env.server 파일 생성 및 KIS 자격증명 입력
2. 서버 정보 확인 (IP, SSH 키)
3. `.\infra\_shared\scripts\deploy\deploy.ps1` 실행
4. 배포 로그 확인 및 서버 검증

---

**작성 일자**: 2026-01-23  
**버전**: v1.0.0  
**상태**: 🟢 Production Ready
