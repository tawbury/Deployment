#!/bin/bash
# ============================================================
# ArgoCD 싱크 실패 진단기
# ============================================================
# 용도: ArgoCD 싱크 실패 원인을 자동 분류하고 수정 방법 제시
#
# 사용법:
#   diagnose-sync-failure.sh --app observer-prod
#   diagnose-sync-failure.sh --app observer-prod --json
#   diagnose-sync-failure.sh --app observer-prod --json --suggest-fix
#   diagnose-sync-failure.sh --app all --json --suggest-fix
#
# 종료 코드: 0 (문제 없음), 1 (에러 발견), 2 (실행 에러)
# 의존성: kubectl, jq
# ============================================================
set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1" >&2; }

# ============================================================
# 패턴 테이블 정의
# 형식: PATTERN_ID|REGEX|CATEGORY|SEVERITY|AUTO_FIXABLE|DESCRIPTION_KR
# ============================================================
PATTERNS=(
    "PERM_DENIED|resource .+ is not permitted in project|appproject_permission|critical|true|AppProject clusterResourceWhitelist 누락"
    "IMG_PULL_FAIL|ImagePullBackOff|image_pull|high|partial|이미지 Pull 실패 (GHCR 인증 또는 태그 미존재)"
    "IMG_ERR_PULL|ErrImagePull|image_pull|high|partial|이미지 Pull 에러"
    "PVC_NOT_FOUND|PersistentVolumeClaim .+ not found|pvc_missing|high|true|PVC 미생성 또는 바인딩 실패"
    "PV_BOUND_FAIL|persistentvolume .+ not found|pv_missing|high|true|PV 미생성"
    "HELM_TMPL_ERR|helm template error|helm_render|critical|false|Helm 차트 렌더링 실패"
    "HELM_VALUE_ERR|values don.t meet the specifications|helm_render|critical|false|Helm values 파일 오류"
    "NS_NOT_FOUND|namespace .+ not found|namespace_missing|medium|true|네임스페이스 미존재"
    "QUOTA_EXCEEDED|exceeded quota|resource_quota|medium|false|리소스 쿼타 초과"
    "SECRET_NOT_FOUND|secret .+ not found|secret_missing|high|false|Secret 참조 누락"
    "CRB_CONFLICT|clusterrolebinding .+ already exists|resource_conflict|low|false|ClusterRoleBinding 충돌"
    "SYNC_TIMEOUT|timed out waiting|sync_timeout|high|false|싱크 대기 타임아웃"
    "HEALTH_DEGRADED|Degraded|health_degraded|medium|false|앱 상태 Degraded"
    "COMP_ERR|ComparisonError|comparison_error|high|false|리소스 비교 오류"
)

# severity 우선순위 매핑
severity_rank() {
    case "$1" in
        critical) echo 0 ;;
        high)     echo 1 ;;
        medium)   echo 2 ;;
        low)      echo 3 ;;
        *)        echo 9 ;;
    esac
}

# ============================================================
# 사용법 출력
# ============================================================
usage() {
    cat <<'EOF'
사용법: diagnose-sync-failure.sh --app <앱이름|all> [옵션]

옵션:
  --app <name>      진단 대상 ArgoCD 앱 이름 (필수). "all" 지정 시 전체 앱 진단
  --json            JSON 형식으로 진단 보고서 출력
  --suggest-fix     자동 수정 제안 포함
  --help            이 도움말 출력

종료 코드:
  0  진단 완료, 문제 없음 (Synced + Healthy)
  1  진단 완료, 에러 패턴 발견
  2  스크립트 실행 에러 (인자 누락, 도구 미설치 등)

예시:
  diagnose-sync-failure.sh --app observer-prod
  diagnose-sync-failure.sh --app observer-prod --json --suggest-fix
  diagnose-sync-failure.sh --app all --json
EOF
    exit 2
}

