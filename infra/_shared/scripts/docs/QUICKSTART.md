# Observer 배포 체크리스트 & 빠른 시작 가이드

## 📋 배포 전 체크리스트

### 1️⃣ 로컬 환경 준비
- [ ] PowerShell 5.0 이상 설치
- [ ] SSH/SCP 클라이언트 설치 (`ssh -V` 확인)
- [ ] SSH 키 존재: `~/.ssh/id_rsa` 또는 사용자 키 경로
- [ ] SSH 키 권한: `chmod 600` (Linux/Mac) 또는 ACL 확인 (Windows)

### 2️⃣ 서버 준비
- [ ] Azure VM 실행 중
- [ ] SSH 포트 22 개방
- [ ] Docker & Docker Compose 설치
- [ ] 배포 디렉토리 존재: `/home/azureuser/observer-deploy`
- [ ] 포트 8000, 5432 개방 (방화벽)

### 3️⃣ 로컬 아티팩트 준비
- [ ] `app/obs_deploy/.env.server` 파일 존재
- [ ] KIS_APP_KEY 값 입력됨
- [ ] KIS_APP_SECRET 값 입력됨
- [ ] `app/obs_deploy/observer-image.tar` 존재 (121MB)
- [ ] `app/obs_deploy/docker-compose.server.yml` 존재
- [ ] `app/obs_deploy/env.template` 존재

### 4️⃣ 스크립트 준비
- [ ] `infra/_shared/scripts/deploy/deploy.ps1` 존재
- [ ] `infra/_shared/scripts/deploy/server_deploy.sh` 존재
- [ ] `infra/_shared/scripts/deploy/README.md` 존재 (사용 설명서)

### 5️⃣ Git 상태
- [ ] 로컬 변경사항 커밋 완료
- [ ] 최신 버전 푸시 완료 (보조 브랜치)
- [ ] `.env` 파일 .gitignore 포함 (비밀 보호)

---

## 🚀 빠른 시작 (5단계)

### Step 1: 환경 변수 준비
```powershell
# 로컬 env.server 파일 생성
cd d:\development\prj_obs
Copy-Item app\obs_deploy\env.template app\obs_deploy\.env.server

# 텍스트 에디터로 열어서 값 입력
notepad app\obs_deploy\.env.server

# 입력 항목:
# - KIS_APP_KEY=<실제_키>
# - KIS_APP_SECRET=<실제_시크릿>
# - DB_PASSWORD=observer_db_pwd (기본값)
```

### Step 2: 배포 스크립트 실행 (기본 설정)
```powershell
# 기본 설정으로 실행 (deploy.ps1에서 값 수정 후)
.\infra\_shared\scripts\deploy\deploy.ps1
```

### Step 3: 배포 스크립트 실행 (커스텀 서버)
```powershell
# 서버 정보와 함께 실행
.\infra\_shared\scripts\deploy\deploy.ps1 `
    -ServerHost "your.server.ip" `
    -SshUser "azureuser" `
    -SshKeyPath "$env:USERPROFILE\.ssh\id_rsa" `
    -DeployDir "/home/azureuser/observer-deploy"

# 또는 별도 SSH 키 사용:
.\infra\_shared\scripts\deploy\deploy.ps1 `
    -ServerHost "your.server.ip" `
    -SshKeyPath "$env:USERPROFILE\.ssh\id_rsa_azure"
```

### Step 4: 로그 확인
```powershell
# 로컬 배포 로그
Get-Content ops\run_records\deploy_*.log -Tail 50

# 또는 실시간 모니터링 (배포 중)
Get-Content ops\run_records\deploy_*.log -Wait
```

### Step 5: 서버 검증
```bash
# 서버 접속
ssh azureuser@your.server.ip

# Compose 상태 확인
cd /home/azureuser/observer-deploy
docker compose ps

# Observer 로그 확인
docker compose logs observer --tail 100

# Health 체크
curl http://localhost:8000/health
curl http://localhost:8000/status
```

