#!/bin/bash
# ============================================
# k8s 롤백 스크립트
# ============================================
#
# 용도: Deployment 롤백
#
# 사용법:
#   ./rollback.sh staging                 # 이전 버전으로 롤백
#   ./rollback.sh production              # 이전 버전으로 롤백
#   ./rollback.sh production 2           # 특정 revision으로 롤백
#   ./rollback.sh production --history   # 히스토리만 확인
#
# ============================================

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 기본값
ENVIRONMENT="${1:-staging}"
REVISION="${2:-}"
DEPLOYMENT="${DEPLOYMENT:-app}"
SHOW_HISTORY_ONLY=false

# 옵션 파싱
shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --history)
            SHOW_HISTORY_ONLY=true
            shift
            ;;
        [0-9]*)
            REVISION="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Namespace 매핑
case $ENVIRONMENT in
    staging)
        NAMESPACE="prj-01-staging"
        ;;
    production)
        NAMESPACE="prj-01-prod"
        ;;
    *)
        NAMESPACE="prj-01"
        ;;
esac

log_info "환경: ${ENVIRONMENT}"
log_info "Namespace: ${NAMESPACE}"
log_info "Deployment: ${DEPLOYMENT}"
log_info ""

# 히스토리 표시
log_info "롤아웃 히스토리:"
kubectl rollout history deployment/${DEPLOYMENT} -n "${NAMESPACE}"

if [[ "$SHOW_HISTORY_ONLY" == true ]]; then
    exit 0
fi

log_info ""

# 롤백 실행
if [[ -n "$REVISION" ]]; then
    log_warn "Revision ${REVISION}으로 롤백합니다..."
    read -p "계속하시겠습니까? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "롤백 취소됨"
        exit 0
    fi

    kubectl rollout undo deployment/${DEPLOYMENT} -n "${NAMESPACE}" --to-revision="${REVISION}"
else
    log_warn "이전 버전으로 롤백합니다..."
    read -p "계속하시겠습니까? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "롤백 취소됨"
        exit 0
    fi

    kubectl rollout undo deployment/${DEPLOYMENT} -n "${NAMESPACE}"
fi

# 롤아웃 대기
log_info "롤백 진행 중..."
kubectl rollout status deployment/${DEPLOYMENT} -n "${NAMESPACE}" --timeout=120s

log_info ""
log_info "롤백 완료!"
log_info ""
log_info "현재 상태:"
kubectl get pods -n "${NAMESPACE}" -l app=${DEPLOYMENT}
