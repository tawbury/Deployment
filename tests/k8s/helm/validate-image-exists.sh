#!/bin/bash
# GHCR 이미지 존재 검증기
# ============================================================
# Helm 차트의 values.yaml에서 이미지 repo+tag를 추출하고
# GHCR API를 통해 해당 이미지가 실제로 존재하는지 확인
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
HELM_DIR="${REPO_ROOT}/infra/helm"
TOKEN="${GITHUB_TOKEN:-}"

PASS=0
FAIL=0
SKIP=0
ERRORS=""

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

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
            --token)
                TOKEN="$2"
                shift 2
                ;;
            --help)
                echo "사용법: $(basename "$0") [옵션]"
                echo ""
                echo "옵션:"
                echo "  --helm-dir <path>  Helm 차트 루트 디렉토리 (기본: infra/helm)"
                echo "  --token <token>    GHCR API 인증 토큰 (기본: \$GITHUB_TOKEN)"
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
    if ! command -v curl &>/dev/null; then
        echo "[ERROR] curl이 설치되어 있지 않습니다." >&2
        exit 2
    fi

    if [[ -z "${TOKEN}" ]]; then
        echo "[ERROR] GITHUB_TOKEN이 설정되지 않았습니다." >&2
        echo "  export GITHUB_TOKEN=<your-token> 또는 --token <token> 사용" >&2
        exit 2
    fi

    if [[ ! -d "${HELM_DIR}" ]]; then
        echo "[ERROR] Helm 디렉토리가 존재하지 않습니다: ${HELM_DIR}" >&2
        exit 2
    fi
}

# ============================================================
# YAML에서 값 추출
# ============================================================
extract_value() {
    local file="$1"
    local key="$2"
    local yq_path=".${key}"

    if command -v yq &>/dev/null; then
        yq -r "${yq_path} // empty" "${file}" 2>/dev/null || echo ""
        return
    fi

    # python3 폴백
    if command -v python3 &>/dev/null; then
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
        return
    fi

    # grep 기반 간이 파싱 (최후 수단)
    # image.repository → "repository:" 줄에서 값 추출
    local last_key="${key##*.}"
    grep -E "^\s+${last_key}:" "${file}" 2>/dev/null | head -1 | awk '{print $2}' || echo ""
}

# ============================================================
# GHCR 이미지 존재 확인
# ============================================================
check_image_exists() {
    local repo_path="$1"   # tawbury/observer
    local tag="$2"
    local token="$3"

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${token}" \
        "https://ghcr.io/v2/${repo_path}/manifests/${tag}" \
        --connect-timeout 10 \
        --max-time 30 \
        2>/dev/null) || status="000"

    case "${status}" in
        200)
            return 0
            ;;
        401)
            echo -e "  ${RED}[ERROR] 인증 실패 (401) - 토큰을 확인하세요${NC}" >&2
            return 1
            ;;
        429)
            # 레이트 리밋: 1회 재시도 (3초 대기)
            echo -e "  ${YELLOW}[WARN] 레이트 리밋 (429) - 3초 대기 후 재시도${NC}" >&2
            sleep 3
            status=$(curl -s -o /dev/null -w "%{http_code}" \
                -H "Authorization: Bearer ${token}" \
                "https://ghcr.io/v2/${repo_path}/manifests/${tag}" \
                --connect-timeout 10 \
                --max-time 30 \
                2>/dev/null) || status="000"
            [[ "${status}" == "200" ]]
            return $?
            ;;
        404)
            return 1
            ;;
        000)
            echo -e "  ${RED}[ERROR] 네트워크 오류 - GHCR에 연결할 수 없습니다${NC}" >&2
            return 1
            ;;
        *)
            echo -e "  ${YELLOW}[WARN] 예상치 못한 응답: HTTP ${status}${NC}" >&2
            return 1
            ;;
    esac
}

# ============================================================
# 메인 실행
# ============================================================
main() {
    parse_args "$@"
    check_prerequisites

    echo "=== GHCR 이미지 존재 검증 시작 ==="
    echo "Helm 디렉토리: ${HELM_DIR}"
    echo ""

    for chart_dir in "${HELM_DIR}"/*/; do
        local chart_name
        chart_name="$(basename "${chart_dir}")"

        [[ ! -f "${chart_dir}/values.yaml" ]] && continue

        echo "--- ${chart_name} ---"

        # image.repository + image.tag 추출
        local repo tag
        repo="$(extract_value "${chart_dir}/values.yaml" "image.repository")"
        tag="$(extract_value "${chart_dir}/values.yaml" "image.tag")"

        if [[ -z "${repo}" || -z "${tag}" ]]; then
            echo -e "  ${YELLOW}[SKIP]${NC} image.repository 또는 image.tag 미설정"
            SKIP=$((SKIP + 1))
            continue
        fi

        # GHCR이 아닌 이미지는 스킵 (postgres 등 공식 이미지)
        if [[ "${repo}" != ghcr.io/* ]]; then
            echo -e "  ${YELLOW}[SKIP]${NC} GHCR 이미지가 아님: ${repo}"
            SKIP=$((SKIP + 1))
            continue
        fi

        # 태그 포맷 검증
        if [[ ! "${tag}" =~ ${TAG_PATTERN} ]]; then
            echo -e "  ${YELLOW}[WARN]${NC} 태그 포맷 불일치: ${tag} (기대: build-YYYYMMDD-HHMMSS)"
        fi

        # ghcr.io/ 접두사 제거 (API 경로용)
        local repo_path="${repo#ghcr.io/}"

        echo -n "  [check] ${repo}:${tag} ... "
        if check_image_exists "${repo_path}" "${tag}" "${TOKEN}"; then
            echo -e "${GREEN}EXISTS${NC}"
            PASS=$((PASS + 1))
        else
            echo -e "${RED}NOT FOUND${NC}"
            FAIL=$((FAIL + 1))
            ERRORS="${ERRORS}\n  - ${chart_name}: ${repo}:${tag}"
        fi

        echo ""
    done

    # 결과 요약
    echo "=== GHCR 이미지 검증 결과 ==="
    echo "  EXISTS: ${PASS}"
    echo "  NOT FOUND: ${FAIL}"
    echo "  SKIP: ${SKIP}"

    if [[ ${FAIL} -gt 0 ]]; then
        echo ""
        echo "미존재 이미지:"
        echo -e "${ERRORS}"
        exit 1
    fi

    echo ""
    echo "모든 이미지 존재 확인 완료!"
}

main "$@"