# ============================================================
# 인자 파싱
# ============================================================
APP_NAME=""
OUTPUT_FORMAT="text"
SUGGEST_FIX=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --app)
                [[ $# -lt 2 ]] && { log_error "--app 인자에 값이 필요합니다"; usage; }
                APP_NAME="$2"
                shift 2
                ;;
            --json)
                OUTPUT_FORMAT="json"
                shift
                ;;
            --suggest-fix)
                SUGGEST_FIX=true
                shift
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

    if [[ -z "${APP_NAME}" ]]; then
        log_error "--app 인자가 필요합니다"
        usage
    fi
}

# ============================================================
# 의존성 확인
# ============================================================
check_dependencies() {
    local missing=false

    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl이 설치되어 있지 않습니다"
        missing=true
    fi

    if ! command -v jq &>/dev/null; then
        log_error "jq가 설치되어 있지 않습니다"
        missing=true
    fi

    if [[ "${missing}" == true ]]; then
        exit 2
    fi
}

# ============================================================
# 앱 목록 획득 (--app all 지원)
# kubectl로 ArgoCD Application CR 조회
# ============================================================
resolve_app_list() {
    if [[ "${APP_NAME}" == "all" ]]; then
        local apps
        apps=$(kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null) || {
            log_error "ArgoCD 앱 목록 조회 실패. kubectl 접근을 확인하세요"
            exit 2
        }

        if [[ -z "${apps}" ]]; then
            log_warn "등록된 ArgoCD 앱이 없습니다"
            echo ""
            return
        fi

        echo "${apps}" | tr ' ' '\n'
    else
        echo "${APP_NAME}"
    fi
}

# ============================================================
# 앱 상태 수집 (kubectl로 ArgoCD Application CR 조회 - 1회 호출 후 캐싱)
# ============================================================
collect_app_status() {
    local app_name="$1"

    APP_JSON=$(timeout 10 kubectl get application "${app_name}" -n argocd -o json 2>/dev/null) || {
        log_error "앱 '${app_name}' 조회 실패 (kubectl 접근 또는 앱 미존재)"
        return 1
    }

    SYNC_STATUS=$(echo "${APP_JSON}" | jq -r '.status.sync.status // "Unknown"')
    HEALTH_STATUS=$(echo "${APP_JSON}" | jq -r '.status.health.status // "Unknown"')
    OP_PHASE=$(echo "${APP_JSON}" | jq -r '.status.operationState.phase // "N/A"')
    RETRY_COUNT=$(echo "${APP_JSON}" | jq -r '.status.operationState.retryCount // 0')
    REVISION=$(echo "${APP_JSON}" | jq -r '.status.operationState.syncResult.revision // "unknown"')
    LAST_SYNC=$(echo "${APP_JSON}" | jq -r '.status.operationState.finishedAt // "unknown"')
    NAMESPACE=$(echo "${APP_JSON}" | jq -r '.spec.destination.namespace // "default"')
}

# ============================================================
# conditions 메시지 추출
# ============================================================
extract_conditions() {
    echo "${APP_JSON}" | jq -r '.status.conditions[]? | "\(.type): \(.message)"' 2>/dev/null || true
}

# ============================================================
# 실패 리소스 메시지 추출
# ============================================================
extract_failed_resources() {
    echo "${APP_JSON}" | jq -r '
        .status.operationState.syncResult.resources[]? |
        select(.status != "Synced") |
        "\(.kind)/\(.name): \(.status) - \(.message)"' 2>/dev/null || true
}

