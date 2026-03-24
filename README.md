# DevSecOps Homelab Platform

Apple Silicon(M4 Max) + tart 가상화 기반 4-클러스터 K8s 환경에서
프로덕션 수준의 DevSecOps 파이프라인을 구축하고 운영한다.

---

## 인프라 개요

tart VM 10대로 4개 K8s 클러스터를 운영한다.

| 클러스터 | 역할 | 노드 | CPU | RAM | Pod CIDR |
|----------|------|------|-----|-----|----------|
| **platform** | 관리/관측 (Prometheus, Grafana, ArgoCD, Jenkins) | 3 | 7 | 24GB | 10.10.0.0/16 |
| **dev** | 개발/테스트 (Istio, HPA, 데모앱, Trivy) | 2 | 4 | 12GB | 10.20.0.0/16 |
| **staging** | 프로덕션 전 검증 | 2 | 4 | 12GB | 10.30.0.0/16 |
| **prod** | 운영 (Gatekeeper, Sealed Secrets, Velero, Harbor) | 3 | 6 | 20GB | 10.40.0.0/16 |

**합계: 10 VM / 21 vCPU / 68 GB RAM**

### 아키텍처

```
MacBook Pro (M4 Max, 128GB RAM)
│
├── tart hypervisor (ARM64 VM)
│   ├── platform-master ─┐
│   ├── platform-worker1 ├─ platform 클러스터 (Prometheus, Grafana, ArgoCD, Jenkins, Vault)
│   ├── platform-worker2 ─┘
│   ├── dev-master ──────┐
│   ├── dev-worker1 ─────┘ dev 클러스터 (Istio, Cilium, HPA, Trivy Operator)
│   ├── staging-master ──┐
│   ├── staging-worker1 ─┘ staging 클러스터 (프로덕션 전 검증)
│   ├── prod-master ─────┐
│   ├── prod-worker1 ────┤ prod 클러스터 (Gatekeeper, Sealed Secrets, Velero, Harbor)
│   └── prod-worker2 ────┘
│
├── CI/CD Pipeline (GitHub Actions → Jenkins → ArgoCD)
│   └── Lint → Test → Trivy Scan → Build → Deploy (dev → staging → prod)
│
└── DevSecOps Layers
    ├── Trivy Operator (이미지 취약점 지속 스캔)
    ├── OPA Gatekeeper (정책 위반 배포 차단)
    ├── Sealed Secrets (시크릿 암호화)
    ├── Vault (시크릿 중앙 관리)
    ├── CiliumNetworkPolicy (L3/L4/L7 제로트러스트)
    ├── RBAC (최소 권한 원칙)
    └── Velero (백업/DR)
```

### 기술 스택

| 범주 | 도구 |
|------|------|
| 가상화 | tart 2.31 (Apple Silicon 네이티브) |
| OS | Ubuntu ARM64 (ghcr.io/cirruslabs/ubuntu) |
| CNI | Cilium eBPF + Hubble (kube-proxy 대체) |
| 서비스메시 | Istio (mTLS, 카나리 배포, 서킷브레이커) |
| 모니터링 | Prometheus + Grafana + Loki + AlertManager |
| CI/CD | Jenkins + ArgoCD (GitOps) |
| 보안 스캔 | Trivy Operator (클러스터 내), Trivy CLI (로컬) |
| 정책 엔진 | OPA Gatekeeper |
| 시크릿 | Sealed Secrets + HashiCorp Vault |
| 백업/DR | Velero + etcd 스냅샷 |
| 레지스트리 | Harbor (프라이빗 컨테이너 레지스트리) |
| IaC | Terraform 1.5 + Ansible 2.18 |
| 패키지 | Helm 3.17 |
| 대시보드 | React + Vite |

---

## 사전 준비

```bash
# tart (Apple Silicon VM)
brew install cirruslabs/cli/tart

# K8s 도구
brew install kubectl helm

# IaC
brew install hashicorp/tap/terraform ansible

# 보안
brew install trivy

# 기타
brew install sshpass node
```

---

## 빠른 시작

```bash
# 1. VM 시작 + kubeconfig 수집 + 보안 도구 배포 (전체 자동화)
./scripts/setup.sh

# 2. 상태 확인
./scripts/status.sh

# 3. 보안 스캔
./scripts/scan.sh
```

## 단계별 실습

### Step 1. tart VM 시작

