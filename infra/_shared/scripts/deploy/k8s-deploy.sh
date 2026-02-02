#!/bin/bash
# ============================================
# k8s 배포 스크립트 (kustomize 기반)
# ============================================
#
# 용도: kustomize overlay를 사용하여 앱 배포
#
# 사용법:
#   ./k8s-deploy.sh staging                           # 스테이징 배포
#   ./k8s-deploy.sh production                        # 프로덕션 배포
#   ./k8s-deploy.sh production 20260202-143512        # YYYYMMDD-HHMMSS 태그로 배포
#   IMAGE_TAG=$(../build/generate_build_tag.sh) ./k8s-deploy.sh production  # 빌드 태그 자동
#   ./k8s-deploy.sh production --dry-run              # dry-run 모드
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 스크립트 디렉터리 기준으로 경로 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
K8S_DIR="${REPO_ROOT}/infra/k8s"

# 기본값
ENVIRONMENT="${1:-staging}"
IMAGE_TAG="${2:-}"
DRY_RUN=false
TIMEOUT="${TIMEOUT:-300s}"

# 옵션 파싱
shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        v*)
            IMAGE_TAG="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# 환경 유효성 검사
OVERLAY_PATH="${K8S_DIR}/overlays/${ENVIRONMENT}"
if [[ ! -d "$OVERLAY_PATH" ]]; then
    log_error "환경 '$ENVIRONMENT'을(를) 찾을 수 없습니다."
    log_info "사용 가능한 환경:"
    ls -1 "${K8S_DIR}/overlays/"
    exit 1
fi

log_info "========================================"
log_info "k8s 배포 시작"
log_info "========================================"
log_info "환경: ${ENVIRONMENT}"
log_info "Overlay 경로: ${OVERLAY_PATH}"

# 이미지 태그 업데이트
if [[ -n "$IMAGE_TAG" ]]; then
    log_step "이미지 태그 업데이트: ${IMAGE_TAG}"
    cd "$OVERLAY_PATH"
    kustomize edit set image "ghcr.io/tawbury/observer=ghcr.io/tawbury/observer:${IMAGE_TAG}"
    cd - > /dev/null
fi

# manifest 빌드 및 검증
log_step "manifest 빌드 및 검증..."
MANIFEST_FILE=$(mktemp)
kustomize build "$OVERLAY_PATH" > "$MANIFEST_FILE"
log_info "생성된 manifest: $(wc -l < "$MANIFEST_FILE") 라인"

# dry-run 모드
if [[ "$DRY_RUN" == true ]]; then
    log_warn "DRY-RUN 모드: 실제 배포하지 않습니다."
    log_info ""
    log_info "생성될 manifest:"
    cat "$MANIFEST_FILE"
    rm "$MANIFEST_FILE"
    exit 0
fi

# 배포 실행
log_step "배포 적용 중..."
kubectl apply -f "$MANIFEST_FILE"
rm "$MANIFEST_FILE"

# Namespace 확인
NAMESPACE=$(kustomize build "$OVERLAY_PATH" | grep -m1 "namespace:" | awk '{print $2}' || echo "observer")
log_info "Namespace: ${NAMESPACE}"

# 롤아웃 대기
log_step "롤아웃 대기 중... (timeout: ${TIMEOUT})"
if kubectl rollout status deployment/observer -n "${NAMESPACE}" --timeout="${TIMEOUT}"; then
    log_info "롤아웃 완료!"
else
    log_error "롤아웃 실패 또는 타임아웃"
    log_warn "상태 확인: kubectl get pods -n ${NAMESPACE}"
    log_warn "롤백: kubectl rollout undo deployment/observer -n ${NAMESPACE}"
    exit 1
fi

# 배포 결과 확인
log_info ""
log_info "========================================"
log_info "배포 완료!"
log_info "========================================"
log_info ""
log_info "리소스 상태:"
kubectl get pods,svc,deploy -n "${NAMESPACE}" -l app=observer

log_info ""
log_info "유용한 명령어:"
log_info "  로그: kubectl logs -f deployment/observer -n ${NAMESPACE}"
log_info "  상태: kubectl describe deployment/observer -n ${NAMESPACE}"
log_info "  롤백: kubectl rollout undo deployment/observer -n ${NAMESPACE}"
