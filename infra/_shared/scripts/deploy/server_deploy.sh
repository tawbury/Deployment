#!/bin/bash
################################################################################
# Observer Deployment Server Runner (Linux/Bash)
# 용도: 서버에서 GHCR 이미지 배포/롤백, Compose 실행, 운영 체크
# 버전: v1.1.0
################################################################################

set -euo pipefail

# ============================================================================
# 설정 및 상수
# ============================================================================
DEPLOY_DIR="${1:-.}"
COMPOSE_FILE="${2:-docker-compose.server.yml}"
IMAGE_TAG_INPUT="${3:-}"
MODE="${4:-deploy}"
IMAGE_NAME="ghcr.io/tawbury/observer"
LAST_GOOD_FILE="$DEPLOY_DIR/runtime/state/last_good_tag"
BACKUP_DIR="$DEPLOY_DIR/backups/archives"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
HEALTH_ENDPOINT="http://localhost:8000/health"
MAX_RETRIES=5
RETRY_DELAY=3
IMAGE_TAG=""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# 함수: 로깅
# ============================================================================
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "[DEBUG] $1"
    fi
}

# ============================================================================
# 함수: 입력 검증
# ============================================================================
validate_inputs() {
    log_info "=== 입력 검증 시작 ==="
    
    # 배포 디렉토리 확인
    if [ ! -d "$DEPLOY_DIR" ]; then
        log_error "배포 디렉토리 없음: $DEPLOY_DIR"
        return 1
    fi
    
    log_debug "배포 디렉토리: $DEPLOY_DIR"
    
    # Compose 파일 확인
    if [ ! -f "$DEPLOY_DIR/$COMPOSE_FILE" ]; then
        log_error "Compose 파일 없음: $DEPLOY_DIR/$COMPOSE_FILE"
        return 1
    fi

    log_debug "Compose 파일: $COMPOSE_FILE"
    
    # .env 파일 확인
    if [ ! -f "$DEPLOY_DIR/.env" ]; then
        log_error ".env 파일 없음: $DEPLOY_DIR/.env"
        return 1
    fi

    log_debug ".env 파일 존재 확인됨"

    # 모드별 태그 확인
    if [ "$MODE" = "deploy" ] && [ -z "$IMAGE_TAG_INPUT" ]; then
        log_error "IMAGE_TAG 입력 필요 (예: 20260123-123456)"
        return 1
    fi
    if [ "$MODE" = "rollback" ] && [ ! -f "$LAST_GOOD_FILE" ]; then
        log_error "last_good_tag 없음: $LAST_GOOD_FILE"
        return 1
    fi
    
    log_info "✅ 입력 검증 완료"
    return 0
}

# ============================================================================
# 함수: 이미지 태그 결정 (deploy/rollback)
# ============================================================================
resolve_image_tag() {
    if [ "$MODE" = "rollback" ]; then
        IMAGE_TAG=$(cat "$LAST_GOOD_FILE" 2>/dev/null || true)
        if [ -z "$IMAGE_TAG" ]; then
            log_error "last_good_tag를 읽을 수 없습니다"
            return 1
        fi
        log_info "롤백 태그 사용: $IMAGE_TAG"
    else
        IMAGE_TAG="$IMAGE_TAG_INPUT"
        log_info "배포 태그 사용: $IMAGE_TAG"

    # ============================================================================
    # 함수: GHCR 인증 확인 및 자동 로그인
    # ============================================================================
    ensure_ghcr_auth() {
        log_info "=== GHCR 인증 확인 중 ==="
    
        # Docker config 확인
        if docker pull ghcr.io/tawbury/observer:latest --quiet >/dev/null 2>&1; then
            log_info "✅ GHCR 인증 이미 완료됨"
            return 0
        fi
    
        log_warn "⚠️  GHCR 인증 필요"
    
        # GHCR_TOKEN 환경변수 확인
        if [ -n "${GHCR_TOKEN:-}" ]; then
            log_info "🔐 GHCR_TOKEN 환경변수로 인증 시도..."
            if echo "$GHCR_TOKEN" | docker login ghcr.io -u tawbury --password-stdin >/dev/null 2>&1; then
                log_info "✅ GHCR 인증 성공"
                return 0
            else
                log_error "GHCR 인증 실패 (GHCR_TOKEN)"
                return 1
            fi
        fi
    
        # gh CLI 사용 가능 여부 확인
        if command -v gh >/dev/null 2>&1; then
            log_info "🔐 gh CLI로 인증 시도..."
            if gh auth token 2>/dev/null | docker login ghcr.io -u tawbury --password-stdin >/dev/null 2>&1; then
                log_info "✅ GHCR 인증 성공"
                return 0
            fi
        fi
    
        log_error "❌ GHCR 인증 실패"
        log_error "다음 중 하나를 수행하세요:"
        log_error "  1. GHCR_TOKEN 환경변수 설정: export GHCR_TOKEN=<your_token>"
        log_error "  2. 수동 로그인: echo <token> | docker login ghcr.io -u tawbury --password-stdin"
        return 1
    }
    fi
    return 0
}

