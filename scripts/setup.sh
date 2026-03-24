#!/bin/bash
# =============================================================================
# tart 기반 DevSecOps 환경 설정
#
# 기존 tart 4-클러스터(10 VM)가 실행 중인 상태에서
# DevSecOps 보안 도구를 추가 배포한다.
#
# 사용법:
#   ./scripts/setup.sh              # 전체 설정
#   ./scripts/setup.sh --step vms   # VM 시작만
#   ./scripts/setup.sh --step infra # Terraform만
#   ./scripts/setup.sh --step sec   # 보안 도구만
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$PROJECT_ROOT/config/clusters.json"

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

STEP="${2:-all}"
[[ "${1:-}" == "--step" ]] && STEP="$2"

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: tart VM 시작
# ─────────────────────────────────────────────────────────────────────────────
start_vms() {
    log_info "tart VM 시작 중..."

    local vms=(
        platform-master platform-worker1 platform-worker2
        dev-master dev-worker1
        staging-master staging-worker1
        prod-master prod-worker1 prod-worker2
    )

    for vm in "${vms[@]}"; do
        if tart list | grep -q "$vm.*running"; then
            log_ok "$vm 이미 실행 중"
        else
            log_info "$vm 시작..."
            tart run "$vm" --net-softnet-allow=0.0.0.0/0 &
            sleep 1
        fi
    done

    log_info "VM SSH 대기 중..."
    for vm in "${vms[@]}"; do
        local ip=""
        for i in $(seq 1 60); do
            ip=$(tart ip "$vm" 2>/dev/null || true)
            [[ -n "$ip" ]] && break
            sleep 3
        done
        if [[ -n "$ip" ]]; then
            log_ok "$vm → $ip"
        else
            log_error "$vm IP를 가져올 수 없음"
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: kubeconfig 수집
# ─────────────────────────────────────────────────────────────────────────────
collect_kubeconfigs() {
    log_info "kubeconfig 수집 중..."
    mkdir -p "$PROJECT_ROOT/kubeconfig"

    for cluster in platform dev staging prod; do
        local master_ip
        master_ip=$(tart ip "${cluster}-master" 2>/dev/null || true)
        if [[ -z "$master_ip" ]]; then
            log_warn "${cluster}-master IP를 가져올 수 없음. 건너뜀."
            continue
        fi

        sshpass -p admin scp -o StrictHostKeyChecking=no \
            "admin@${master_ip}:/etc/kubernetes/admin.conf" \
            "$PROJECT_ROOT/kubeconfig/${cluster}.yaml" 2>/dev/null || {
            log_warn "${cluster} kubeconfig 수집 실패"
            continue
        }

        # kubeconfig의 server 주소를 실제 IP로 교체
        sed -i '' "s|https://.*:6443|https://${master_ip}:6443|g" \
            "$PROJECT_ROOT/kubeconfig/${cluster}.yaml" 2>/dev/null || true

        log_ok "${cluster} kubeconfig → kubeconfig/${cluster}.yaml"
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Terraform 적용
# ─────────────────────────────────────────────────────────────────────────────
provision_infra() {
    log_info "Terraform 초기화 및 적용..."
    cd "$PROJECT_ROOT/infrastructure/terraform"
    terraform init -input=false
    terraform apply -auto-approve
    terraform output
    cd "$PROJECT_ROOT"
    log_ok "인프라 프로비저닝 완료"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: 보안 도구 배포
# ─────────────────────────────────────────────────────────────────────────────
deploy_security() {
    log_info "보안 도구 배포 중..."
    cd "$PROJECT_ROOT/infrastructure/ansible"
    ansible-playbook playbooks/setup-cluster.yml
    cd "$PROJECT_ROOT"
    log_ok "보안 도구 배포 완료"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: 대시보드 앱 배포
# ─────────────────────────────────────────────────────────────────────────────
deploy_app() {
    log_info "대시보드 앱 배포 (dev 클러스터)..."

    local dev_worker_ip
    dev_worker_ip=$(tart ip dev-worker1 2>/dev/null || true)

    if [[ -z "$dev_worker_ip" ]]; then
        log_warn "dev-worker1 IP를 가져올 수 없음. 앱 배포 건너뜀."
        return
    fi

    # dev-worker1에서 이미지 빌드
    cd "$PROJECT_ROOT/dashboard"
    docker build -t dashboard:dev .
    docker save dashboard:dev | sshpass -p admin ssh -o StrictHostKeyChecking=no \
        "admin@${dev_worker_ip}" "sudo ctr -n k8s.io images import -" 2>/dev/null || {
        log_warn "이미지 전송 실패. 로컬 레지스트리 또는 Harbor를 사용하세요."
    }
    cd "$PROJECT_ROOT"

    kubectl apply -k kubernetes/overlays/dev/ \
        --kubeconfig "$PROJECT_ROOT/kubeconfig/dev.yaml" 2>/dev/null || true

    log_ok "앱 배포 완료"
}

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "======================================"
echo "  DevSecOps on Tart (4-Cluster)"
echo "======================================"
echo ""

case "$STEP" in
    vms)      start_vms ;;
    config)   collect_kubeconfigs ;;
    infra)    provision_infra ;;
    sec)      deploy_security ;;
    app)      deploy_app ;;
    all)
        start_vms
        collect_kubeconfigs
        provision_infra
        deploy_security
        deploy_app
        ;;
    *)
        log_error "알 수 없는 단계: $STEP"
        echo "사용법: $0 [--step vms|config|infra|sec|app|all]"
        exit 1
        ;;
esac

echo ""
log_ok "설정 완료!"
echo ""
echo "서비스 접속 (platform-worker1 NodePort):"
echo "  Grafana:      http://\$(tart ip platform-worker1):30300  (admin/admin)"
echo "  ArgoCD:       http://\$(tart ip platform-worker1):30800"
echo "  Jenkins:      http://\$(tart ip platform-worker1):30900"
echo "  AlertManager: http://\$(tart ip platform-worker1):30903"
echo "  Harbor:       http://\$(tart ip platform-worker1):30400  (admin/Harbor12345)"
echo ""
echo "클러스터 접근:"
echo "  kubectl --kubeconfig kubeconfig/dev.yaml get pods -A"
echo "  kubectl --kubeconfig kubeconfig/prod.yaml get constraints"
echo ""
