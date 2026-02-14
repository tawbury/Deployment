#!/bin/bash
# Helm Values 오버라이드 정합성 검증기
# ============================================================
# 1) 필수 키 존재 확인 (image.repository, image.tag, replicaCount)
# 2) 오버라이드 키가 base values.yaml에 존재하는지 검증
# 3) 이미지 태그 포맷 검증 (build-YYYYMMDD-HHMMSS)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
HELM_DIR="${REPO_ROOT}/infra/helm"

PASS=0
FAIL=0
WARN=0
ERRORS=""

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 필수 키 목록 (dot notation)
REQUIRED_KEYS=(
    "image.repository"
    "image.tag"
    "replicaCount"
)

# 이미지 태그 패턴
TAG_PATTERN='^build-20[0-9]{6}-[0-9]{6}$'

# ============================================================
# 인자 파싱
# ============================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --helm-dir)
                HELM_DIR="$2"
                shift 2
                ;;
            --help)
                echo "사용법: $(basename "$0") [옵션]"
                echo ""
                echo "옵션:"
                echo "  --helm-dir <path>  Helm 차트 루트 디렉토리 (기본: infra/helm)"
                exit 0
                ;;
            *)
                echo "[ERROR] 알 수 없는 인자: $1" >&2
                exit 2
                ;;
        esac
    done
}

# ============================================================
# 사전 조건 확인
# ============================================================
check_prerequisites() {
    # yq 또는 python3 필요
    if ! command -v yq &>/dev/null && ! command -v python3 &>/dev/null; then
        echo "[ERROR] yq 또는 python3이 설치되어 있지 않습니다." >&2
        exit 2
    fi

    if [[ ! -d "${HELM_DIR}" ]]; then
        echo "[ERROR] Helm 디렉토리가 존재하지 않습니다: ${HELM_DIR}" >&2
        exit 2
    fi
}

# ============================================================
# YAML에서 dot notation 키 값 추출
# ============================================================
extract_value() {
    local file="$1"
    local key="$2"

    # dot notation → yq 경로 변환 (image.tag → .image.tag)
    local yq_path=".${key}"

    if command -v yq &>/dev/null; then
        yq -r "${yq_path} // empty" "${file}" 2>/dev/null || echo ""
        return
    fi

    # python3 폴백
    python3 -c "
import yaml, sys
with open('${file}') as f:
    data = yaml.safe_load(f) or {}
keys = '${key}'.split('.')
val = data
for k in keys:
    if isinstance(val, dict) and k in val:
        val = val[k]
    else:
        sys.exit(0)
print(val)
" 2>/dev/null || echo ""
}

# ============================================================
# YAML에서 모든 leaf 키 추출 (dot notation)
# ============================================================
extract_all_keys() {
    local file="$1"

    if command -v yq &>/dev/null; then
        yq -r '.. | path | join(".")' "${file}" 2>/dev/null | grep -v '^\.$' | sort -u || true
        return
    fi

    # python3 폴백
    python3 -c "
import yaml, sys

def flatten_keys(data, prefix=''):
    if isinstance(data, dict):
        for k, v in data.items():
            full_key = f'{prefix}.{k}' if prefix else k
            flatten_keys(v, full_key)
    elif isinstance(data, list):
        for i, v in enumerate(data):
            full_key = f'{prefix}.{i}'
            flatten_keys(v, full_key)
    else:
        if prefix:
            print(prefix)

with open('${file}') as f:
    data = yaml.safe_load(f) or {}
flatten_keys(data)
" 2>/dev/null | sort -u || true
}

# ============================================================
# V1: 필수 키 존재 확인
# ============================================================
check_required_keys() {
    local values_file="$1"
    local chart_name="$2"

    for key in "${REQUIRED_KEYS[@]}"; do
        local value
        value="$(extract_value "${values_file}" "${key}")"
        if [[ -n "${value}" ]]; then
            echo -e "  ${GREEN}[PASS]${NC} ${key} = ${value}"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}[FAIL]${NC} ${key} - 필수 키 누락"
            FAIL=$((FAIL + 1))
            ERRORS="${ERRORS}\n  - ${chart_name}: ${key} 필수 키 누락"
        fi
    done
}

