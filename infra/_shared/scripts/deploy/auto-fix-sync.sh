#!/bin/bash
# ============================================================
# Auto-Fix 싱크 실패 자동 수정 엔진
# ============================================================
# diagnose-sync-failure.sh의 진단 결과를 입력으로 받아
# 알려진 패턴에 대해 자동 수정을 수행하거나 제안한다
#
# 사용법:
#   # dry-run (기본): 수정 제안만 출력
#   ./diagnose-sync-failure.sh --app observer-prod --json | ./auto-fix-sync.sh
#
#   # 파일에서 읽기:
#   ./auto-fix-sync.sh --diagnosis result.json
#
#   # 실제 적용:
#   ./auto-fix-sync.sh --diagnosis result.json --apply
#
#   # 자동 커밋 포함:
#   ./auto-fix-sync.sh --diagnosis result.json --apply --auto-commit
#
# 종료 코드:
#   0  수정 불필요 또는 모든 수정 성공 적용
#   1  수정 가능한 문제 발견 (dry-run 제안)
#   2  스크립트 실행 오류
#   3  수정 불가능한 문제 (수동 에스컬레이션)
#   4  수정 적용 실패 (Git 커밋/푸시 실패 등)
#
# 의존성: jq (필수), yq (YAML 수정 시), git (--auto-commit 시),
#          kubectl (namespace 수정 시), curl (이미지 롤백 시)
# ============================================================
set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1" >&2; }

# 스크립트 디렉터리 기준으로 경로 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../" && pwd)"

# 기본값
DIAGNOSIS_FILE=""
DRY_RUN=true
AUTO_COMMIT=false
MAX_FIXES=1
OUTPUT_FORMAT="text"
LOCK_FILE="/tmp/auto-fix-sync.lock"

# 임시 디렉토리 및 정리 트랩
WORK_TMPDIR="$(mktemp -d)"
trap 'rm -rf "${WORK_TMPDIR}"; rm -f "${LOCK_FILE}"' EXIT

# 결과 추적
FIXES_JSON='[]'
MANUAL_JSON='[]'

# ============================================================
# 사용법 출력
# ============================================================
usage() {
    cat <<'EOF'
사용법: auto-fix-sync.sh [옵션]

옵션:
  --diagnosis <file>   진단 JSON 파일 경로 (미지정 시 stdin에서 읽음)
  --repo-root <path>   Deployment 레포 루트 경로 (기본: 자동 감지)
  --dry-run            수정 사항을 출력만 하고 적용하지 않음 (기본값)
  --apply              실제 수정 적용
  --auto-commit        --apply와 함께 사용. 수정 후 자동 Git 커밋/푸시
  --max-fixes <n>      최대 자동 수정 시도 횟수 (기본: 1)
  --output <format>    출력 포맷: text (기본) 또는 json
  --help               이 도움말 출력

종료 코드:
  0  수정 불필요 또는 모든 수정 성공
  1  수정 가능한 문제 발견 (dry-run 제안)
  2  스크립트 실행 오류
  3  수정 불가능한 문제 (수동 에스컬레이션)
  4  수정 적용 실패

예시:
  ./diagnose-sync-failure.sh --app observer-prod --json | ./auto-fix-sync.sh
  ./auto-fix-sync.sh --diagnosis /tmp/diag.json --apply --auto-commit
EOF
    exit 2
}

# ============================================================
# 인자 파싱
# ============================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --diagnosis)
                [[ $# -lt 2 ]] && { log_error "--diagnosis 인자에 값이 필요합니다"; usage; }
                DIAGNOSIS_FILE="$2"
                shift 2
                ;;
            --repo-root)
                [[ $# -lt 2 ]] && { log_error "--repo-root 인자에 값이 필요합니다"; usage; }
                REPO_ROOT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --apply)
                DRY_RUN=false
                shift
                ;;
            --auto-commit)
                AUTO_COMMIT=true
                shift
                ;;
            --max-fixes)
                [[ $# -lt 2 ]] && { log_error "--max-fixes 인자에 값이 필요합니다"; usage; }
                MAX_FIXES="$2"
                shift 2
                ;;
            --output)
                [[ $# -lt 2 ]] && { log_error "--output 인자에 값이 필요합니다"; usage; }
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --help|-h)
                usage
                ;;
            *)
                log_warn "알 수 없는 인자: $1"
                shift
                ;;
        esac
    done

    # --auto-commit은 --apply와 함께만 사용
    if [[ "${AUTO_COMMIT}" == true ]] && [[ "${DRY_RUN}" == true ]]; then
        log_warn "--auto-commit은 --apply와 함께 사용해야 합니다. 무시합니다."
        AUTO_COMMIT=false
    fi
}