# ============================================================================
# 함수: Docker 이미지 Pull
# ============================================================================
pull_docker_image() {
    log_info "=== Docker 이미지 Pull 중 ==="
    cd "$DEPLOY_DIR"
    local image_ref="${IMAGE_NAME}:${IMAGE_TAG}"
    if docker pull "$image_ref"; then
        log_info "✅ 이미지 Pull 완료: $image_ref"
        return 0
    else
        log_error "이미지 Pull 실패: $image_ref"
        return 1
    fi
}

# ============================================================================
# 함수: 필수 디렉토리 생성
# ============================================================================
create_required_directories() {
    log_info "=== 필수 디렉토리 생성 중 ==="
    
    cd "$DEPLOY_DIR"
    
    local required_dirs=(
        "data/observer"
        "data/postgres"
        "logs/system"
        "logs/maintenance"
        "config"
        "secrets"
        "runtime/state"
        "backups/archives"
    )
    
    for dir in "${required_dirs[@]}"; do
        if mkdir -p "$dir"; then
            log_debug "✓ $dir"
        else
            log_error "디렉토리 생성 실패: $dir"
            return 1
        fi
    done
    
    log_info "✅ 모든 필수 디렉토리 생성 완료"
    return 0
}

# ============================================================================
# 함수: Docker Compose 시작
# ============================================================================
start_compose_stack() {
    log_info "=== Docker Compose 스택 시작 중 ==="
    
    cd "$DEPLOY_DIR"
    
    log_debug "Compose 파일: $COMPOSE_FILE"
    
    if IMAGE_TAG="$IMAGE_TAG" docker compose -f "$COMPOSE_FILE" up -d --remove-orphans; then
        log_info "✅ Docker Compose 스택 시작 완료"
        log_info "⏳ PostgreSQL 헬스 체크 대기 중 (10초)..."
        sleep 10
        return 0
    else
        log_error "Docker Compose 시작 실패"
        return 1
    fi
}

# ============================================================================
# 함수: 컨테이너/호스트 시간 드리프트 확인
# ============================================================================
check_time_drift() {
    local service="observer"
    local max_drift=5

    log_info "=== 컨테이너-호스트 시간 드리프트 확인 ==="

    cd "$DEPLOY_DIR"

    if ! docker compose ps "$service" >/dev/null 2>&1; then
        log_warn "서비스($service)가 실행 중이 아니어서 시간 확인을 건너뜁니다."
        return 0
    fi

    local host_epoch
    host_epoch=$(date +%s)

    local container_epoch
    container_epoch=$(docker compose exec -T "$service" date +%s 2>/dev/null || true)

    if [[ -z "$container_epoch" ]]; then
        log_warn "컨테이너 시간 조회 실패 (서비스: $service)"
        return 0
    fi

    local drift
    drift=$(( host_epoch > container_epoch ? host_epoch - container_epoch : container_epoch - host_epoch ))

    log_info "  · Host epoch: $host_epoch"
    log_info "  · Container epoch: $container_epoch"
    log_info "  · Drift: ${drift}s"

    if [[ "$drift" -gt "$max_drift" ]]; then
        log_warn "⚠️  시간 드리프트가 ${max_drift}s 초과 (재시작/호스트 시계 확인 필요)"
    else
        log_info "✅ 시간 동기화 양호 (<= ${max_drift}s)"
    fi
}