---

## 🔍 배포 단계 상세 흐름

```
┌─────────────────────────────────────────────────────────────────┐
│  Windows Local (deploy.ps1)                                     │
├─────────────────────────────────────────────────────────────────┤
│ 1️⃣  로컬 환경 검증                                              │
│     • env.template 확인                                         │
│     • .env.server 확인                                          │
│     • 필수 KEY 존재 여부 (KIS_APP_KEY, KIS_APP_SECRET 등)      │
│                                                                 │
│ 2️⃣  아티팩트 검증                                              │
│     • observer-image.tar (121MB)                               │
│     • docker-compose.server.yml                                │
│     • .env.server                                              │
│                                                                 │
│ 3️⃣  SSH 연결 테스트                                            │
│     • SSH 키 확인                                              │
│     • 서버 연결 테스트                                         │
│                                                                 │
│ 4️⃣  서버 배포 디렉토리 검증                                    │
│     • /home/azureuser/observer-deploy 존재 확인               │
│                                                                 │
│ 5️⃣  서버 .env 백업                                             │
│     • .env.bak-YYYYMMDD-HHMMSS 생성                          │
│                                                                 │
│ 6️⃣  .env 파일 업로드                                           │
│     • 원자적 교체 (.env.tmp → .env)                            │
│     • chmod 600 강제 적용                                     │
│                                                                 │
│ 7️⃣  아티팩트 업로드                                            │
│     • observer-image.tar                                       │
│     • docker-compose.server.yml                                │
│                                                                 │
│ 8️⃣  서버 배포 스크립트 실행                                    │
│     └─────────────────────────────────────────────────┐       │
└──────────────────────────────────────────────────────────────┬─┘
                                                              │
┌─────────────────────────────────────────────────────────────┴─┐
│  Azure VM (server_deploy.sh)                                   │
├──────────────────────────────────────────────────────────────┤
│ 1️⃣  입력 검증                                                 │
│     • 배포 디렉토리 확인                                      │
│     • Compose 파일 확인                                       │
│     • .env 파일 확인                                          │
│                                                               │
│ 2️⃣  Docker 이미지 로드                                        │
│     • docker load -i observer-image.tar                      │
│                                                               │
│ 3️⃣  필수 디렉토리 생성                                        │
│     • data/observer, data/postgres                           │
│     • logs/system, logs/maintenance                          │
│     • config, secrets                                        │
│                                                               │
│ 4️⃣  Docker Compose 시작                                       │
│     • docker compose up -d                                   │
│     • PostgreSQL 헬스 체크 대기 (10초)                       │
│                                                               │
│ 5️⃣  상태 확인                                                │
│     • docker compose ps                                      │
│     • 서비스 Up 상태 확인                                    │
│                                                               │
│ 6️⃣  로그 확인                                                │
│     • docker compose logs --tail 100                         │
│     • 심각한 에러 감지                                       │
│                                                               │
│ 7️⃣  Health Endpoint 확인                                      │
│     • curl http://localhost:8000/health                     │
│     • 최대 5회 재시도 (3초 간격)                            │
│                                                               │
│ 8️⃣  최종 운영 체크                                            │
│     • 서비스 개수 확인                                       │
│     • 이미지 정보                                            │
│     • 포트 바인딩 확인                                       │
│     • 데이터 디렉토리 확인                                   │
│                                                               │
│ ✅  배포 완료                                                 │
└──────────────────────────────────────────────────────────────┘
```

---

## 🛟 문제 해결

### Issue: SSH 연결 실패
```
❌ SSH 연결 실패 (exit code: 255)
```

**원인 & 해결:**
1. SSH 키 경로 확인
   ```powershell
   Test-Path $env:USERPROFILE\.ssh\id_rsa
   ```

