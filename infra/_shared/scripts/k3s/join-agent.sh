#!/bin/bash
# ============================================
# k3s 워커 노드 추가 스크립트
# ============================================
#
# 용도: k3s 클러스터에 워커 노드 추가
#
# 사용법:
#   ./join-agent.sh <서버IP> <토큰>
#
# 예시:
#   ./join-agent.sh 192.168.1.100 K10abc123...
#
# 토큰 확인 (서버에서):
#   sudo cat /var/lib/rancher/k3s/server/node-token
#
# ============================================

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 인자 확인
if [[ $# -ne 2 ]]; then
    log_error "사용법: $0 <서버IP> <토큰>"
    log_info ""
    log_info "토큰 확인 방법 (서버에서 실행):"
    log_info "  sudo cat /var/lib/rancher/k3s/server/node-token"
    exit 1
fi

K3S_URL="https://$1:6443"
K3S_TOKEN="$2"

# 루트 권한 확인
if [[ $EUID -ne 0 ]]; then
    log_error "이 스크립트는 root 권한이 필요합니다."
    log_info "sudo $0 $*"
    exit 1
fi

log_info "k3s 워커 노드 설치를 시작합니다..."
log_info "서버 URL: $K3S_URL"

# k3s agent 설치
curl -sfL https://get.k3s.io | K3S_URL="$K3S_URL" K3S_TOKEN="$K3S_TOKEN" sh -

log_info "워커 노드 설치 완료!"
log_info ""
log_info "서버에서 노드 확인:"
log_info "  kubectl get nodes"