# ============================================================
# 의존성 확인
# ============================================================
check_prerequisites() {
    # jq 필수
    if ! command -v jq &>/dev/null; then
        log_error "jq가 설치되어 있지 않습니다 (필수)"
        exit 2
    fi

    # yq 권장 (YAML 수정 패턴에 필요)
    if ! command -v yq &>/dev/null; then
        log_warn "yq 미설치. YAML 수정이 필요한 패턴은 스킵됩니다"
    fi

    # git (--auto-commit 시 필수)
    if [[ "${AUTO_COMMIT}" == true ]] && ! command -v git &>/dev/null; then
        log_error "git이 설치되어 있지 않습니다 (--auto-commit에 필수)"
        exit 2
    fi
}

# ============================================================
# 락 파일 기반 중복 실행 방지
# ============================================================
acquire_lock() {
    local lock_file="${1:-${LOCK_FILE}}"
    local max_age=600  # 10분

    if [[ -f "${lock_file}" ]]; then
        local lock_age
        lock_age=$(( $(date +%s) - $(stat -c %Y "${lock_file}" 2>/dev/null || echo 0) ))

        if [[ ${lock_age} -lt ${max_age} ]]; then
            log_error "Auto-Fix가 이미 실행 중 (${lock_age}초 전 시작)"
            log_info "강제 해제: rm ${lock_file}"
            exit 2
        fi

        log_warn "오래된 락 파일 감지 (${lock_age}초). 해제 후 계속"
        rm -f "${lock_file}"
    fi

    echo "$$" > "${lock_file}"
}