```bash
# 전체 VM 시작
./scripts/setup.sh --step vms

# 개별 VM 시작
tart run dev-master --net-softnet-allow=0.0.0.0/0 &
tart run dev-worker1 --net-softnet-allow=0.0.0.0/0 &

# IP 확인
tart ip dev-master
tart ip dev-worker1
```

### Step 2. kubeconfig 수집

```bash
./scripts/setup.sh --step config

# 수동으로 할 경우:
sshpass -p admin scp admin@$(tart ip dev-master):/etc/kubernetes/admin.conf kubeconfig/dev.yaml
kubectl --kubeconfig kubeconfig/dev.yaml get nodes
```

### Step 3. Terraform으로 보안 리소스 프로비저닝

```bash
cd infrastructure/terraform
terraform init
terraform plan    # devsecops 네임스페이스, RBAC, NetworkPolicy 등
terraform apply
```

### Step 4. Ansible로 보안 도구 배포

```bash
cd infrastructure/ansible

# Trivy Operator (dev + prod)
ansible-playbook playbooks/setup-cluster.yml --tags "trivy"

# OPA Gatekeeper (prod)
ansible-playbook playbooks/setup-cluster.yml --tags "gatekeeper"

# Vault (platform)
ansible-playbook playbooks/setup-cluster.yml --tags "vault"
```

### Step 5. 대시보드 배포

```bash
cd dashboard && npm install && npm run build && cd ..

# dev 클러스터에 배포
kubectl apply -k kubernetes/overlays/dev/ --kubeconfig kubeconfig/dev.yaml
```

### Step 6. 보안 스캔

```bash
# 로컬 스캔 (이미지, 매니페스트, Dockerfile)
./scripts/scan.sh

# 클러스터 내 Trivy Operator 보고서
kubectl get vulnerabilityreports -A --kubeconfig kubeconfig/dev.yaml

# Gatekeeper 정책 위반 확인
kubectl get constraints -A --kubeconfig kubeconfig/prod.yaml
```

### Step 7. 서비스 접속

```bash
PLATFORM_IP=$(tart ip platform-worker1)

echo "Grafana:      http://$PLATFORM_IP:30300  (admin/admin)"
echo "ArgoCD:       http://$PLATFORM_IP:30800"
echo "Jenkins:      http://$PLATFORM_IP:30900"
echo "AlertManager: http://$PLATFORM_IP:30903"
echo "Harbor:       http://$PLATFORM_IP:30400  (admin/Harbor12345)"
```

---

## 디렉토리 구조

```
devsecops/
├── config/
│   └── clusters.json                  # 4-클러스터 VM 구성 (Single Source of Truth)
├── infrastructure/
│   ├── terraform/                     # 네임스페이스, RBAC, NetworkPolicy (멀티클러스터)
│   └── ansible/                       # Trivy, Gatekeeper, Vault 배포
├── kubernetes/
│   ├── base/                          # 공통 매니페스트
│   ├── overlays/{dev,staging,prod}/   # 환경별 Kustomize 오버레이
│   ├── policies/                      # OPA Gatekeeper 정책
│   └── monitoring/                    # Prometheus 알럿 규칙
├── ci/
│   └── argocd-app.yml                 # ArgoCD Application (GitOps)
├── .github/workflows/
│   └── ci.yml                         # GitHub Actions CI 파이프라인
├── scripts/
│   ├── setup.sh                       # 환경 구성 (VM 시작 → 보안 도구 배포)
│   ├── status.sh                      # 4-클러스터 상태 확인
│   ├── scan.sh                        # Trivy 보안 스캔
│   └── teardown.sh                    # 리소스 정리
├── dashboard/                         # React 대시보드 (4-클러스터 시각화)
└── blogs/                             # 개발 기록, 실습 가이드, 트러블슈팅
```

---

## 블로그

| 번호 | 제목 | 내용 |
|------|------|------|
| 001 | [프로젝트 킥오프](blogs/001-project-kickoff.md) | tart 4-클러스터 설계 배경 |
| 002 | [Terraform 실습](blogs/002-terraform-hands-on.md) | 멀티클러스터 IaC |
| 003 | [Kubernetes 실습](blogs/003-kubernetes-hands-on.md) | tart에서의 K8s 운영 |
| 004 | [DevSecOps 실습](blogs/004-devsecops-hands-on.md) | Trivy, Gatekeeper, Vault |
