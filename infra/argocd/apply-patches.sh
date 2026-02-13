#!/bin/bash
# ArgoCD 리소스 제한 일괄 적용 스크립트
# 용도: ArgoCD 설치/업그레이드 후 리소스 제한 재적용
#
# 사용법: bash apply-patches.sh
# 전제: kubectl이 설정되어 있고, argocd 네임스페이스 존재

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KUBECTL="k3s kubectl"

log() { echo "[$(date +%Y-%m-%dT%H:%M:%S)] $1"; }

log "=== ArgoCD 리소스 제한 패치 시작 ==="

# argocd 네임스페이스 확인
if ! $KUBECTL get namespace argocd > /dev/null 2>&1; then
  log "오류: argocd 네임스페이스가 존재하지 않습니다."
  exit 1
fi

# 컴포넌트별 패치 적용
declare -A PATCHES=(
  ["statefulset/argocd-application-controller"]='{"spec":{"template":{"spec":{"containers":[{"name":"argocd-application-controller","resources":{"limits":{"memory":"512Mi","cpu":"500m"},"requests":{"memory":"256Mi","cpu":"100m"}}}]}}}}'
  ["deployment/argocd-repo-server"]='{"spec":{"template":{"spec":{"containers":[{"name":"argocd-repo-server","resources":{"limits":{"memory":"256Mi","cpu":"500m"},"requests":{"memory":"128Mi","cpu":"100m"}}}]}}}}'
  ["deployment/argocd-server"]='{"spec":{"template":{"spec":{"containers":[{"name":"argocd-server","resources":{"limits":{"memory":"256Mi","cpu":"500m"},"requests":{"memory":"128Mi","cpu":"100m"}}}]}}}}'
  ["deployment/argocd-dex-server"]='{"spec":{"template":{"spec":{"containers":[{"name":"dex","resources":{"limits":{"memory":"256Mi","cpu":"250m"},"requests":{"memory":"64Mi","cpu":"50m"}}}]}}}}'
  ["deployment/argocd-applicationset-controller"]='{"spec":{"template":{"spec":{"containers":[{"name":"argocd-applicationset-controller","resources":{"limits":{"memory":"256Mi","cpu":"250m"},"requests":{"memory":"64Mi","cpu":"50m"}}}]}}}}'
  ["deployment/argocd-notifications-controller"]='{"spec":{"template":{"spec":{"containers":[{"name":"argocd-notifications-controller","resources":{"limits":{"memory":"128Mi","cpu":"100m"},"requests":{"memory":"64Mi","cpu":"50m"}}}]}}}}'
  ["deployment/argocd-redis"]='{"spec":{"template":{"spec":{"containers":[{"name":"redis","resources":{"limits":{"memory":"128Mi","cpu":"100m"},"requests":{"memory":"64Mi","cpu":"50m"}}}]}}}}'
)

SUCCESS=0
FAIL=0

for resource in "${!PATCHES[@]}"; do
  if $KUBECTL patch "$resource" -n argocd -p "${PATCHES[$resource]}" --type=strategic 2>/dev/null; then
    log "  적용 완료: $resource"
    SUCCESS=$((SUCCESS + 1))
  else
    log "  적용 실패: $resource"
    FAIL=$((FAIL + 1))
  fi
done

log "=== 패치 완료: 성공 ${SUCCESS}개, 실패 ${FAIL}개 ==="

# 결과 검증
log "현재 리소스 제한:"
$KUBECTL get deploy,statefulset -n argocd \
  -o jsonpath='{range .items[*]}  {.kind}/{.metadata.name}: mem={.spec.template.spec.containers[0].resources.limits.memory} cpu={.spec.template.spec.containers[0].resources.limits.cpu}{"\n"}{end}'