# ============================================================
# 범위 제한 검증
# ============================================================
validate_target_path() {
    local file_path="$1"
    local repo_root="$2"

    # 절대 경로로 정규화
    local abs_path
    abs_path=$(realpath "${file_path}" 2>/dev/null || echo "${file_path}")

    # Deployment 레포 범위 확인
    if [[ "${abs_path}" != "${repo_root}"/* ]]; then
        log_error "범위 초과: ${file_path} (Deployment 레포 외부)"
        return 2
    fi

    # 앱 레포 디렉토리 변경 금지
    local forbidden_dirs=("QTS" "observer")
    for dir in "${forbidden_dirs[@]}"; do
        if [[ "${abs_path}" == *"/${dir}/"* ]]; then
            log_error "앱 레포 변경 금지: ${file_path}"
            return 2
        fi
    done

    return 0
}

# ============================================================
# 4.3.1 AppProject Whitelist 누락 수정
# ============================================================
fix_appproject_whitelist() {
    local issue_json="$1"
    local repo_root="$2"
    local dry_run="$3"

    local project_file="${repo_root}/infra/argocd/applications/project.yaml"

    if [[ ! -f "${project_file}" ]]; then
        log_error "project.yaml 파일 미존재: ${project_file}"
        return 3
    fi

    if ! command -v yq &>/dev/null; then
        log_warn "yq 미설치. AppProject whitelist 수정을 스킵합니다"
        return 3
    fi

    if ! validate_target_path "${project_file}" "${repo_root}"; then
        return 2
    fi

    local resource_kind resource_group
    resource_kind=$(echo "${issue_json}" | jq -r '.resource_kind // empty')
    resource_group=$(echo "${issue_json}" | jq -r '.resource_group // ""')

    # resource_kind가 없으면 메시지에서 추출 시도
    if [[ -z "${resource_kind}" ]]; then
        resource_kind=$(echo "${issue_json}" | jq -r '.message' | \
            grep -oP 'resource \K\S+' | head -1 || true)
    fi

    if [[ -z "${resource_kind}" ]]; then
        log_warn "리소스 kind 추출 실패. 수정 스킵"
        return 3
    fi

    log_info "AppProject whitelist 수정: ${resource_kind} (${resource_group:-core})"

    # 이미 whitelist에 존재하는지 확인 (중복 방지)
    if yq -e ".spec.clusterResourceWhitelist[] |
        select(.kind == \"${resource_kind}\" and .group == \"${resource_group}\")" \
        "${project_file}" &>/dev/null; then
        log_info "이미 whitelist에 존재: ${resource_kind}"
        return 0
    fi

    if [[ "${dry_run}" == true ]]; then
        log_info "[DRY-RUN] 다음 항목이 clusterResourceWhitelist에 추가됩니다:"
        log_info "  - group: \"${resource_group}\""
        log_info "    kind: ${resource_kind}"

        # diff 미리보기
        local tmp_file="${WORK_TMPDIR}/project-patched.yaml"
        cp "${project_file}" "${tmp_file}"
        yq -i ".spec.clusterResourceWhitelist += \
            [{\"group\": \"${resource_group}\", \"kind\": \"${resource_kind}\"}]" \
            "${tmp_file}"
        diff "${project_file}" "${tmp_file}" || true
        return 1  # dry-run 제안
    fi

    # --apply 모드: 실제 파일 수정
    # 수정 전 백업
    mkdir -p "${WORK_TMPDIR}/backup"
    cp "${project_file}" "${WORK_TMPDIR}/backup/$(basename "${project_file}")"

    yq -i ".spec.clusterResourceWhitelist += \
        [{\"group\": \"${resource_group}\", \"kind\": \"${resource_kind}\"}]" \
        "${project_file}"

    log_info "적용 완료: ${project_file}"
    echo "${project_file}" >> "${WORK_TMPDIR}/modified-files.txt"
    return 0
}

# ============================================================
# 4.3.2 네임스페이스 미존재 수정
# ============================================================
fix_namespace_not_found() {
    local issue_json="$1"
    local dry_run="$2"

    # 에러 메시지에서 네임스페이스 이름 추출
    local namespace
    namespace=$(echo "${issue_json}" | jq -r '.message' | \
        grep -oP 'namespace[: "]+\K[a-zA-Z0-9_-]+' | head -1 || true)

    if [[ -z "${namespace}" ]]; then
        log_warn "네임스페이스 이름 추출 실패"
        return 3
    fi

    log_info "네임스페이스 생성: ${namespace}"

    if [[ "${dry_run}" == true ]]; then
        log_info "[DRY-RUN] kubectl create namespace ${namespace}"
        return 1
    fi

    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl 미설치. SSH 환경에서만 실행 가능"
        return 3
    fi

    if kubectl get namespace "${namespace}" &>/dev/null; then
        log_info "네임스페이스 이미 존재: ${namespace}"
        return 0
    fi

    kubectl create namespace "${namespace}"
    log_info "네임스페이스 생성 완료: ${namespace}"
    return 0
}

# ============================================================
# 4.3.3 PV/PVC 바인딩 실패 가이드
# ============================================================
fix_pvc_not_found() {
    local issue_json="$1"
    local repo_root="$2"
    local dry_run="$3"

    log_info "PV/PVC 바인딩 진단 시작"

    # kubectl 접근 가능 시: PV 상태 확인
    if command -v kubectl &>/dev/null; then
        log_info "현재 PV 상태:"
        kubectl get pv 2>/dev/null || log_warn "PV 조회 실패 (클러스터 접근 불가)"

        log_info "현재 PVC 상태:"
        kubectl get pvc --all-namespaces 2>/dev/null || log_warn "PVC 조회 실패"

        # Released 상태 PV 탐지
        local released_pvs
        released_pvs=$(kubectl get pv -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase == "Released") |
            .metadata.name' || true)

        if [[ -n "${released_pvs}" ]]; then
            log_warn "Released 상태 PV 발견 (reclaim 필요):"
            echo "${released_pvs}" | while read -r pv; do
                log_info "  kubectl patch pv ${pv} -p '{\"spec\":{\"claimRef\":null}}'"
            done
        fi
    fi

    # 수정 제안 출력
    log_info ""
    log_info "수동 확인 필요:"
    log_info "  1. PV hostPath가 노드에 실제 존재하는지 확인"
    log_info "  2. PV storageClassName이 PVC와 일치하는지 확인"
    log_info "  3. PV capacity가 PVC request 이상인지 확인"
    log_info "  4. PV nodeAffinity의 nodeName이 올바른지 확인"

    return 3  # 수동 처리 필요
}

# ============================================================
# 4.3.4 이미지 태그 롤백 제안
# ============================================================
fix_image_pull_backoff() {
    local issue_json="$1"
    local repo_root="$2"
    local dry_run="$3"

    local helm_dir="${repo_root}/infra/helm"

    if [[ ! -d "${helm_dir}" ]]; then
        log_warn "Helm 디렉토리 미존재: ${helm_dir}"
        return 3
    fi

    log_info "이미지 태그 검증 시작"

    for chart_dir in "${helm_dir}"/*/; do
        [[ ! -f "${chart_dir}/values.yaml" ]] && continue

        local chart_name repo tag
        chart_name="$(basename "${chart_dir}")"

        if command -v yq &>/dev/null; then
            repo=$(yq -r '.image.repository // ""' "${chart_dir}/values.yaml")
            tag=$(yq -r '.image.tag // ""' "${chart_dir}/values.yaml")
        else
            # yq 없을 때 jq 기반 폴백 (YAML → JSON 변환은 불가하므로 grep)
            repo=$(grep -A1 'repository:' "${chart_dir}/values.yaml" | tail -1 | awk '{print $NF}' | tr -d '"' || true)
            tag=$(grep 'tag:' "${chart_dir}/values.yaml" | head -1 | awk '{print $NF}' | tr -d '"' || true)
        fi

        [[ -z "${repo}" || -z "${tag}" ]] && continue
        # GHCR 이미지만 대상
        [[ "${repo}" != ghcr.io/* ]] && continue

        local repo_path="${repo#ghcr.io/}"

        # 태그 포맷 검증
        if ! [[ "${tag}" =~ ^build-20[0-9]{6}-[0-9]{6}$ ]]; then
            log_warn "${chart_name}: 비정상 태그 포맷: ${tag}"
            log_info "  기대 패턴: build-YYYYMMDD-HHMMSS"
            continue
        fi

        # GHCR에서 최신 유효 태그 조회
        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            local latest_tag
            latest_tag=$(curl -s \
                -H "Authorization: Bearer ${GITHUB_TOKEN}" \
                "https://api.github.com/users/${repo_path%%/*}/packages/container/${repo_path##*/}/versions" \
                2>/dev/null | \
                jq -r '[.[] | .metadata.container.tags[] |
                    select(startswith("build-"))] | .[0] // empty' || true)

            if [[ -n "${latest_tag}" ]] && [[ "${latest_tag}" != "${tag}" ]]; then
                log_info "${chart_name}: 최신 유효 태그: ${latest_tag} (현재: ${tag})"

                if [[ "${dry_run}" == true ]]; then
                    log_info "[DRY-RUN] ${chart_dir}values.yaml image.tag 롤백 제안"
                    log_info "  ${tag} -> ${latest_tag}"
                    return 1
                fi

                if ! validate_target_path "${chart_dir}/values.yaml" "${repo_root}"; then
                    return 2
                fi

                # 수정 전 백업
                mkdir -p "${WORK_TMPDIR}/backup"
                cp "${chart_dir}/values.yaml" \
                    "${WORK_TMPDIR}/backup/${chart_name}-values.yaml"

                yq -i ".image.tag = \"${latest_tag}\"" "${chart_dir}/values.yaml"
                log_info "태그 롤백 적용: ${tag} -> ${latest_tag}"
                echo "${chart_dir}/values.yaml" >> "${WORK_TMPDIR}/modified-files.txt"
                return 0
            fi
        else
            log_warn "GITHUB_TOKEN 미설정. GHCR 태그 조회 스킵"
        fi
    done

    return 3  # 수정 불가
}

# ============================================================
# 4.3.5 수동 에스컬레이션
# ============================================================
escalate_manual() {
    local issue_json="$1"

    local pattern message
    pattern=$(echo "${issue_json}" | jq -r '.pattern')
    message=$(echo "${issue_json}" | jq -r '.message')

    log_warn "자동 수정 불가 - 수동 처리 필요"
    log_info "  패턴: ${pattern}"
    log_info "  메시지: ${message}"

    local suggestion=""
    case "${pattern}" in
        helm_template_error)
            suggestion="helm template <chart> <chart-dir>/ 로 직접 디버깅"
            log_info "  제안: ${suggestion}"
            log_info "  확인: values.yaml 문법, 템플릿 조건문 검토"
            ;;
        exceeded_quota)
            suggestion="kubectl describe resourcequota -n <namespace>"
            log_info "  제안: ${suggestion}"
            log_info "  확인: 리소스 요청량 축소 또는 쿼타 상향 검토"
            ;;
        *)
            suggestion="ArgoCD 대시보드에서 상세 상태 확인"
            log_info "  제안: ${suggestion}"
            ;;
    esac

    # 결과 추적
    MANUAL_JSON=$(echo "${MANUAL_JSON}" | jq \
        --arg id "MANUAL-$(($(echo "${MANUAL_JSON}" | jq 'length') + 1))" \
        --arg pattern "${pattern}" \
        --arg desc "${message}" \
        --arg suggestion "${suggestion}" \
        '. + [{id: $id, pattern: $pattern, description: $desc, suggestion: $suggestion}]')

    return 3
}

