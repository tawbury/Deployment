#!/bin/bash
# AppProject ↔ Helm 차트 리소스 정합성 검증기
# ============================================================
# Helm 차트에서 생성하는 cluster-scoped 리소스가
# AppProject clusterResourceWhitelist에 모두 포함되는지 검증
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"

# 기본값
PROJECT_FILE="${REPO_ROOT}/infra/argocd/applications/project.yaml"
HELM_DIR="${REPO_ROOT}/infra/helm"
FIX_MODE=false
OUTPUT_FORMAT="text"

# 카운터
PASS=0
FAIL=0
ERRORS=""

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 알려진 cluster-scoped 리소스 (group|kind)
# 현재 플랫폼에서 사용 가능성이 있는 리소스만 포함
KNOWN_CLUSTER_SCOPED=(
    # Core API (group: "")
    "|Namespace"
    "|Node"
    "|PersistentVolume"

    # rbac.authorization.k8s.io
    "rbac.authorization.k8s.io|ClusterRole"
    "rbac.authorization.k8s.io|ClusterRoleBinding"

    # storage.k8s.io
    "storage.k8s.io|StorageClass"

    # apiextensions.k8s.io
    "apiextensions.k8s.io|CustomResourceDefinition"

    # scheduling.k8s.io
    "scheduling.k8s.io|PriorityClass"

    # networking.k8s.io
    "networking.k8s.io|IngressClass"

    # admissionregistration.k8s.io
    "admissionregistration.k8s.io|MutatingWebhookConfiguration"
    "admissionregistration.k8s.io|ValidatingWebhookConfiguration"

    # certificates.k8s.io
    "certificates.k8s.io|CertificateSigningRequest"

    # policy
    "policy|PodSecurityPolicy"

    # node.k8s.io
    "node.k8s.io|RuntimeClass"
)

# ============================================================
# 인자 파싱
# ============================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project-file)
                PROJECT_FILE="$2"
                shift 2
                ;;
            --helm-dir)
                HELM_DIR="$2"
                shift 2
                ;;
            --fix)
                FIX_MODE=true
                shift
                ;;
            --output)
                OUTPUT_FORMAT="$2"
                if [[ "${OUTPUT_FORMAT}" != "text" && "${OUTPUT_FORMAT}" != "json" ]]; then
                    echo "[ERROR] --output 값은 'text' 또는 'json'이어야 합니다." >&2
                    exit 2
                fi
                shift 2
                ;;
            --help)
                echo "사용법: $(basename "$0") [옵션]"
                echo ""
                echo "옵션:"
                echo "  --project-file <path>  AppProject 매니페스트 경로 (기본: infra/argocd/applications/project.yaml)"
                echo "  --helm-dir <path>      Helm 차트 루트 디렉토리 (기본: infra/helm)"
                echo "  --fix                  누락 리소스 자동 패치 모드"
                echo "  --output <format>      출력 포맷: text 또는 json (기본: text)"
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
    if ! command -v helm &>/dev/null; then
        echo "[ERROR] helm이 설치되어 있지 않습니다." >&2
        exit 2
    fi

    if [[ ! -f "${PROJECT_FILE}" ]]; then
        echo "[ERROR] 프로젝트 파일이 존재하지 않습니다: ${PROJECT_FILE}" >&2
        exit 2
    fi

    if [[ ! -d "${HELM_DIR}" ]]; then
        echo "[ERROR] Helm 디렉토리가 존재하지 않습니다: ${HELM_DIR}" >&2
        exit 2
    fi
}

# ============================================================
# cluster-scoped 리소스 판별 함수
# ============================================================
is_cluster_scoped() {
    local kind="$1"
    for entry in "${KNOWN_CLUSTER_SCOPED[@]}"; do
        local entry_kind="${entry#*|}"
        if [[ "${kind}" == "${entry_kind}" ]]; then
            return 0
        fi
    done
    return 1
}

# ============================================================
# Helm 렌더링 → apiVersion + kind 쌍 추출
# ============================================================
extract_api_kind_pairs() {
    local rendered_file="$1"

    # awk로 --- 구분자 기준 apiVersion과 kind 쌍 추출
    awk '
    /^---/ { api=""; kind="" }
    /^apiVersion:/ { api=$2 }
    /^kind:/ { kind=$2 }
    api != "" && kind != "" {
        # apiVersion에서 group 분리 (v1 → "", apps/v1 → "apps")
        split(api, parts, "/")
        if (length(parts) == 1) group = ""
        else group = parts[1]
        print group "|" kind
        api=""; kind=""
    }
    ' "${rendered_file}"
}

