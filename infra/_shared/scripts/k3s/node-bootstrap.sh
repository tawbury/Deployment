#!/bin/bash
# OCI ARM64 노드 초기화 스크립트
# 용도: 서버 재프로비저닝 시 한번 실행하여 전체 노드 설정 적용
#
# 사용법: sudo bash node-bootstrap.sh
# 전제: K3s가 이미 install.sh로 설치된 상태

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_TAG="node-bootstrap"
log() { logger -t "$LOG_TAG" "$1"; echo "[$(date +%Y-%m-%dT%H:%M:%S)] $1"; }

# root 권한 확인
if [ "$(id -u)" -ne 0 ]; then
  echo "오류: root 권한이 필요합니다. sudo bash $0 으로 실행하세요."
  exit 1
fi

log "=== OCI ARM64 노드 초기화 시작 ==="

# ─────────────────────────────────────────────
# 1. Swap 설정 (4GB)
# ─────────────────────────────────────────────
SWAPFILE="/swapfile"
SWAP_SIZE="4G"

if [ ! -f "$SWAPFILE" ]; then
  log "[1/5] Swap ${SWAP_SIZE} 생성 중..."
  fallocate -l "$SWAP_SIZE" "$SWAPFILE"
  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE"
  swapon "$SWAPFILE"

  # fstab에 영구 등록 (중복 방지)
  if ! grep -q "$SWAPFILE" /etc/fstab; then
    echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
  fi
  log "[1/5] Swap ${SWAP_SIZE} 설정 완료"
else
  swapon "$SWAPFILE" 2>/dev/null || true
  log "[1/5] Swap 이미 존재 (${SWAPFILE}), 활성화 확인"
fi

# ─────────────────────────────────────────────
# 2. sysctl 최적화
# ─────────────────────────────────────────────
log "[2/5] sysctl 설정 적용 중..."

SYSCTL_CONF="/etc/sysctl.d/99-k3s-optimize.conf"
cat > "$SYSCTL_CONF" << 'SYSCTL_EOF'
# K3s 노드 최적화 설정
# 메모리 overcommit: 기본 휴리스틱 (위험한 무제한 할당 방지)
vm.overcommit_memory=0
# Swap 최소 사용 (메모리 부족 시에만)
vm.swappiness=10
SYSCTL_EOF

sysctl --system > /dev/null 2>&1
log "[2/5] sysctl 설정 완료 (overcommit_memory=0, swappiness=10)"

# ─────────────────────────────────────────────
# 3. 불필요 서비스 비활성화
# ─────────────────────────────────────────────
log "[3/5] 불필요 서비스 비활성화 중..."

SERVICES_TO_DISABLE=(
  "rpcbind"      # NFS RPC (포트 111, 보안 위험)
  "iscsid"       # iSCSI (사용 안 함)
  "packagekit"   # PackageKit (자동 업데이트 불필요)
  "udisks2"      # USB/디스크 자동 마운트 (서버 불필요)
)

for svc in "${SERVICES_TO_DISABLE[@]}"; do
  if systemctl is-enabled "$svc" 2>/dev/null | grep -q "enabled"; then
    systemctl disable --now "$svc" 2>/dev/null
    log "  비활성화: $svc"
  else
    log "  이미 비활성화: $svc"
  fi
done

log "[3/5] 불필요 서비스 비활성화 완료"

# ─────────────────────────────────────────────
# 4. K3s config.yaml 배포
# ─────────────────────────────────────────────
log "[4/5] K3s config.yaml 배포 중..."

K3S_CONFIG_SRC="${SCRIPT_DIR}/config.yaml"
K3S_CONFIG_DST="/etc/rancher/k3s/config.yaml"

if [ -f "$K3S_CONFIG_SRC" ]; then
  mkdir -p "$(dirname "$K3S_CONFIG_DST")"
  cp "$K3S_CONFIG_SRC" "$K3S_CONFIG_DST"
  log "[4/5] K3s config.yaml 배포 완료 → ${K3S_CONFIG_DST}"
  log "  주의: K3s 재시작 필요 (systemctl restart k3s)"
else
  log "[4/5] 경고: ${K3S_CONFIG_SRC} 파일을 찾을 수 없음. 건너뜀."
fi

# ─────────────────────────────────────────────
# 5. 이미지 GC 스크립트 배포 + cron 등록
# ─────────────────────────────────────────────
log "[5/5] 이미지 GC 스크립트 배포 중..."

GC_SCRIPT_SRC="${SCRIPT_DIR}/k3s-image-gc.sh"
GC_SCRIPT_DST="/usr/local/bin/k3s-image-gc.sh"
GC_LOG="/var/log/k3s-image-gc.log"
CRON_ENTRY="0 4 * * * ${GC_SCRIPT_DST} >> ${GC_LOG} 2>&1"

if [ -f "$GC_SCRIPT_SRC" ]; then
  cp "$GC_SCRIPT_SRC" "$GC_SCRIPT_DST"
  chmod +x "$GC_SCRIPT_DST"

  # cron 등록 (중복 방지)
  if ! crontab -l 2>/dev/null | grep -qF "$GC_SCRIPT_DST"; then
    (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
    log "  cron 등록 완료: 매일 04:00 실행"
  else
    log "  cron 이미 등록됨"
  fi

  # 로그 파일 생성
  touch "$GC_LOG"

  log "[5/5] 이미지 GC 스크립트 배포 완료 → ${GC_SCRIPT_DST}"
else
  log "[5/5] 경고: ${GC_SCRIPT_SRC} 파일을 찾을 수 없음. 건너뜀."
fi

# ─────────────────────────────────────────────
# 요약
# ─────────────────────────────────────────────
log "=== 노드 초기화 완료 ==="
log "다음 단계:"
log "  1. K3s 재시작: systemctl restart k3s"
log "  2. ArgoCD 리소스 제한: ../../../argocd/apply-patches.sh 실행"
log "  3. 설정 검증: swapon --show, sysctl vm.overcommit_memory, sysctl vm.swappiness"