# ============================================================
# 수정 디스패처
# ============================================================
dispatch_fix() {
    local issue_json="$1"
    local pattern
    pattern=$(echo "${issue_json}" | jq -r '.pattern')

    case "${pattern}" in
        appproject_whitelist_missing)
            fix_appproject_whitelist "${issue_json}" "${REPO_ROOT}" "${DRY_RUN}"
            ;;
        namespace_not_found)
            fix_namespace_not_found "${issue_json}" "${DRY_RUN}"
            ;;
        pvc_not_found)
            fix_pvc_not_found "${issue_json}" "${REPO_ROOT}" "${DRY_RUN}"
            ;;
        image_pull_backoff)
            fix_image_pull_backoff "${issue_json}" "${REPO_ROOT}" "${DRY_RUN}"
            ;;
        *)
            escalate_manual "${issue_json}"
            ;;
    esac
}

# ============================================================
# Git 커밋/푸시
# ============================================================
git_commit_fixes() {
    local repo_root="$1"
    local modified_files="$2"

    if [[ ! -f "${modified_files}" ]] || [[ ! -s "${modified_files}" ]]; then
        log_info "커밋할 변경 사항 없음"
        return 0
    fi

    cd "${repo_root}"

    # Git 상태 확인
    if ! git diff --quiet 2>/dev/null; then
        log_warn "커밋되지 않은 기존 변경 사항이 존재합니다"
    fi

    # 수정된 파일만 스테이징
    while IFS= read -r file; do
        local rel_path="${file#${repo_root}/}"
        git add "${rel_path}"
        log_info "스테이징: ${rel_path}"
    done < "${modified_files}"

    # 커밋 메시지 생성
    local fix_count
    fix_count=$(wc -l < "${modified_files}")

    local file_list=""
    while IFS= read -r file; do
        file_list="${file_list}  - ${file#${repo_root}/}
"
    done < "${modified_files}"

    local commit_msg="fix(auto-fix): 싱크 실패 자동 수정 (${fix_count}건)

자동 수정 항목:
${file_list}
Generated by: auto-fix-sync.sh
Trigger: ArgoCD sync failure diagnosis"

    git commit -m "${commit_msg}"
    log_info "커밋 완료"

    # 푸시
    local current_branch
    current_branch=$(git branch --show-current)

    if [[ "${current_branch}" == "master" || "${current_branch}" == "main" ]]; then
        git push origin "${current_branch}"
        log_info "푸시 완료: ${current_branch}"
    else
        log_warn "master/main이 아닌 브랜치 (${current_branch}). 수동 푸시 필요"
        return 4
    fi

    return 0
}