# ============================================================
# V2: 오버라이드 키 정합성 확인
# ============================================================
check_override_keys() {
    local base_file="$1"
    local env_file="$2"
    local chart_name="$3"
    local env_name="$4"

    # base와 env의 leaf 키 추출
    local base_keys_file
    base_keys_file="$(mktemp)"
    local env_keys_file
    env_keys_file="$(mktemp)"
    trap "rm -f ${base_keys_file} ${env_keys_file}" RETURN

    extract_all_keys "${base_file}" > "${base_keys_file}"
    extract_all_keys "${env_file}" > "${env_keys_file}"

    # env에만 존재하고 base에 없는 키 검출
    local orphan_count=0
    while IFS= read -r env_key; do
        [[ -z "${env_key}" ]] && continue
        # 숫자 인덱스를 포함한 키는 리스트 항목이므로 스킵
        [[ "${env_key}" =~ \.[0-9]+(\.|$) ]] && continue

        if ! grep -qF "${env_key}" "${base_keys_file}" 2>/dev/null; then
            echo -e "  ${YELLOW}[WARN]${NC} ${env_key} - values-${env_name}.yaml에만 존재 (오타 가능성)"
            WARN=$((WARN + 1))
            orphan_count=$((orphan_count + 1))
        fi
    done < "${env_keys_file}"

    if [[ ${orphan_count} -eq 0 ]]; then
        echo -e "  ${GREEN}[PASS]${NC} values-${env_name}.yaml 오버라이드 키 정합성"
        PASS=$((PASS + 1))
    fi
}

# ============================================================
# V3: 이미지 태그 포맷 검증
# ============================================================
check_image_tag_format() {
    local values_file="$1"
    local label="$2"

    local tag
    tag="$(extract_value "${values_file}" "image.tag")"

    if [[ -z "${tag}" ]]; then
        # image.tag가 없는 파일은 스킵 (환경 override에서 태그를 안 바꿀 수 있음)
        return 0
    fi

    if [[ "${tag}" =~ ${TAG_PATTERN} ]]; then
        echo -e "  ${GREEN}[PASS]${NC} image.tag 포맷: ${tag}"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} image.tag 포맷 불일치: ${tag} (기대: build-YYYYMMDD-HHMMSS)"
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  - ${label}: image.tag 포맷 불일치 (${tag})"
    fi
}

# ============================================================
# 메인 실행
# ============================================================
main() {
    parse_args "$@"
    check_prerequisites

    echo "=== Helm Values 오버라이드 검증 시작 ==="
    echo "Helm 디렉토리: ${HELM_DIR}"
    echo ""

    for chart_dir in "${HELM_DIR}"/*/; do
        local chart_name
        chart_name="$(basename "${chart_dir}")"
        local base_values="${chart_dir}/values.yaml"

        [[ ! -f "${base_values}" ]] && continue

        echo "--- ${chart_name} ---"

        # V1: 필수 키 확인
        echo "  [V1] 필수 키 확인:"
        check_required_keys "${base_values}" "${chart_name}"

        # V3: base values.yaml 이미지 태그 포맷
        echo "  [V3] 이미지 태그 포맷 (base):"
        check_image_tag_format "${base_values}" "${chart_name}/values.yaml"

        # V2 + V3: 환경별 values 대조
        for env in prod dev; do
            local env_values="${chart_dir}/values-${env}.yaml"
            [[ ! -f "${env_values}" ]] && continue

            echo "  [V2] 오버라이드 키 정합성 (${env}):"
            check_override_keys "${base_values}" "${env_values}" "${chart_name}" "${env}"

            echo "  [V3] 이미지 태그 포맷 (${env}):"
            check_image_tag_format "${env_values}" "${chart_name}/values-${env}.yaml"
        done

        echo ""
    done

    # 결과 요약
    echo "=== Helm Values 검증 결과 ==="
    echo "  PASS: ${PASS}"
    echo "  FAIL: ${FAIL}"
    echo "  WARN: ${WARN}"

    if [[ ${FAIL} -gt 0 ]]; then
        echo ""
        echo "실패 항목:"
        echo -e "${ERRORS}"
        exit 1
    fi

    if [[ ${WARN} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}경고가 있지만 검증은 통과했습니다.${NC}"
    fi

    echo ""
    echo "모든 Values 검증 통과!"
}

main "$@"