# ============================================================
# Helm 차트에서 cluster-scoped 리소스 추출
# ============================================================
extract_cluster_scoped_kinds() {
    local helm_dir="$1"
    local tmpdir="$2"
    local rendered_count=0

    for chart_dir in "${helm_dir}"/*/; do
        local chart_name
        chart_name="$(basename "${chart_dir}")"

        # Chart.yaml 없으면 스킵
        [[ ! -f "${chart_dir}/Chart.yaml" ]] && continue

        # values 파일 조합 결정
        local values_args=()
        if [[ -f "${chart_dir}/values.yaml" ]]; then
            values_args+=(-f "${chart_dir}/values.yaml")
        fi
        if [[ -f "${chart_dir}/values-prod.yaml" ]]; then
            values_args+=(-f "${chart_dir}/values-prod.yaml")
        fi

        # helm template 렌더링
        local output_file="${tmpdir}/${chart_name}-rendered.yaml"
        if ! helm template "${chart_name}" "${chart_dir}" \
            "${values_args[@]}" > "${output_file}" 2>/dev/null; then
            echo -e "  ${YELLOW}[WARN] ${chart_name}: helm template 렌더링 실패${NC}" >&2
            continue
        fi
        rendered_count=$((rendered_count + 1))

        # apiVersion + kind 쌍 추출
        extract_api_kind_pairs "${output_file}" >> "${tmpdir}/all-pairs.txt"
    done

    # 렌더링 가능한 차트가 하나도 없으면 오류 (E5)
    if [[ ${rendered_count} -eq 0 ]]; then
        # 차트 디렉토리 자체가 없는 경우 (E3) vs 모두 실패 (E5) 구분
        local chart_count=0
        for chart_dir in "${helm_dir}"/*/; do
            [[ -f "${chart_dir}/Chart.yaml" ]] && chart_count=$((chart_count + 1))
        done
        if [[ ${chart_count} -eq 0 ]]; then
            # E3: 검증할 대상 없음
            return 0
        fi
        echo "[ERROR] 모든 차트의 helm template 렌더링에 실패했습니다." >&2
        exit 2
    fi

    # cluster-scoped 리소스만 필터링하여 고유 목록 생성
    if [[ -f "${tmpdir}/all-pairs.txt" ]]; then
        while IFS='|' read -r group kind; do
            # kind 공백 제거
            kind="$(echo "${kind}" | tr -d '[:space:]')"
            group="$(echo "${group}" | tr -d '[:space:]')"
            if is_cluster_scoped "${kind}"; then
                echo "${group}|${kind}"
            fi
        done < "${tmpdir}/all-pairs.txt" | sort -u > "${tmpdir}/required.txt"
    else
        touch "${tmpdir}/required.txt"
    fi
}

