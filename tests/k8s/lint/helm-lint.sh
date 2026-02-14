#!/bin/bash
# Helm Lint 자동화 스크립트
# ============================================================
# 모든 Helm 차트에 대해 lint를 실행하여 문법/구조 오류 검증
# values.yaml + values-prod.yaml 조합으로 프로덕션 설정 검증
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
HELM_DIR="${REPO_ROOT}/infra/helm"

PASS=0
FAIL=0
ERRORS=""

echo "=== Helm Lint 검증 시작 ==="
echo "Helm 디렉토리: ${HELM_DIR}"
echo ""

# Helm 설치 확인
if ! command -v helm &>/dev/null; then
  echo "[ERROR] helm이 설치되어 있지 않습니다."
  exit 1
fi

# 모든 차트 디렉토리 순회
for chart_dir in "${HELM_DIR}"/*/; do
  chart_name="$(basename "${chart_dir}")"

  # Chart.yaml 존재 확인
  if [[ ! -f "${chart_dir}/Chart.yaml" ]]; then
    echo "[SKIP] ${chart_name}: Chart.yaml 없음"
    continue
  fi

  echo "--- ${chart_name} ---"

  # 1) 기본 values.yaml로 lint
  if [[ -f "${chart_dir}/values.yaml" ]]; then
    echo -n "  [lint] values.yaml ... "
    if helm lint "${chart_dir}" -f "${chart_dir}/values.yaml" --quiet 2>/dev/null; then
      echo "PASS"
      ((PASS++))
    else
      echo "FAIL"
      ((FAIL++))
      ERRORS="${ERRORS}\n  - ${chart_name}: values.yaml lint 실패"
    fi
  fi

  # 2) values.yaml + values-prod.yaml 조합으로 lint (프로덕션 검증)
  if [[ -f "${chart_dir}/values-prod.yaml" ]]; then
    echo -n "  [lint] values.yaml + values-prod.yaml ... "
    if helm lint "${chart_dir}" -f "${chart_dir}/values.yaml" -f "${chart_dir}/values-prod.yaml" --quiet 2>/dev/null; then
      echo "PASS"
      ((PASS++))
    else
      echo "FAIL"
      ((FAIL++))
      ERRORS="${ERRORS}\n  - ${chart_name}: values-prod.yaml lint 실패"
    fi
  fi

  # 3) values.yaml + values-dev.yaml 조합으로 lint (개발 검증)
  if [[ -f "${chart_dir}/values-dev.yaml" ]]; then
    echo -n "  [lint] values.yaml + values-dev.yaml ... "
    if helm lint "${chart_dir}" -f "${chart_dir}/values.yaml" -f "${chart_dir}/values-dev.yaml" --quiet 2>/dev/null; then
      echo "PASS"
      ((PASS++))
    else
      echo "FAIL"
      ((FAIL++))
      ERRORS="${ERRORS}\n  - ${chart_name}: values-dev.yaml lint 실패"
    fi
  fi

  echo ""
done

# 결과 요약
echo "=== Helm Lint 결과 ==="
echo "  PASS: ${PASS}"
echo "  FAIL: ${FAIL}"

if [[ ${FAIL} -gt 0 ]]; then
  echo ""
  echo "실패 항목:"
  echo -e "${ERRORS}"
  exit 1
fi

echo ""
echo "모든 차트 lint 통과!"