# ============================================================
# 실패 리소스 상세 정보 (JSON 배열)
# ============================================================
extract_affected_resources_json() {
    echo "${APP_JSON}" | jq '[
        .status.operationState.syncResult.resources[]? |
        select(.status != "Synced") |
        {
            group: (.group // ""),
            kind: .kind,
            name: .name,
            namespace: (.namespace // ""),
            sync_status: .status,
            message: (.message // "")
        }
    ]' 2>/dev/null || echo '[]'
}

# ============================================================
# K8s Warning 이벤트 수집 (보충 정보 - 항상)
# ============================================================
collect_k8s_events() {
    local namespace="$1"

    timeout 10 kubectl get events -n "${namespace}" \
        --sort-by='.lastTimestamp' \
        --field-selector type=Warning \
        -o json 2>/dev/null | jq '[
            .items[-10:][] |
            {
                timestamp: (.lastTimestamp // .eventTime // "unknown"),
                kind: .involvedObject.kind,
                name: .involvedObject.name,
                message: .message
            }
        ]' 2>/dev/null || echo '[]'
}

# ============================================================
# Pod 대기 상태 수집 (IMG_PULL 매칭 시에만)
# ============================================================
collect_pod_status() {
    local namespace="$1"

    timeout 10 kubectl get pods -n "${namespace}" -o json 2>/dev/null | jq -r '
        .items[] |
        select(.status.containerStatuses[]?.state.waiting != null) |
        "\(.metadata.name): \(.status.containerStatuses[].state.waiting.reason) - \(.status.containerStatuses[].state.waiting.message)"' 2>/dev/null || true
}

# ============================================================
# PVC 바인딩 상태 수집 (PVC/PV 매칭 시에만)
# ============================================================
collect_pvc_status() {
    local namespace="$1"

    timeout 10 kubectl get pvc -n "${namespace}" -o json 2>/dev/null | jq -r '
        .items[] |
        select(.status.phase != "Bound") |
        "\(.metadata.name): \(.status.phase)"' 2>/dev/null || true
}

# ============================================================
# 패턴 매칭 엔진
# ============================================================
match_error_patterns() {
    local all_messages="$1"
    local affected_json="$2"

    # 매칭된 패턴을 JSON 배열로 구축
    local matched_json='[]'
    local has_img_pull=false
    local has_pvc_pv=false

    for pattern_entry in "${PATTERNS[@]}"; do
        IFS='|' read -r id regex category severity fixable desc <<< "${pattern_entry}"

        local matched_lines
        matched_lines=$(echo "${all_messages}" | grep -iE "${regex}" 2>/dev/null | head -5 || true)

        if [[ -n "${matched_lines}" ]]; then
            # 매칭된 메시지를 JSON 배열로 변환
            local messages_json
            messages_json=$(echo "${matched_lines}" | jq -R '[., inputs]' 2>/dev/null || echo '[]')

            # 이 패턴과 관련된 리소스 필터링
            local pattern_resources
            pattern_resources=$(echo "${affected_json}" | jq --arg regex "${regex}" '[
                .[] | select(.message | test($regex; "i"))
            ]' 2>/dev/null || echo '[]')

            # auto_fixable 값 처리 (true/false/partial → boolean 또는 string)
            local fixable_json
            case "${fixable}" in
                true)  fixable_json='true' ;;
                false) fixable_json='false' ;;
                *)     fixable_json="\"${fixable}\"" ;;
            esac

            local entry
            entry=$(jq -n \
                --arg id "${id}" \
                --arg category "${category}" \
                --arg severity "${severity}" \
                --argjson fixable "${fixable_json}" \
                --arg desc "${desc}" \
                --argjson messages "${messages_json}" \
                --argjson resources "${pattern_resources}" \
                '{
                    pattern_id: $id,
                    category: $category,
                    severity: $severity,
                    auto_fixable: $fixable,
                    description: $desc,
                    matched_messages: $messages,
                    affected_resources: $resources
                }')

            matched_json=$(echo "${matched_json}" | jq --argjson entry "${entry}" '. + [$entry]')

            # 조건부 수집 플래그
            [[ "${id}" == "IMG_PULL_FAIL" || "${id}" == "IMG_ERR_PULL" ]] && has_img_pull=true
            [[ "${id}" == "PVC_NOT_FOUND" || "${id}" == "PV_BOUND_FAIL" ]] && has_pvc_pv=true
        fi
    done

    # 매칭된 패턴이 없고 Synced가 아닌 경우 → 미분류 에러
    local pattern_count
    pattern_count=$(echo "${matched_json}" | jq 'length')

    if [[ ${pattern_count} -eq 0 ]] && [[ "${SYNC_STATUS}" != "Synced" ]]; then
        local unknown_entry
        unknown_entry=$(jq -n '{
            pattern_id: "UNKNOWN",
            category: "unknown",
            severity: "high",
            auto_fixable: false,
            description: "미분류 에러",
            matched_messages: [],
            affected_resources: []
        }')
        matched_json=$(echo "${matched_json}" | jq --argjson entry "${unknown_entry}" '. + [$entry]')
    fi

    # severity 순 정렬
    matched_json=$(echo "${matched_json}" | jq '
        sort_by(
            if .severity == "critical" then 0
            elif .severity == "high" then 1
            elif .severity == "medium" then 2
            elif .severity == "low" then 3
            else 9 end
        )')

    # 결과 저장
    MATCHED_PATTERNS="${matched_json}"
    HAS_IMG_PULL="${has_img_pull}"
    HAS_PVC_PV="${has_pvc_pv}"
}

