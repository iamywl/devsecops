#!/bin/bash
# =============================================================================
# DevSecOps 리소스 정리 (VM은 삭제하지 않음)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo -e "${RED}경고: DevSecOps 네임스페이스와 보안 도구를 삭제합니다.${NC}"
echo -e "${RED}tart VM은 삭제하지 않습니다.${NC}"
echo -n "계속하시겠습니까? (yes/no): "
read -r confirm
if [[ "$confirm" != "yes" ]]; then
    echo "취소됨."
    exit 0
fi

for cluster in dev staging prod; do
    kc="$PROJECT_ROOT/kubeconfig/${cluster}.yaml"
    [[ ! -f "$kc" ]] && continue

    echo "[${cluster}] devsecops 네임스페이스 삭제..."
    kubectl delete namespace devsecops --kubeconfig "$kc" --ignore-not-found 2>/dev/null || true
done

# Terraform state 정리
cd "$PROJECT_ROOT/infrastructure/terraform"
if [[ -f "terraform.tfstate" ]]; then
    terraform destroy -auto-approve 2>/dev/null || true
fi
rm -f terraform.tfstate terraform.tfstate.backup
rm -rf .terraform
cd "$PROJECT_ROOT"

echo -e "${GREEN}정리 완료.${NC}"