2. SSH 키 권한 확인 (Windows)
   - 우클릭 → Properties → Security → Advanced
   - 현재 사용자만 읽기 권한 확인

3. 서버 IP/호스트명 확인
   ```powershell
   Test-NetConnection your.server.ip -Port 22
   ```

### Issue: .env 검증 실패
```
❌ 필수 키 누락: KIS_APP_KEY, KIS_APP_SECRET
```

**원인 & 해결:**
1. .env.server 파일 확인
   ```powershell
   Test-Path app\obs_deploy\.env.server
   ```

2. 파일 내용 확인 (첫 10줄)
   ```powershell
   Get-Content app\obs_deploy\.env.server -Head 10
   ```

3. 값 입력 확인 (비어있는지 체크)
   ```powershell
   (Get-Content app\obs_deploy\.env.server | Where-Object { $_ -like "KIS_APP_KEY=*" })
   ```

### Issue: 서버 docker-compose 실행 실패
```
⚠️ 서버 배포 스크립트 종료 코드: 1
```

**원인 & 해결:**
1. 서버 직접 접속
   ```bash
   ssh azureuser@your.server.ip
   ```

2. 배포 디렉토리 확인
   ```bash
   ls -la /home/azureuser/observer-deploy/
   ```

3. Docker 상태 확인
   ```bash
   docker ps -a
   docker compose ps
   ```

4. 로그 확인
   ```bash
   docker compose logs observer | tail -50
   ```

5. .env 파일 확인
   ```bash
   head -5 /home/azureuser/observer-deploy/.env
   wc -l /home/azureuser/observer-deploy/.env
   ```

---

## 📊 배포 후 모니터링

### 실시간 로그 모니터링
```bash
# 서버에서:
docker compose logs -f observer
```

### 주기적인 상태 확인
```bash
# 1분마다 상태 확인
watch -n 60 'docker compose ps; echo "---"; curl -s http://localhost:8000/health'
```

### 성능 지표 확인
```bash
# CPU, 메모리 사용량
docker stats observer postgres

# 볼륨 사용량
docker exec observer du -sh /app/data/observer

# 데이터베이스 상태
docker compose logs postgres | grep "ready to accept connections"
```

---

## 🔄 배포 되돌리기 (Rollback)

### 옵션 1: 이전 .env 복구
```bash
# 서버에서:
cd /home/azureuser/observer-deploy
cp .env.bak-20260123-123456 .env
docker compose restart observer
```

### 옵션 2: 이전 이미지 사용
```bash
# 이전 이미지 태그 확인
docker images | grep obs_deploy-observer

# 이전 버전으로 재배포 (로컬에서)
# 1. docker-compose.server.yml에서 이미지 태그 변경
# 2. .\infra\_shared\scripts\deploy\deploy.ps1 실행
```

### 옵션 3: 전체 롤백
```bash
# 서버 스택 중지
docker compose down

# 이전 .env 복구
cp .env.bak-20260123-123456 .env

# 새 이미지 없이 원래 이미지로 시작
docker compose up -d
```

---

## 📚 참고 문서

- **배포 스크립트**: `infra/_shared/scripts/deploy/README.md` (상세 설명)
- **워크플로우**: `.ai/workflows/deploy_automation.workflow.md`
- **서버 Compose**: `app/obs_deploy/docker-compose.server.yml`
- **환경 템플릿**: `app/obs_deploy/env.template`

---

## 🎯 다음 단계

1. **배포 실행**
   ```powershell
   .\infra\_shared\scripts\deploy\deploy.ps1 -ServerHost "your.server.ip"
   ```

2. **로그 확인**
   ```powershell
   Get-Content ops\run_records\deploy_*.log
   ```

3. **서버 검증**
   ```bash
   ssh azureuser@your.server.ip
   docker compose ps
   curl http://localhost:8000/health
   ```

4. **운영 모니터링**
   ```bash
   docker compose logs -f observer
   ```

---

**준비 완료! 🚀**