# ============================================================
# 수정 제안 생성
# ============================================================
generate_fix_suggestions() {
    local pattern_id="$1"
    local app_name="$2"
    local namespace="$3"

    case "${pattern_id}" in
        PERM_DENIED)
            jq -n --arg app "${app_name}" '{
                pattern_id: "PERM_DENIED",
                description: "project.yaml에 누락 리소스를 clusterResourceWhitelist에 추가",
                auto_fix_command: "auto-fix-sync.sh --diagnosis /tmp/diag.json --apply --auto-commit",
                manual_steps: [
                    "infra/argocd/applications/project.yaml clusterResourceWhitelist에 누락된 kind 추가",
                    "git commit + push 후 ArgoCD 리프레시"
                ]
            }'
            ;;
        NS_NOT_FOUND)
            jq -n --arg ns "${namespace}" '{
                pattern_id: "NS_NOT_FOUND",
                description: "누락된 네임스페이스 생성",
                auto_fix_command: "auto-fix-sync.sh --diagnosis /tmp/diag.json --apply",
                manual_steps: [
                    ("kubectl create namespace " + $ns),
                    ("kubectl label namespace " + $ns + " app.kubernetes.io/part-of=tawbury-platform")
                ]
            }'
            ;;
        PVC_NOT_FOUND|PV_BOUND_FAIL)
            jq -n --arg ns "${namespace}" --arg pid "${pattern_id}" '{
                pattern_id: $pid,
                description: "PV/PVC 상태 확인 및 복구",
                auto_fix_command: "",
                manual_steps: [
                    ("kubectl get pv,pvc -n " + $ns),
                    "Released PV: kubectl patch pv <name> -p \u0027{\"spec\":{\"claimRef\":null}}\u0027",
                    "PV 미존재: argocd app sync <app> 으로 재생성 시도"
                ]
            }'
            ;;
        IMG_PULL_FAIL|IMG_ERR_PULL)
            jq -n --arg pid "${pattern_id}" '{
                pattern_id: $pid,
                description: "이미지 태그 확인 및 롤백 검토",
                auto_fix_command: "",
                manual_steps: [
                    "values-prod.yaml의 image.tag 확인",
                    "GHCR에 해당 태그 존재 여부 확인",
                    "인증 문제 시: ghcr-secret SealedSecret 재생성 (ops/seal-secrets.py)"
                ]
            }'
            ;;
        *)
            jq -n --arg pid "${pattern_id}" '{
                pattern_id: $pid,
                description: "수동 조치 필요",
                auto_fix_command: "",
                manual_steps: ["ArgoCD 대시보드에서 상세 확인"]
            }'
            ;;
    esac
}

