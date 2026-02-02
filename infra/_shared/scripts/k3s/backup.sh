#!/bin/bash
# ============================================
# k3s 백업 스크립트
# ============================================
#
# 용도: k3s 클러스터 상태 백업 (etcd 스냅샷)
#
# 사용법:
#   ./backup.sh                    # 기본 백업 (로컬)
#   ./backup.sh --s3               # S3 백업 (환경변수 필요)
#
# 복원:
#   k3s server --cluster-reset --cluster-reset-restore-path=/path/to/snapshot
#
# ============================================

set -euo pipefail

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# 루트 권한 확인
if [[ $EUID -ne 0 ]]; then
    log_error "이 스크립트는 root 권한이 필요합니다."
    exit 1
fi

# 백업 디렉터리
BACKUP_DIR="${BACKUP_DIR:-/var/lib/rancher/k3s/server/db/snapshots}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SNAPSHOT_NAME="k3s-snapshot-${TIMESTAMP}"

# 옵션 파싱
USE_S3=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --s3)
            USE_S3=true
            shift
            ;;
        *)
            log_error "알 수 없는 옵션: $1"
            exit 1
            ;;
    esac
done

log_info "k3s 백업을 시작합니다..."
log_info "스냅샷 이름: ${SNAPSHOT_NAME}"

if [[ "$USE_S3" == true ]]; then
    # S3 백업 (환경변수 필요)
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        log_error "S3 백업을 위해 AWS 환경변수가 필요합니다:"
        log_info "  export AWS_ACCESS_KEY_ID=..."
        log_info "  export AWS_SECRET_ACCESS_KEY=..."
        log_info "  export S3_BUCKET=..."
        log_info "  export S3_ENDPOINT=..."
        exit 1
    fi

    k3s etcd-snapshot save \
        --name "${SNAPSHOT_NAME}" \
        --s3 \
        --s3-bucket "${S3_BUCKET}" \
        --s3-endpoint "${S3_ENDPOINT:-s3.amazonaws.com}" \
        --s3-region "${S3_REGION:-us-east-1}"

    log_info "S3 백업 완료: s3://${S3_BUCKET}/${SNAPSHOT_NAME}"
else
    # 로컬 백업
    k3s etcd-snapshot save --name "${SNAPSHOT_NAME}"

    log_info "로컬 백업 완료: ${BACKUP_DIR}/${SNAPSHOT_NAME}"
fi

# 스냅샷 목록 표시
log_info ""
log_info "저장된 스냅샷 목록:"
k3s etcd-snapshot ls

log_info ""
log_info "복원 방법:"
log_info "  sudo systemctl stop k3s"
log_info "  sudo k3s server --cluster-reset --cluster-reset-restore-path=${BACKUP_DIR}/${SNAPSHOT_NAME}"
log_info "  sudo systemctl start k3s"
