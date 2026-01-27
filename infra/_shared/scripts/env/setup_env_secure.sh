#!/bin/bash
# VM 서버에서 안전하게 .env 파일 생성하는 스크립트
# 사용법: ssh observer-vm 접속 후 이 명령어들을 복사해서 실행

set -e  # 에러 발생 시 중단

echo "=================================================="
echo "Observer .env 파일 안전 생성 스크립트"
echo "=================================================="
echo ""

# 1. 디렉토리 확인
cd ~/observer-deploy
echo "✓ 현재 위치: $(pwd)"

# 2. 기존 .env 파일 백업 (있다면)
if [ -f .env ]; then
    BACKUP_FILE=".env.backup.$(date +%Y%m%d_%H%M%S)"
    cp .env "$BACKUP_FILE"
    echo "✓ 기존 .env 백업: $BACKUP_FILE"
fi

# 3. KIS API 키 입력 받기
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "KIS API 키를 입력하세요 (복사 후 붙여넣기)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "KIS_APP_KEY: " KIS_APP_KEY
read -sp "KIS_APP_SECRET: " KIS_APP_SECRET
echo ""
read -p "KIS_IS_VIRTUAL (true/false): " KIS_IS_VIRTUAL

# 4. 검증
if [ -z "$KIS_APP_KEY" ] || [ -z "$KIS_APP_SECRET" ]; then
    echo "❌ 에러: API 키가 비어 있습니다!"
    exit 1
fi

# 5. .env 파일 생성
cat > .env << EOF
# KIS API 인증 정보 (자동 생성)
KIS_APP_KEY=$KIS_APP_KEY
KIS_APP_SECRET=$KIS_APP_SECRET
KIS_IS_VIRTUAL=$KIS_IS_VIRTUAL

# PostgreSQL 설정
DB_HOST=postgres
DB_USER=postgres
DB_PASSWORD=observer_db_pwd
DB_NAME=observer
DB_PORT=5432
EOF

echo "✓ .env 파일 생성 완료"

# 6. 권한 설정
chmod 600 .env
echo "✓ 파일 권한 설정: 600 (소유자만 읽기/쓰기)"

# 7. 확인
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "생성 완료! 확인:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ls -lh .env
echo ""

# 8. Docker Compose 재시작 제안
echo "다음 명령어로 컨테이너를 재시작하세요:"
echo ""
echo "  docker compose down"
echo "  docker compose up -d"
echo "  docker compose logs -f observer | grep 'Universe Scheduler'"
echo ""
echo "=================================================="