# ============================================================
# 앱 진단 실행
# ============================================================
diagnose_app() {
    local app_name="$1"

    # 앱 상태 수집
    if ! collect_app_status "${app_name}"; then
        return 1
    fi

    # operationState가 null인 경우 (한 번도 sync 안 됨)
    if [[ "${OP_PHASE}" == "N/A" ]] && [[ "${SYNC_STATUS}" == "Unknown" ]]; then
        log_warn "앱 '${app_name}': 싱크 이력 없음"
    fi

    # conditions + 실패 리소스 메시지 결합
    local conditions failed_resources all_messages
    conditions=$(extract_conditions)
    failed_resources=$(extract_failed_resources)
    all_messages="${conditions}
${failed_resources}"

    # 실패 리소스 상세 정보
    local affected_json
    affected_json=$(extract_affected_resources_json)

    # 패턴 매칭
    match_error_patterns "${all_messages}" "${affected_json}"

    # 조건부 보충 정보 수집
    local pod_status_info=""
    local pvc_status_info=""

    if [[ "${HAS_IMG_PULL}" == true ]]; then
        pod_status_info=$(collect_pod_status "${NAMESPACE}")
    fi

    if [[ "${HAS_PVC_PV}" == true ]]; then
        pvc_status_info=$(collect_pvc_status "${NAMESPACE}")
    fi

    # K8s Warning 이벤트 수집 (항상)
    local events_json
    events_json=$(collect_k8s_events "${NAMESPACE}")

    # 실패 리소스 요약
    local failed_summary
    failed_summary=$(echo "${affected_json}" | jq '{
        total: length,
        by_kind: (group_by(.kind) | map({key: .[0].kind, value: length}) | from_entries)
    }')

    # 수정 제안 생성 (--suggest-fix 시)
    local fix_suggestions='[]'
    if [[ "${SUGGEST_FIX}" == true ]]; then
        local pattern_ids
        pattern_ids=$(echo "${MATCHED_PATTERNS}" | jq -r '.[].pattern_id')

        while IFS= read -r pid; do
            [[ -z "${pid}" ]] && continue
            local suggestion
            suggestion=$(generate_fix_suggestions "${pid}" "${app_name}" "${NAMESPACE}")
            fix_suggestions=$(echo "${fix_suggestions}" | jq --argjson s "${suggestion}" '. + [$s]')
        done <<< "${pattern_ids}"
    fi

    # 결과 JSON 조립
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z' | sed 's/\(..\)$/:\1/')

    local retry_limit
    retry_limit=$(echo "${APP_JSON}" | jq -r '.spec.syncPolicy.retry.limit // 0')

    local app_report
    app_report=$(jq -n \
        --arg ts "${timestamp}" \
        --arg app "${app_name}" \
        --arg ns "${NAMESPACE}" \
        --arg sync "${SYNC_STATUS}" \
        --arg health "${HEALTH_STATUS}" \
        --arg phase "${OP_PHASE}" \
        --arg last_sync "${LAST_SYNC}" \
        --argjson retry "${RETRY_COUNT}" \
        --arg rev "${REVISION}" \
        --argjson errors "${MATCHED_PATTERNS}" \
        --argjson summary "${failed_summary}" \
        --argjson events "${events_json}" \
        '{
            timestamp: $ts,
            version: "1.0.0",
            app_name: $app,
            namespace: $ns,
            app_status: {
                sync_status: $sync,
                health_status: $health,
                operation_phase: $phase,
                last_sync_at: $last_sync,
                retry_count: $retry,
                revision: $rev
            },
            errors: $errors,
            failed_resources_summary: $summary,
            recent_events: $events
        }')

    # suggest-fix 필드 추가 (플래그 있을 때만)
    if [[ "${SUGGEST_FIX}" == true ]]; then
        app_report=$(echo "${app_report}" | jq --argjson fixes "${fix_suggestions}" '. + {fix_suggestions: $fixes}')
    fi

    echo "${app_report}"
}