# ============================================================================
# 함수: Docker Compose 상태 확인
# ============================================================================
check_compose_status() {
    log_info "=== Docker Compose 상태 확인 ==="
    
    cd "$DEPLOY_DIR"
    
    echo ""
    docker compose ps
    echo ""
    
    # 모든 서비스가 Up 상태인지 확인
    local down_count=$(docker compose ps --format "{{.Status}}" | grep -v "Up" | wc -l)
    
    if [ "$down_count" -gt 0 ]; then
        log_warn "⚠️  일부 서비스가 Up 상태가 아님 (다시 시작 중...)"
        docker compose restart
        sleep 5
        docker compose ps
    fi
    
    log_info "✅ Docker Compose 상태 확인 완료"
}

# ============================================================================
# 함수: 로그 확인 (초기 에러 감지)
# ============================================================================
check_initial_logs() {
    log_info "=== 초기 로그 확인 ==="
    
    cd "$DEPLOY_DIR"
    
    echo ""
    log_info "Observer 서비스 로그 (최근 100줄):"
    echo "─────────────────────────────────────────────────────────────────"
    docker compose logs --tail 100 observer || true
    echo "─────────────────────────────────────────────────────────────────"
    echo ""
    
    # 심각한 에러 감지 (선택적)
    if docker compose logs observer | grep -i "fatal\|critical error" > /dev/null 2>&1; then
        log_warn "⚠️  로그에서 심각한 에러 발견 (상세 로그 참조)"
    fi
    
    log_info "✅ 로그 확인 완료"
}

# ============================================================================
# 함수: Health Endpoint 확인
# ============================================================================
check_health_endpoint() {
    log_info "=== Health Endpoint 확인 ==="
    
    log_debug "대상: $HEALTH_ENDPOINT"
    
    local attempt=1
    while [ $attempt -le $MAX_RETRIES ]; do
        log_debug "시도 $attempt/$MAX_RETRIES..."
        
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_ENDPOINT" 2>/dev/null || echo "000")
        
        if [ "$http_code" = "200" ]; then
            log_info "✅ Health endpoint 응답: 200 OK"
            return 0
        else
            log_debug "응답 코드: $http_code (재시도 대기 중...)"
            sleep $RETRY_DELAY
            attempt=$((attempt + 1))
        fi
    done
    
    log_warn "⚠️  Health endpoint 응답 없음 (시작 지연 가능)"
    return 0  # 실패해도 계속 진행
}

# ============================================================================
# 함수: 이미지 백업 및 last_good_tag 갱신
# ============================================================================
save_image_tar() {
    log_info "=== 이미지 백업(TAR) 생성 ==="
    mkdir -p "$BACKUP_DIR"
    local image_ref="${IMAGE_NAME}:${IMAGE_TAG}"
    local tar_path="$BACKUP_DIR/observer-image_${IMAGE_TAG}.tar"
    if docker save "$image_ref" -o "$tar_path"; then
        log_info "✅ TAR 생성: $tar_path"
        return 0
    else
        log_warn "TAR 생성 실패 (무시)"
        return 0
    fi
}

prune_old_tars() {
    log_info "=== TAR 보관 (최근 3개 유지) ==="
    if ls "$BACKUP_DIR"/observer-image_*.tar >/dev/null 2>&1; then
        ls -1t "$BACKUP_DIR"/observer-image_*.tar | tail -n +4 | xargs -r rm -f
        log_info "✅ 불필요 TAR 정리 완료"
    else
        log_info "TAR 없음, 정리 스킵"
    fi
}

update_last_good_tag() {
    mkdir -p "$(dirname "$LAST_GOOD_FILE")"
    echo -n "$IMAGE_TAG" > "$LAST_GOOD_FILE"
    log_info "✅ last_good_tag 업데이트: $IMAGE_TAG"
}

