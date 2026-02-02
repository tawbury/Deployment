#!/bin/bash
# ============================================
# k8s 헬스체크 스크립트
# ============================================
#
# 용도: 클러스터 및 앱 상태 확인
#
# 사용법:
#   ./check_health.sh                    # 전체 상태 확인
#   ./check_health.sh staging            # 특정 환경만 확인
#   ./check_health.sh --pods-only        # Pod 상태만 확인
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

log_section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# 기본값
ENVIRONMENT="${1:-}"
PODS_ONLY=false

# 옵션 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --pods-only)
            PODS_ONLY=true
            shift
            ;;
        staging|production)
            ENVIRONMENT="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Namespace 결정
if [[ -n "$ENVIRONMENT" ]]; then
    case $ENVIRONMENT in
        staging)
            NAMESPACES=("prj-01-staging")
            ;;
        production)
            NAMESPACES=("prj-01-prod")
            ;;
        *)
            NAMESPACES=("prj-01")
            ;;
    esac
else
    NAMESPACES=("prj-01" "prj-01-staging" "prj-01-prod")
fi

# 클러스터 전체 상태 (pods-only가 아닐 때)
if [[ "$PODS_ONLY" == false ]]; then
    log_section "클러스터 노드 상태"
    kubectl get nodes -o wide

    log_section "시스템 Pod 상태"
    kubectl get pods -n kube-system

    log_section "전체 리소스 사용량"
    if kubectl top nodes 2>/dev/null; then
        echo ""
    else
        log_warn "metrics-server가 설치되지 않았습니다."
    fi
fi

# 각 Namespace별 상태
for NS in "${NAMESPACES[@]}"; do
    # Namespace 존재 여부 확인
    if ! kubectl get namespace "$NS" &>/dev/null; then
        log_warn "Namespace '$NS'가 존재하지 않습니다. 건너뜁니다."
        continue
    fi

    log_section "Namespace: $NS"

    # Pod 상태
    echo "📦 Pods:"
    kubectl get pods -n "$NS" -o wide 2>/dev/null || echo "  (없음)"

    if [[ "$PODS_ONLY" == false ]]; then
        echo ""
        echo "🔗 Services:"
        kubectl get svc -n "$NS" 2>/dev/null || echo "  (없음)"

        echo ""
        echo "📊 Deployments:"
        kubectl get deploy -n "$NS" 2>/dev/null || echo "  (없음)"

        echo ""
        echo "🌐 Ingress:"
        kubectl get ingress -n "$NS" 2>/dev/null || echo "  (없음)"

        # 최근 이벤트
        echo ""
        echo "📝 최근 이벤트 (Warning):"
        kubectl get events -n "$NS" --field-selector type=Warning --sort-by='.lastTimestamp' 2>/dev/null | tail -5 || echo "  (없음)"
    fi
done

# 문제 있는 Pod 확인
log_section "문제 있는 Pod 확인"

# CrashLoopBackOff, Error, Pending 상태 Pod 찾기
PROBLEM_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | grep -v "^NAMESPACE" || true)

if [[ -n "$PROBLEM_PODS" ]]; then
    log_warn "문제 있는 Pod 발견:"
    echo "$PROBLEM_PODS"
else
    log_info "모든 Pod가 정상 상태입니다."
fi

log_info ""
log_info "헬스체크 완료!"