# ============================================================
# 결과 요약 출력
# ============================================================
print_summary() {
    local issue_count="$1"
    local applied_count="$2"
    local fix_count="$3"
    local manual_count="$4"

    if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
        local mode="dry-run"
        [[ "${DRY_RUN}" == false ]] && mode="apply"

        jq -n \
            --arg mode "${mode}" \
            --argjson total "${issue_count}" \
            --argjson fixable "$((applied_count + fix_count))" \
            --argjson manual "${manual_count}" \
            --argjson applied "${applied_count}" \
            --argjson fixes "${FIXES_JSON}" \
            --argjson manual_items "${MANUAL_JSON}" \
            '{
                mode: $mode,
                total_issues: $total,
                fixable: $fixable,
                manual: $manual,
                applied: $applied,
                fixes: $fixes,
                manual_items: $manual_items
            }'
    else
        echo "" >&2
        echo -e "${BOLD}=== Auto-Fix 결과 ===${NC}" >&2
        echo -e "  모드: $(${DRY_RUN} && echo 'dry-run (실제 적용 없음)' || echo 'apply')" >&2
        echo -e "  발견된 문제: ${issue_count}건" >&2
        echo -e "  자동 수정: ${applied_count}건 적용" >&2
        echo -e "  수정 제안: ${fix_count}건 (dry-run)" >&2
        echo -e "  수동 처리: ${manual_count}건" >&2

        if [[ "${DRY_RUN}" == true ]] && [[ ${fix_count} -gt 0 ]]; then
            echo "" >&2
            echo -e "${YELLOW}[INFO]${NC} 실제 적용하려면 --apply 플래그를 사용하세요." >&2
        fi
    fi
}

