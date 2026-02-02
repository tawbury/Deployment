#!/bin/bash
# ============================================
# k3s 서버 설치 스크립트
# ============================================
#
# 용도: k3s 클러스터의 첫 번째 서버 노드 설치
#
# 사용법:
#   ./install.sh                    # 기본 설치
#   ./install.sh --cluster-init     # HA 클러스터 첫 노드 (etcd 내장)
#
# 설치 후:
#   - kubeconfig: /etc/rancher/k3s/k3s.yaml
#   - kubectl 자동 설정됨
#   - 노드 토큰: /var/lib/rancher/k3s/server/node-token
#
# ============================================

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
    log_info "sudo $0 $*"
    exit 1
fi

# 옵션 파싱
CLUSTER_INIT=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-init)
            CLUSTER_INIT="--cluster-init"
            log_info "HA 클러스터 모드: 내장 etcd 사용"
            shift
            ;;
        *)
            log_error "알 수 없는 옵션: $1"
            exit 1
            ;;
    esac
done

log_info "k3s 서버 설치를 시작합니다..."

# k3s 설치
curl -sfL https://get.k3s.io | sh -s - server $CLUSTER_INIT

# 설치 확인
if ! command -v kubectl &> /dev/null; then
    log_error "k3s 설치에 실패했습니다."
    exit 1
fi

log_info "k3s 설치 완료!"
log_info ""
log_info "클러스터 상태:"
kubectl get nodes

log_info ""
log_info "노드 토큰 (워커 노드 추가 시 필요):"
cat /var/lib/rancher/k3s/server/node-token

log_info ""
log_info "kubeconfig 경로:"
echo "/etc/rancher/k3s/k3s.yaml"

log_info ""
log_info "로컬 머신에서 접근하려면:"
log_info "  scp root@$(hostname -I | awk '{print $1}'):/etc/rancher/k3s/k3s.yaml ~/.kube/config"
log_info "  sed -i 's/127.0.0.1/<서버IP>/g' ~/.kube/config"
