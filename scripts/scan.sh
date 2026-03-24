#!/bin/bash
# =============================================================================
# 보안 스캔: 이미지, 매니페스트, 클러스터 취약점
# =============================================================================
set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAN_TYPE="${1:-all}"

section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

if ! command -v trivy >/dev/null 2>&1; then
    echo -e "${RED}trivy 미설치. brew install trivy${NC}"
    exit 1
fi

scan_image() {
    section "Docker 이미지 취약점 스캔"
    if docker images dashboard:dev --format "{{.ID}}" 2>/dev/null | head -1 | grep -q .; then
        trivy image --severity HIGH,CRITICAL dashboard:dev
    else
        echo "dashboard:dev 이미지 없음. 빌드 먼저: cd dashboard && docker build -t dashboard:dev ."
    fi
}

scan_config() {
    section "K8s 매니페스트 보안 스캔"
    trivy config "$PROJECT_ROOT/kubernetes/"

    section "Dockerfile 보안 스캔"
    trivy config "$PROJECT_ROOT/dashboard/Dockerfile" 2>/dev/null || true

    section "Terraform 설정 스캔"
    trivy config "$PROJECT_ROOT/infrastructure/terraform/"
}

scan_cluster() {
    section "클러스터 내 Trivy Operator 보고서"
    for cluster in dev prod; do
        kc="$PROJECT_ROOT/kubeconfig/${cluster}.yaml"
        if [[ -f "$kc" ]]; then
            echo -e "\n${cluster} 클러스터:"
            kubectl get vulnerabilityreports -A --kubeconfig "$kc" 2>/dev/null | head -15 || echo "  (Trivy Operator 미설치)"
        fi
    done
}

case "$SCAN_TYPE" in
    --image)   scan_image ;;
    --config)  scan_config ;;
    --cluster) scan_cluster ;;
    all)       scan_config; scan_image; scan_cluster ;;
    *)         echo "사용법: $0 [--image|--config|--cluster|all]"; exit 1 ;;
esac

echo -e "\n${GREEN}스캔 완료.${NC}"
