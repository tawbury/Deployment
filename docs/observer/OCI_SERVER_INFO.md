# OCI 서버 배포 정보

## 서버 정보

### Oracle Cloud Infrastructure (OCI)
- **호스트명**: oracle-obs-vm-01
- **IP 주소**: 134.185.117.22
- **사용자**: ubuntu
- **SSH 키**: `C:\Users\tawbu\.ssh\oracle-obs-vm-01.key`
- **아키텍처**: ARM64 (linux/arm64/v8)
- **배포 디렉토리**: /home/ubuntu/observer-deploy

### SSH 접속

```bash
ssh -i "C:\Users\tawbu\.ssh\oracle-obs-vm-01.key" ubuntu@134.185.117.22
```

또는 SSH config 사용:

```bash
ssh oracle-obs-vm-01
```

## 배포 환경

### Docker 설정
- Docker Engine: 설치됨
- Docker Compose: 설치됨
- GHCR 인증: 필요

### 디렉토리 구조

```
/home/ubuntu/observer-deploy/
├── .env                                    # 환경변수 (KIS_APP_KEY, KIS_APP_SECRET)
├── docker-compose.server.yml               # Compose 설정
├── server_deploy.sh                        # 배포 스크립트
├── data/                                   # 영구 데이터
│   ├── observer/                           # Observer 데이터
│   └── postgres/                           # PostgreSQL 데이터
├── logs/                                   # 로그
│   ├── system/                             # 시스템 로그
│   └── maintenance/                        # 유지보수 로그
├── runtime/
│   └── state/
│       └── last_good_tag                   # 마지막 성공 배포 태그
└── backups/
    └── archives/                           # 이미지 백업 (TAR)
```

## 현재 배포 상태

### 마지막 배포 정보
- **배포 일시**: 2026-01-27 00:13:27 KST
- **이미지 태그**: 20260127-000738
- **이미지**: ghcr.io/tawbury/observer:20260127-000738
- **플랫폼**: linux/arm64

### 실행 중인 컨테이너

```bash
# 컨테이너 확인
docker ps

# 컨테이너 목록:
# - observer (ghcr.io/tawbury/observer:20260127-000738)
# - observer-postgres (postgres:15-alpine)
```

### Health Check

```bash
# Health Endpoint
curl http://localhost:8000/health

# Status Endpoint
curl http://localhost:8000/status | python3 -m json.tool
```

## GHCR 인증

### 수동 인증 (필요 시)

```bash
# GitHub Personal Access Token 사용
echo <YOUR_GITHUB_TOKEN> | docker login ghcr.io -u tawbury --password-stdin
```

### 환경변수 사용 (권장)

```bash
# .bashrc 또는 .profile에 추가
export GHCR_TOKEN=<YOUR_GITHUB_TOKEN>

# server_deploy.sh가 자동으로 사용
```

### Token 권한 요구사항
- `read:packages`
- `write:packages` (푸시 시 필요)

## 배포 명령어

### 로컬에서 OCI 배포 (PowerShell, 프로젝트 루트 기준)

1. **이미지 태그 생성** (현재 시각 기준, 재사용하지 않음)
   ```powershell
   $tag = .\infra\_shared\scripts\build\generate_build_tag.ps1 | Select-Object -Last 1
   ```
2. **배포 실행** (deploy.ps1 기본값이 OCI·app/observer 경로로 설정됨)
   ```powershell
   .\infra\_shared\scripts\deploy\deploy.ps1 -ImageTag $tag
   ```
   - 필요 시: `-LocalEnvFile "app\observer\.env"`, `-ArtifactDir "app\observer\docker\compose"` 등은 이미 기본값으로 지정됨.
3. **배포 성공 시 이 문서 갱신**  
   "현재 배포 상태" 아래 **마지막 배포 정보**를 다음처럼 수정:
   - **배포 일시**: 실제 배포 완료 시각 (예: 2026-01-27 22:51:30 KST)
   - **이미지 태그**: 위에서 사용한 `$tag` 값 (예: 20260127-225130)
   - **이미지**: `ghcr.io/tawbury/observer:<위_태그>`
   - **실행 중인 컨테이너** 예시의 이미지 태그를 동일하게 변경
   - **최종 업데이트**: 문서 수정한 날짜

### 서버에서 새 이미지 배포

```bash
# GHCR_TOKEN 환경변수가 설정되어 있으면 자동 인증
export GHCR_TOKEN=<your_token>

# 배포 실행
cd /home/ubuntu/observer-deploy
bash server_deploy.sh . docker-compose.server.yml 20260127-123456 deploy
```

### 롤백

```bash
cd /home/ubuntu/observer-deploy
bash server_deploy.sh . docker-compose.server.yml "" rollback
```

## 주의사항

### ARM64 아키텍처
- 이 서버는 **ARM64** 아키텍처입니다
- Docker 이미지는 반드시 **multi-platform** (amd64, arm64) 빌드 필요
- GitHub Actions에서 자동으로 multi-platform 빌드 수행

### 포트 노출
- **8000**: Observer API (HTTP)
- **5432**: PostgreSQL (DB)

### 환경 변수
`.env` 파일에 다음 변수 필요:
- `KIS_APP_KEY`: 한국투자증권 API 키
- `KIS_APP_SECRET`: 한국투자증권 API 시크릿
- `KIS_IS_VIRTUAL`: 모의투자 여부 (true/false)

## 트러블슈팅

### GHCR Pull 실패 (denied)
```bash
# 해결: GHCR 인증 확인
docker login ghcr.io -u tawbury
```

### ARM64 호환 이미지 없음 (no matching manifest)
```bash
# 해결: Multi-platform 이미지 빌드 필요
# GitHub Actions가 자동으로 amd64, arm64 빌드
```

### 컨테이너 재시작 반복
```bash
# 로그 확인
docker logs observer

# 일반적 원인: .env 파일 누락 또는 잘못된 환경변수
```

---

**최종 업데이트**: 2026-01-27  
**작성자**: Deployment Automation Team
