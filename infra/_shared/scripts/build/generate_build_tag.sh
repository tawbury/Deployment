#!/bin/bash
#################################################################################
# Observer Build Tag Generator
# 용도: Docker 빌드 시점에 자동으로 타임스탬프 기반 태그 생성
# 형식: YYMMDD-HHMMSS (예: 20260126-155945)
# 버전: v1.0.0
#################################################################################

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 로깅 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 태그 생성 함수
generate_tag() {
    local timestamp
    local tag
    
    # 현재 시간으로 타임스탬프 생성 (KST)
    timestamp=$(date '+%Y%m%d-%H%M%S')
    
    # YYMMDD-HHMMSS 형식으로 변환 (20YYMMDD-HHMMSS)
    tag="20${timestamp:2:6}-${timestamp:9:6}"
    
    echo "$tag"
}

# 태그 검증 함수
validate_tag() {
    local tag="$1"
    
    # 정규식 검증: 20YYMMDD-HHMMSS
    if [[ ! "$tag" =~ ^20[0-9]{6}-[0-9]{6}$ ]]; then
        log_error "Invalid tag format: $tag"
        log_error "Expected format: 20YYMMDD-HHMMSS (e.g., 20260126-155945)"
        return 1
    fi
    
    # 날짜/시간 유효성 검증
    local date_part="${tag:0:8}"
    local time_part="${tag:9:6}"
    
    # 날짜 검증 (YYYYMMDD)
    if ! date -d "${date_part:0:4}-${date_part:4:2}-${date_part:6:2}" >/dev/null 2>&1; then
        log_error "Invalid date: $date_part"
        return 1
    fi
    
    # 시간 검증 (HHMMSS)
    local hour="${time_part:0:2}"
    local minute="${time_part:2:2}"
    local second="${time_part:4:2}"
    
    if [[ "$hour" -gt 23 ]] || [[ "$minute" -gt 59 ]] || [[ "$second" -gt 59 ]]; then
        log_error "Invalid time: $time_part"
        return 1
    fi
    
    return 0
}

# 메인 함수
main() {
    local tag
    local output_file="${1:-}"
    
    log_info "=== Observer Build Tag Generator ==="
    
    # 태그 생성
    tag=$(generate_tag)
    log_info "Generated tag: $tag"
    
    # 태그 검증
    if ! validate_tag "$tag"; then
        log_error "Tag validation failed"
        exit 1
    fi
    
    log_info "✅ Tag validation passed: $tag"
    
    # 출력 파일이 지정된 경우 파일에 저장
    if [[ -n "$output_file" ]]; then
        mkdir -p "$(dirname "$output_file")"
        echo "$tag" > "$output_file"
        log_info "✅ Tag saved to: $output_file"
    fi
    
    # 표준 출력으로 태그 출력 (다른 스크립트에서 사용)
    echo "$tag"
    
    log_info "=== Tag Generation Complete ==="
}

# 인자 처리
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
