#!/bin/bash
# K3s 미사용 컨테이너 이미지 자동 정리
# Pod에서 사용 중인 이미지 (repo:tag)를 보호하고 나머지 삭제
#
# 배포: node-bootstrap.sh가 /usr/local/bin/k3s-image-gc.sh로 복사
# Cron: 매일 04:00 KST 실행
#   0 4 * * * /usr/local/bin/k3s-image-gc.sh >> /var/log/k3s-image-gc.log 2>&1

set -euo pipefail
LOG_TAG="k3s-image-gc"
log() { logger -t "$LOG_TAG" "$1"; echo "$(date +%Y-%m-%dT%H:%M:%S) $1"; }

log "=== K3s 이미지 GC 시작 ==="

# 사용 중인 이미지 목록 (spec.containers[].image 기준, repo:tag 형식)
USED_REFS=$(k3s kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null | sort -u | grep -v '^$')

if [ -z "$USED_REFS" ]; then
  log "경고: 사용 중인 이미지 목록을 가져올 수 없음. 안전을 위해 중단."
  exit 1
fi

USED_COUNT=$(echo "$USED_REFS" | wc -l)
log "사용 중인 이미지: ${USED_COUNT}개"

# 전체 이미지에서 미사용 이미지만 삭제
DELETED=0
SKIPPED=0
TOTAL=0

while IFS= read -r line; do
  # crictl images 출력: IMAGE TAG IMAGE_ID SIZE
  REPO=$(echo "$line" | awk '{print $1}')
  TAG=$(echo "$line" | awk '{print $2}')
  IMG_ID=$(echo "$line" | awk '{print $3}')

  [ "$REPO" = "IMAGE" ] && continue  # 헤더 스킵
  [ -z "$REPO" ] && continue

  TOTAL=$((TOTAL + 1))
  REF="${REPO}:${TAG}"

  # 사용 중인 이미지인지 확인
  IS_USED=false
  while IFS= read -r used_ref; do
    # 정확한 매치 또는 docker.io prefix 보정
    if [ "$REF" = "$used_ref" ] || \
       [ "docker.io/$used_ref" = "$REF" ] || \
       [ "docker.io/library/$used_ref" = "$REF" ] || \
       [ "$REPO" = "$used_ref" ]; then
      IS_USED=true
      break
    fi
  done <<< "$USED_REFS"

  if [ "$IS_USED" = "false" ] && [ "$TAG" != "<none>" ]; then
    if k3s crictl rmi "$IMG_ID" 2>/dev/null; then
      log "삭제: $REF"
      DELETED=$((DELETED + 1))
    fi
  else
    SKIPPED=$((SKIPPED + 1))
  fi
done <<< "$(k3s crictl images 2>/dev/null)"

log "=== GC 완료: 전체 ${TOTAL}개, 삭제 ${DELETED}개, 보호 ${SKIPPED}개 ==="
