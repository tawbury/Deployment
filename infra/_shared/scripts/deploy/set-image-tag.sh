#!/bin/bash
# Overlay의 Observer 이미지 태그를 YYYYMMDD-HHMMSS 형식으로 설정
# 사용: ./set-image-tag.sh production [태그]
#   태그 생략 시 build/generate_build_tag.sh 로 생성
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
ENV="${1:-staging}"
TAG="${2:-}"
OVERLAY="${REPO_ROOT}/infra/k8s/overlays/${ENV}"
if [[ ! -d "$OVERLAY" ]]; then
  echo "Overlay not found: $OVERLAY"
  exit 1
fi
if [[ -z "$TAG" ]]; then
  TAG=$("${SCRIPT_DIR}/../build/generate_build_tag.sh")
fi
cd "$OVERLAY"
kustomize edit set image "ghcr.io/tawbury/observer=ghcr.io/tawbury/observer:${TAG}"
echo "Set ghcr.io/tawbury/observer:${TAG} in overlays/${ENV}"