# ============================================================
# project.yaml clusterResourceWhitelist 파싱
# ============================================================
parse_whitelist() {
    local project_file="$1"

    if command -v yq &>/dev/null; then
        yq -r '.spec.clusterResourceWhitelist[]? | .group + "|" + .kind' "${project_file}" 2>/dev/null || true
        return
    fi

    # yq 미설치 시: awk 기반 파싱 (E7 폴백)
    awk '
    /^  clusterResourceWhitelist:/ { in_section=1; next }
    in_section && /^  [a-zA-Z]/ { in_section=0 }
    in_section && /group:/ { gsub(/"/, ""); group=$2 }
    in_section && /kind:/ {
        gsub(/"/, ""); kind=$2
        print group "|" kind
        group=""
    }
    ' "${project_file}"
}

# ============================================================
# project.yaml destinations 파싱
# ============================================================
parse_destinations() {
    local project_file="$1"

    if command -v yq &>/dev/null; then
        yq -r '.spec.destinations[]? | .namespace' "${project_file}" 2>/dev/null || true
        return
    fi

    awk '
    /^  destinations:/ { in_section=1; next }
    in_section && /^  [a-zA-Z]/ { in_section=0 }
    in_section && /namespace:/ { gsub(/"/, ""); print $2 }
    ' "${project_file}"
}

# ============================================================
# 와일드카드 whitelist 검사 (E8: group: "*", kind: "*")
# ============================================================
has_wildcard_whitelist() {
    local whitelist_file="$1"
    if grep -qE '^\*\|\*$' "${whitelist_file}" 2>/dev/null; then
        return 0
    fi
    return 1
}

# ============================================================
# clusterResourceWhitelist 비교
# ============================================================
compare_cluster_resources() {
    local required_file="$1"
    local whitelist_file="$2"
    local tmpdir="$3"

    # 필요한 cluster-scoped 리소스가 없으면 PASS
    if [[ ! -s "${required_file}" ]]; then
        if [[ "${OUTPUT_FORMAT}" == "text" ]]; then
            echo -e "  ${GREEN}[INFO] cluster-scoped 리소스가 없습니다.${NC}"
        fi
        return 0
    fi

    # 와일드카드 허용 확인 (E8)
    if has_wildcard_whitelist "${whitelist_file}"; then
        if [[ "${OUTPUT_FORMAT}" == "text" ]]; then
            echo -e "  ${GREEN}[INFO] 와일드카드 whitelist 감지 - 모든 리소스 허용${NC}"
        fi
        local count
        count=$(wc -l < "${required_file}")
        PASS=$((PASS + count))
        return 0
    fi

    local missing_count=0

    while IFS='|' read -r group kind; do
        [[ -z "${kind}" ]] && continue
        if grep -qF "${group}|${kind}" "${whitelist_file}" 2>/dev/null; then
            if [[ "${OUTPUT_FORMAT}" == "text" ]]; then
                echo -e "  ${GREEN}[PASS]${NC} ${kind} (${group:-core/v1})"
            fi
            PASS=$((PASS + 1))
        else
            if [[ "${OUTPUT_FORMAT}" == "text" ]]; then
                echo -e "  ${RED}[FAIL]${NC} ${kind} (${group:-core/v1}) - whitelist에 누락"
            fi
            echo "${group}|${kind}" >> "${tmpdir}/missing-resources.txt"
            FAIL=$((FAIL + 1))
            missing_count=$((missing_count + 1))
        fi
    done < "${required_file}"

    return ${missing_count}
}

# ============================================================
# destinations 검증 (Helm 차트 namespace vs project destinations)
# ============================================================
compare_destinations() {
    local helm_dir="$1"
    local dest_file="$2"
    local tmpdir="$3"

    local missing_count=0

    # 각 차트의 values.yaml에서 namespace 관련 설정 확인은 복잡하므로
    # 현재는 destinations 파싱 자체만 검증 (project.yaml에 destinations가 있는지)
    # 향후 확장 가능

    return ${missing_count}
}

# ============================================================
# 패치 생성 (--fix 모드)
# ============================================================
generate_patch() {
    local project_file="$1"
    local missing_file="$2"
    local patch_file="$3"

    if [[ ! -s "${missing_file}" ]]; then
        if [[ "${OUTPUT_FORMAT}" == "text" ]]; then
            echo -e "  ${GREEN}[INFO] 패치할 항목 없음${NC}"
        fi
        return 0
    fi

    cp "${project_file}" "${patch_file}"

    if command -v yq &>/dev/null; then
        while IFS='|' read -r group kind; do
            yq -i ".spec.clusterResourceWhitelist += [{\"group\": \"${group}\", \"kind\": \"${kind}\"}]" \
                "${patch_file}"
        done < "${missing_file}"
    else
        # yq 없는 경우 수동 패치 안내
        if [[ "${OUTPUT_FORMAT}" == "text" ]]; then
            echo -e "  ${YELLOW}[WARN] yq 미설치 - 자동 패치 불가. 아래 항목을 수동으로 추가하세요:${NC}"
            while IFS='|' read -r group kind; do
                echo "    - group: \"${group}\""
                echo "      kind: ${kind}"
            done < "${missing_file}"
        fi
        return 0
    fi

    if [[ "${OUTPUT_FORMAT}" == "text" ]]; then
        echo -e "  ${GREEN}[FIX] 패치 생성 완료: ${patch_file}${NC}"
        echo "  적용: cp ${patch_file} ${project_file}"
        echo ""
        echo "--- 변경 사항 ---"
        diff "${project_file}" "${patch_file}" || true
    fi
}

# ============================================================
# 결과 출력
# ============================================================
print_summary() {
    local total_fail="$1"
    local tmpdir="$2"

    if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
        # JSON 출력
        local status="PASS"
        [[ ${total_fail} -gt 0 ]] && status="FAIL"

        local missing_resources="[]"
        if [[ -s "${tmpdir}/missing-resources.txt" ]]; then
            missing_resources="["
            local first=true
            while IFS='|' read -r group kind; do
                if [[ "${first}" == true ]]; then
                    first=false
                else
                    missing_resources="${missing_resources},"
                fi
                missing_resources="${missing_resources}{\"group\":\"${group}\",\"kind\":\"${kind}\"}"
            done < "${tmpdir}/missing-resources.txt"
            missing_resources="${missing_resources}]"
        fi

        local patch_available="false"
        [[ ${total_fail} -gt 0 ]] && patch_available="true"

        if command -v jq &>/dev/null; then
            jq -n \
                --arg status "${status}" \
                --argjson pass "${PASS}" \
                --argjson fail "${FAIL}" \
                --argjson missing "${missing_resources}" \
                --argjson patch "${patch_available}" \
                '{status: $status, pass: $pass, fail: $fail, missing_cluster_resources: $missing, patch_available: $patch}'
        else
            printf '{"status":"%s","pass":%d,"fail":%d,"missing_cluster_resources":%s,"patch_available":%s}\n' \
                "${status}" "${PASS}" "${FAIL}" "${missing_resources}" "${patch_available}"
        fi
    else
        # text 출력
        echo ""
        echo "=== 검증 결과 ==="
        echo "  PASS: ${PASS}"
        echo "  FAIL: ${FAIL}"

        if [[ -s "${tmpdir}/missing-resources.txt" ]]; then
            echo ""
            echo "누락 항목:"
            while IFS='|' read -r group kind; do
                echo "  - clusterResourceWhitelist: ${kind} (${group:-core})"
            done < "${tmpdir}/missing-resources.txt"
        fi

        if [[ ${total_fail} -gt 0 && "${FIX_MODE}" == false ]]; then
            echo ""
            echo -e "${CYAN}[FIX] 자동 패치를 적용하려면 --fix 플래그를 사용하세요.${NC}"
        fi
    fi
}

# ============================================================
# 메인 실행
# ============================================================
main() {
    parse_args "$@"
    check_prerequisites

    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "${TMPDIR}"' EXIT

    if [[ "${OUTPUT_FORMAT}" == "text" ]]; then
        echo "=== AppProject 권한 검증 시작 ==="
        echo "프로젝트 파일: ${PROJECT_FILE}"
        echo "Helm 디렉토리: ${HELM_DIR}"
        echo ""
    fi

    # 1. Helm 차트에서 cluster-scoped 리소스 추출
    extract_cluster_scoped_kinds "${HELM_DIR}" "${TMPDIR}"

    # 2. project.yaml whitelist 파싱
    parse_whitelist "${PROJECT_FILE}" > "${TMPDIR}/whitelist.txt"

    # 3. clusterResourceWhitelist 비교
    if [[ "${OUTPUT_FORMAT}" == "text" ]]; then
        echo "--- clusterResourceWhitelist 검증 ---"
    fi
    touch "${TMPDIR}/missing-resources.txt"
    compare_cluster_resources "${TMPDIR}/required.txt" "${TMPDIR}/whitelist.txt" "${TMPDIR}" || true
    local resource_fail=${FAIL}

    # 4. 결과 출력
    print_summary ${resource_fail} "${TMPDIR}"

    # 5. 자동 패치 (--fix 모드)
    if [[ "${FIX_MODE}" == true && ${resource_fail} -gt 0 ]]; then
        if [[ "${OUTPUT_FORMAT}" == "text" ]]; then
            echo ""
            echo "--- 자동 패치 ---"
        fi
        generate_patch "${PROJECT_FILE}" "${TMPDIR}/missing-resources.txt" \
            "${TMPDIR}/project-patched.yaml"
    fi

    [[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
}

main "$@"