# ============================================================
# 진단 JSON에서 issue 목록 추출 (다양한 스키마 지원)
# ============================================================
extract_issues() {
    local diagnosis="$1"

    # Phase 2-1 출력 형식: diagnosis.results[].errors[]
    # 단순화된 형식: issues[]
    # 진단 보고서에서 issues 추출 시도
    local issues

    # 방법 1: diagnosis.results[].errors[] (diagnose-sync-failure.sh --json 출력)
    issues=$(echo "${diagnosis}" | jq '
        if .diagnosis.results then
            [.diagnosis.results[].errors[] |
                {
                    pattern: (
                        if .category == "appproject_permission" then "appproject_whitelist_missing"
                        elif .category == "namespace_missing" then "namespace_not_found"
                        elif .category == "pvc_missing" then "pvc_not_found"
                        elif .category == "pv_missing" then "pvc_not_found"
                        elif .category == "image_pull" then "image_pull_backoff"
                        elif .category == "helm_render" then "helm_template_error"
                        elif .category == "resource_quota" then "exceeded_quota"
                        else .category
                        end
                    ),
                    severity: .severity,
                    message: (.matched_messages[0] // .description),
                    resource_kind: (.affected_resources[0].kind // ""),
                    resource_group: (.affected_resources[0].group // ""),
                    auto_fixable: .auto_fixable
                }
            ]
        elif .issues then
            .issues
        else
            []
        end
    ' 2>/dev/null)

    echo "${issues}"
}

# ============================================================
# 메인 실행
# ============================================================
main() {
    parse_args "$@"
    check_prerequisites
    acquire_lock "${LOCK_FILE}"

    log_step "=== Auto-Fix 엔진 시작 ==="
    log_info "모드: $(${DRY_RUN} && echo 'dry-run' || echo 'apply')"
    log_info "최대 수정: ${MAX_FIXES}건"
    log_info "레포 루트: ${REPO_ROOT}"

    # 1. 진단 입력 읽기
    local diagnosis
    if [[ -n "${DIAGNOSIS_FILE}" ]]; then
        if [[ ! -f "${DIAGNOSIS_FILE}" ]]; then
            log_error "진단 파일 미존재: ${DIAGNOSIS_FILE}"
            exit 2
        fi
        diagnosis=$(cat "${DIAGNOSIS_FILE}")
    else
        diagnosis=$(cat -)  # stdin에서 읽기
    fi

    # JSON 유효성 확인
    if ! echo "${diagnosis}" | jq empty 2>/dev/null; then
        log_error "진단 입력이 유효한 JSON이 아닙니다"
        exit 2
    fi

    # 2. issue 목록 추출
    local issues
    issues=$(extract_issues "${diagnosis}")

    local issue_count
    issue_count=$(echo "${issues}" | jq 'length')

    if [[ ${issue_count} -eq 0 ]]; then
        log_info "수정할 문제 없음"
        print_summary 0 0 0 0
        exit 0
    fi

    log_info "발견된 문제: ${issue_count}건"

    # 3. 수정 대상 파일 백업 디렉토리
    mkdir -p "${WORK_TMPDIR}/backup"

    # 4. 패턴별 수정 실행
    local fix_count=0 manual_count=0 applied_count=0
    local seen_patterns=""

    for i in $(seq 0 $((issue_count - 1))); do
        local issue
        issue=$(echo "${issues}" | jq ".[$i]")

        local auto_fixable pattern
        auto_fixable=$(echo "${issue}" | jq -r '.auto_fixable')
        pattern=$(echo "${issue}" | jq -r '.pattern')

        # 중복 패턴 처리 (동일 패턴 첫 번째만 수정)
        if echo "${seen_patterns}" | grep -qw "${pattern}"; then
            log_info "중복 패턴 스킵: ${pattern}"
            continue
        fi
        seen_patterns="${seen_patterns} ${pattern}"

        if [[ "${auto_fixable}" != "true" ]]; then
            escalate_manual "${issue}" || true
            ((manual_count++))
            continue
        fi

        # --apply 모드: max-fixes 제한 확인
        if [[ "${DRY_RUN}" == false ]] && [[ ${applied_count} -ge ${MAX_FIXES} ]]; then
            log_warn "최대 수정 횟수 도달 (${MAX_FIXES}). 나머지는 보고만"
            escalate_manual "${issue}" || true
            ((manual_count++))
            continue
        fi

        log_step "수정 시도: ${pattern}"

        local result=0
        dispatch_fix "${issue}" || result=$?

        case ${result} in
            0)
                ((applied_count++))
                FIXES_JSON=$(echo "${FIXES_JSON}" | jq \
                    --arg id "FIX-$((applied_count))" \
                    --arg pattern "${pattern}" \
                    --arg desc "$(echo "${issue}" | jq -r '.message')" \
                    '. + [{id: $id, pattern: $pattern, description: $desc, status: "applied"}]')
                ;;
            1)
                ((fix_count++))
                FIXES_JSON=$(echo "${FIXES_JSON}" | jq \
                    --arg id "FIX-$((fix_count))" \
                    --arg pattern "${pattern}" \
                    --arg desc "$(echo "${issue}" | jq -r '.message')" \
                    '. + [{id: $id, pattern: $pattern, description: $desc, status: "pending"}]')
                ;;
            3)
                ((manual_count++))
                ;;
            *)
                ((manual_count++))
                ;;
        esac
    done

    # 5. 자동 커밋 (--apply --auto-commit)
    if [[ "${DRY_RUN}" == false ]] && [[ "${AUTO_COMMIT}" == true ]]; then
        if [[ ${applied_count} -gt 0 ]]; then
            local git_result=0
            git_commit_fixes "${REPO_ROOT}" "${WORK_TMPDIR}/modified-files.txt" || git_result=$?

            if [[ ${git_result} -ne 0 ]]; then
                log_error "Git 커밋/푸시 실패"
                print_summary "${issue_count}" "${applied_count}" "${fix_count}" "${manual_count}"
                exit 4
            fi

            # 롤백 가이드 출력
            local commit_hash
            commit_hash=$(cd "${REPO_ROOT}" && git rev-parse HEAD)
            log_info "롤백 방법: cd ${REPO_ROOT} && git revert ${commit_hash}"
        fi
    fi

    # 6. 결과 출력
    print_summary "${issue_count}" "${applied_count}" "${fix_count}" "${manual_count}"

    # 종료 코드 결정
    if [[ ${manual_count} -gt 0 ]] && [[ ${applied_count} -eq 0 ]] && [[ ${fix_count} -eq 0 ]]; then
        exit 3  # 수동 처리만 필요
    elif [[ ${fix_count} -gt 0 ]]; then
        exit 1  # dry-run 제안 있음
    fi
    exit 0
}

main "$@"
