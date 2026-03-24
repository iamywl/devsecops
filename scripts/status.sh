#!/bin/bash
# =============================================================================
# tart 클러스터 전체 상태 확인
# =============================================================================
set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# VM 상태
section "tart VM 상태"
tart list | grep -E "^local" | while read -r line; do
    echo "  $line"
done

# 클러스터별 상태
for cluster in platform dev staging prod; do
    kc="$PROJECT_ROOT/kubeconfig/${cluster}.yaml"
    if [[ -f "$kc" ]]; then
        section "${cluster} 클러스터"
        kubectl get nodes --kubeconfig "$kc" 2>/dev/null || echo "  (연결 불가)"
        echo ""
        kubectl get pods -A --kubeconfig "$kc" 2>/dev/null | head -20 || true
    fi
done

# 보안 상태
section "보안 상태"
prod_kc="$PROJECT_ROOT/kubeconfig/prod.yaml"
if [[ -f "$prod_kc" ]]; then
    echo "Gatekeeper 정책 위반:"
    kubectl get constraints -A --kubeconfig "$prod_kc" 2>/dev/null || echo "  (Gatekeeper 미설치)"
    echo ""
    echo "Trivy 취약점 보고서:"
    kubectl get vulnerabilityreports -A --kubeconfig "$prod_kc" 2>/dev/null | head -10 || echo "  (Trivy 미설치)"
fi

echo ""