# ============================================================
# 텍스트 출력
# ============================================================
output_text() {
    local report="$1"

    local app_count
    app_count=$(echo "${report}" | jq '.results | length')

    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD}ArgoCD 싱크 실패 진단 보고서${NC}"
    echo -e "${BOLD}============================================================${NC}"

    for i in $(seq 0 $((app_count - 1))); do
        local app_report
        app_report=$(echo "${report}" | jq ".results[${i}]")

        local app_name sync health phase retry last_sync
        app_name=$(echo "${app_report}" | jq -r '.app_name')
        sync=$(echo "${app_report}" | jq -r '.app_status.sync_status')
        health=$(echo "${app_report}" | jq -r '.app_status.health_status')
        phase=$(echo "${app_report}" | jq -r '.app_status.operation_phase')
        retry=$(echo "${app_report}" | jq -r '.app_status.retry_count')
        last_sync=$(echo "${app_report}" | jq -r '.app_status.last_sync_at')

        echo ""
        echo -e "앱: ${CYAN}${app_name}${NC}"
        echo -e "시각: $(echo "${app_report}" | jq -r '.timestamp')"
        echo ""

        # 상태
        echo -e "${BOLD}[상태]${NC}"

        local sync_color="${GREEN}"
        [[ "${sync}" != "Synced" ]] && sync_color="${RED}"
        echo -e "  Sync:   ${sync_color}${sync}${NC}"

        local health_color="${GREEN}"
        [[ "${health}" != "Healthy" ]] && health_color="${YELLOW}"
        [[ "${health}" == "Degraded" || "${health}" == "Missing" ]] && health_color="${RED}"
        echo -e "  Health: ${health_color}${health}${NC}"

        local phase_color="${GREEN}"
        [[ "${phase}" == "Failed" || "${phase}" == "Error" ]] && phase_color="${RED}"
        echo -e "  Phase:  ${phase_color}${phase}${NC} (재시도 ${retry}회)"
        echo ""

        # 에러 패턴
        local error_count
        error_count=$(echo "${app_report}" | jq '.errors | length')

        if [[ ${error_count} -gt 0 ]]; then
            echo -e "${BOLD}[에러 패턴]${NC}"

            for j in $(seq 0 $((error_count - 1))); do
                local err
                err=$(echo "${app_report}" | jq ".errors[${j}]")

                local sev pid desc fixable
                sev=$(echo "${err}" | jq -r '.severity')
                pid=$(echo "${err}" | jq -r '.pattern_id')
                desc=$(echo "${err}" | jq -r '.description')
                fixable=$(echo "${err}" | jq -r '.auto_fixable')

                local sev_color="${NC}"
                case "${sev}" in
                    critical) sev_color="${RED}" ;;
                    high)     sev_color="${YELLOW}" ;;
                    medium)   sev_color="${BLUE}" ;;
                esac

                local sev_upper
                sev_upper=$(echo "${sev}" | tr '[:lower:]' '[:upper:]')
                echo -e "  ${sev_color}[${sev_upper}]${NC} ${desc} (${pid})"

                # 매칭된 메시지 (최대 3건 표시)
                echo "${err}" | jq -r '.matched_messages[:3][] | "    → \(.)"'

                # 영향 리소스 수
                local res_count
                res_count=$(echo "${err}" | jq '.affected_resources | length')
                if [[ ${res_count} -gt 0 ]]; then
                    local first_res
                    first_res=$(echo "${err}" | jq -r '.affected_resources[0] | "\(.kind)/\(.name)"')
                    if [[ ${res_count} -gt 1 ]]; then
                        echo -e "    → 영향 리소스: ${first_res} 외 $((res_count - 1))건"
                    else
                        echo -e "    → 영향 리소스: ${first_res}"
                    fi
                fi

                local fix_label="X"
                [[ "${fixable}" == "true" ]] && fix_label="O"
                [[ "${fixable}" == "partial" ]] && fix_label="부분적"
                echo -e "    → 자동 수정 가능: ${fix_label}"
                echo ""
            done
        else
            echo -e "${GREEN}[OK]${NC} 에러 패턴 없음 (Synced + Healthy)"
            echo ""
        fi

        # 실패 리소스 요약
        local total_failed
        total_failed=$(echo "${app_report}" | jq '.failed_resources_summary.total')
        if [[ ${total_failed} -gt 0 ]]; then
            echo -e "${BOLD}[실패 리소스 요약]${NC}"
            echo "  총 ${total_failed}건 실패"
            echo "${app_report}" | jq -r '.failed_resources_summary.by_kind | to_entries[] | "  - \(.key): \(.value)건"'
            echo ""
        fi

        # 수정 제안
        if [[ "${SUGGEST_FIX}" == true ]]; then
            local fix_count
            fix_count=$(echo "${app_report}" | jq '.fix_suggestions | length')
            if [[ ${fix_count} -gt 0 ]]; then
                echo -e "${BOLD}[수정 제안]${NC}"
                for k in $(seq 0 $((fix_count - 1))); do
                    local fix
                    fix=$(echo "${app_report}" | jq ".fix_suggestions[${k}]")

                    local fix_desc fix_cmd
                    fix_desc=$(echo "${fix}" | jq -r '.description')
                    fix_cmd=$(echo "${fix}" | jq -r '.auto_fix_command')

                    echo "  $((k + 1)). ${fix_desc}"
                    if [[ -n "${fix_cmd}" ]]; then
                        echo "     \$ ${fix_cmd}"
                    fi

                    echo "${fix}" | jq -r '.manual_steps[]? | "     - \(.)"'
                done
                echo ""
            fi
        fi

        if [[ ${i} -lt $((app_count - 1)) ]]; then
            echo "------------------------------------------------------------"
        fi
    done

    echo -e "${BOLD}============================================================${NC}"
}

