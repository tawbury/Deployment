#!/bin/bash
# Helm Template 렌더링 + 매니페스트 검증 스크립트
# ============================================================
# helm template으로 매니페스트를 생성한 후
# kubeconform (있으면) 또는 kubectl --dry-run=client로 검증
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
HELM_DIR="${REPO_ROOT}/infra/helm"

PASS=0
FAIL=0
ERRORS=""
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "=== Helm Template 렌더링 + 매니페스트 검증 ==="
echo "Helm 디렉토리: ${HELM_DIR}"
echo "임시 디렉토리: ${TMPDIR}"
echo ""

# Helm 설치 확인
if ! command -v helm &>/dev/null; then
  echo "[ERROR] helm이 설치되어 있지 않습니다."
  exit 1
fi

# 검증 도구 결정
VALIDATOR=""
if command -v kubeconform &>/dev/null; then
  VALIDATOR="kubeconform"
  echo "[INFO] kubeconform으로 검증합니다."
elif command -v kubectl &>/dev/null; then
  VALIDATOR="kubectl"
  echo "[INFO] kubectl --dry-run=client로 검증합니다."
else
  VALIDATOR="none"
  echo "[WARN] kubeconform, kubectl 모두 없음 - 렌더링만 검증합니다."
fi
echo ""

validate_manifest() {
  local manifest_file="$1"
  local label="$2"

  case "${VALIDATOR}" in
    kubeconform)
      if kubeconform -strict -summary "${manifest_file}" 2>/dev/null; then
        return 0
      else
        return 1
      fi
      ;;
    kubectl)
      if kubectl apply --dry-run=client -f "${manifest_file}" 2>/dev/null; then
        return 0
      else
        return 1
      fi
      ;;
    none)
      # 렌더링 성공 자체가 검증
      return 0
      ;;
  esac
}

# 모든 차트 디렉토리 순회
for chart_dir in "${HELM_DIR}"/*/; do
  chart_name="$(basename "${chart_dir}")"

  # Chart.yaml 존재 확인
  if [[ ! -f "${chart_dir}/Chart.yaml" ]]; then
    echo "[SKIP] ${chart_name}: Chart.yaml 없음"
    continue
  fi

  echo "--- ${chart_name} ---"

  # 환경별 values 파일 조합 검증
  for env in "prod" "dev"; do
    env_values="${chart_dir}/values-${env}.yaml"
    if [[ ! -f "${env_values}" ]]; then
      continue
    fi

    output_file="${TMPDIR}/${chart_name}-${env}.yaml"
    echo -n "  [template] values.yaml + values-${env}.yaml ... "

    # helm template 렌더링
    if helm template "${chart_name}" "${chart_dir}" \
      -f "${chart_dir}/values.yaml" \
      -f "${env_values}" \
      > "${output_file}" 2>/dev/null; then
      echo "OK"
    else
      echo "FAIL (렌더링 실패)"
      ((FAIL++))
      ERRORS="${ERRORS}\n  - ${chart_name} (${env}): helm template 렌더링 실패"
      continue
    fi

    # 매니페스트 검증
    echo -n "  [validate] ${chart_name}-${env} (${VALIDATOR}) ... "
    if validate_manifest "${output_file}" "${chart_name}-${env}"; then
      echo "PASS"
      ((PASS++))
    else
      echo "FAIL"
      ((FAIL++))
      ERRORS="${ERRORS}\n  - ${chart_name} (${env}): 매니페스트 검증 실패"
    fi
  done

  echo ""
done

# 결과 요약
echo "=== 매니페스트 검증 결과 ==="
echo "  검증 도구: ${VALIDATOR}"
echo "  PASS: ${PASS}"
echo "  FAIL: ${FAIL}"

if [[ ${FAIL} -gt 0 ]]; then
  echo ""
  echo "실패 항목:"
  echo -e "${ERRORS}"
  exit 1
fi

echo ""
echo "모든 매니페스트 검증 통과!"