# ============================================================================
# 함수: 최종 운영 체크
# ============================================================================
operational_summary() {
    log_info "=== 최종 운영 체크 ==="
    
    cd "$DEPLOY_DIR"
    
    echo ""
    log_info "📊 최종 상태:"
    echo "─────────────────────────────────────────────────────────────────"
    
    # 1. Compose 상태
    local total=$(docker compose ps --format "table" | tail -n +2 | wc -l)
    local running=$(docker compose ps --format "{{.Status}}" | grep "Up" | wc -l)
    log_info "  · Docker Compose: $running/$total 서비스 실행 중"
    
    # 2. 이미지 정보
    local image=$(docker compose ps --format "{{.Image}}" | head -1)
    if [ ! -z "$image" ]; then
        log_info "  · Observer 이미지: $image"
    fi
    
    # 3. 포트 확인
    if docker compose ps observer | grep -q "8000"; then
        log_info "  · API 포트: 8000 바인딩됨"
    fi
    
    # 4. 데이터 디렉토리
    if [ -d "data/observer" ]; then
        log_info "  · 데이터 디렉토리: 준비 완료"
    fi
    
    echo "─────────────────────────────────────────────────────────────────"
    echo ""
    
    log_info "✅ 운영 체크 완료"
}

# ============================================================================
# 메인 실행 흐름
# ============================================================================
main() {
    echo ""
    log_info "╔═════════════════════════════════════════════════════════════════════════════════╗"
    log_info "║        Observer Deployment Server Runner v1.0.0                                ║"
    log_info "╚═════════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    log_info "배포 설정:"
    log_info "  · 배포 디렉토리: $DEPLOY_DIR"
    log_info "  · Compose 파일: $COMPOSE_FILE"
    log_info "  · 모드: $MODE"
    log_info "  · 입력 태그: ${IMAGE_TAG_INPUT:-<none>}"
    echo ""
    
    # 1단계: 입력 검증
    if ! validate_inputs; then
        log_error "입력 검증 실패"
        return 1
    fi
    
    # 2단계: 태그 확정 및 이미지 Pull
    if ! resolve_image_tag; then
        log_error "이미지 태그 확인 실패"
    
            # GHCR 인증 확인
            if ! ensure_ghcr_auth; then
                log_error "GHCR 인증 실패"
                return 1
            fi
    
        return 1
    fi
    if ! pull_docker_image; then
        log_error "Docker 이미지 Pull 실패"
        return 1
    fi
    
    # 3단계: 필수 디렉토리 생성
    if ! create_required_directories; then
        log_error "필수 디렉토리 생성 실패"
        return 1
    fi
    
    # 4단계: Docker Compose 시작
    if ! start_compose_stack; then
        log_error "Docker Compose 스택 시작 실패"
        return 1
    fi

    # 4-1단계: 시간 드리프트 확인 (컨테이너 vs 호스트)
    check_time_drift || true
    
    # 5단계: 상태 확인
    check_compose_status || true
    
    # 6단계: 로그 확인
    check_initial_logs || true
    
    # 7단계: Health Endpoint 확인
    check_health_endpoint || true
    
    # 8단계: 최종 운영 체크
    operational_summary || true

    # 9단계: 백업 및 last_good_tag (deploy 모드만)
    if [ "$MODE" = "deploy" ]; then
        save_image_tar || true
        prune_old_tars || true
        update_last_good_tag || true
    fi
    
    # 완료
    echo ""
    log_info "╔═════════════════════════════════════════════════════════════════════════════════╗"
    log_info "║        배포 완료 ✅                                                              ║"
    log_info "╚═════════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    log_info "다음 단계:"
    log_info "  1. 서버 .env 확인: cat $DEPLOY_DIR/.env | grep -v '^$' | wc -l"
    log_info "  2. 로그 모니터링: docker compose logs -f observer"
    log_info "  3. Status 엔드포인트: curl http://localhost:8000/status"
    echo ""
    
    return 0
}

# ============================================================================
# 실행
# ============================================================================
if main; then
    exit 0
else
    exit 1
fi