# ============================================================
# 메인 실행
# ============================================================
main() {
    parse_args "$@"
    check_dependencies

    log_step "ArgoCD 싱크 실패 진단 시작: ${APP_NAME}"

    # 앱 목록 획득
    local app_list
    app_list=$(resolve_app_list)

    if [[ -z "${app_list}" ]]; then
        if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
            jq -n '{diagnosis: {results: [], total_errors: 0}}'
        else
            log_info "진단 대상 앱 없음"
        fi
        exit 0
    fi

    # 앱별 진단 실행
    local all_results='[]'
    local total_errors=0
    local has_errors=false

    while IFS= read -r app; do
        [[ -z "${app}" ]] && continue

        log_step "앱 진단 중: ${app}"

        local result
        result=$(diagnose_app "${app}") || {
            log_warn "앱 '${app}' 진단 실패 (스킵)"
            continue
        }

        all_results=$(echo "${all_results}" | jq --argjson r "${result}" '. + [$r]')

        local err_count
        err_count=$(echo "${result}" | jq '.errors | length')
        total_errors=$((total_errors + err_count))

        if [[ ${err_count} -gt 0 ]]; then
            has_errors=true
        fi
    done <<< "${app_list}"

    # 전체 보고서 조립
    local report
    report=$(jq -n \
        --argjson results "${all_results}" \
        --argjson total "${total_errors}" \
        '{
            diagnosis: {
                results: $results,
                total_errors: $total
            }
        }')

    # 출력
    if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
        echo "${report}" | jq .
    else
        output_text "$(echo "${report}" | jq '.diagnosis')"
    fi

    # 종료 코드
    if [[ "${has_errors}" == true ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
