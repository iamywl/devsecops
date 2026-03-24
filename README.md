# DevSecOps Homelab Platform

Apple Silicon(M4 Max) + tart 가상화 기반 4-클러스터 K8s 환경에서
DevSecOps 파이프라인을 구축하고 운영한다.

---

## 실행 환경 구분

이 프로젝트는 **macOS 호스트**와 **tart VM** 두 계층에서 동작한다.
어떤 명령이 어디에서 실행되는지 명확히 구분해야 한다.

```
┌─────────────────────────────────────────────────────────────────┐
│ macOS 호스트 (M4 Max, 128GB RAM)                                │
│                                                                  │
│  실행하는 것:                                                     │
│  - tart (VM 생성/시작/중지)                                       │
│  - terraform (kubeconfig 경로로 원격 K8s API 호출)                │
│  - ansible-playbook (kubeconfig 경로로 helm/kubectl 실행)         │
│  - kubectl --kubeconfig kubeconfig/dev.yaml (원격 API 서버 호출)  │
│  - trivy (로컬 이미지/매니페스트 스캔)                             │
│  - docker build (이미지 빌드)                                     │
│  - npm run dev (대시보드 개발 서버)                                │
│  - sshpass + ssh/scp (VM에 명령 전달, 파일 복사)                  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ tart VM (Ubuntu ARM64, 10대)                               │  │
│  │                                                            │  │
│  │  실행되는 것:                                               │  │
│  │  - kubelet, kube-apiserver, etcd (K8s 컴포넌트)            │  │
│  │  - containerd (컨테이너 런타임)                             │  │
│  │  - cilium-agent (CNI, 네트워크 정책 집행)                   │  │
│  │  - Pod (앱 컨테이너: nginx, prometheus, argocd 등)         │  │
│  │                                                            │  │
│  │  macOS에서 SSH로 접근:                                      │  │
│  │    sshpass -p admin ssh admin@$(tart ip dev-master)        │  │
│  └────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

**핵심**: `kubectl`, `terraform`, `ansible`, `trivy`, `docker`는 모두 **macOS에서 실행**한다.
이 도구들이 네트워크를 통해 tart VM 안의 K8s API 서버에 접속한다.
VM 안에 직접 들어가서 작업하는 경우는 디버깅 시 SSH 접속뿐이다.

---

## 인프라 구성

### 4-클러스터 / 10 VM

| 클러스터 | 역할 | 노드 | CPU | RAM | Pod CIDR |
|----------|------|------|-----|-----|----------|
| **platform** | 관리/관측 전용 | master(2C/4G) + worker1(3C/12G) + worker2(2C/8G) | 7 | 24GB | 10.10.0.0/16 |
| **dev** | 개발/테스트 | master(2C/4G) + worker1(2C/8G) | 4 | 12GB | 10.20.0.0/16 |
| **staging** | 배포 전 검증 | master(2C/4G) + worker1(2C/8G) | 4 | 12GB | 10.30.0.0/16 |
| **prod** | 운영 | master(2C/4G) + worker1(2C/8G) + worker2(2C/8G) | 6 | 20GB | 10.40.0.0/16 |

합계: **10 VM / 21 vCPU / 68 GB RAM**

### 클러스터별 설치된 컴포넌트

| 컴포넌트 | platform | dev | staging | prod |
|----------|----------|-----|---------|------|
| Cilium eBPF + Hubble | O | O | O | O |
| Prometheus + Grafana + Loki | O | - | - | - |
| AlertManager | O | - | - | - |
| ArgoCD | O | - | - | - |
| Jenkins | O | - | - | - |
| Vault | O | - | - | - |
| Istio (서비스메시) | - | O | - | - |
| metrics-server + HPA | - | O | - | - |
| Trivy Operator | - | O | - | O |
| OPA Gatekeeper | - | - | - | O |
| Sealed Secrets | - | - | - | O |
| Velero (백업) | - | - | - | O |
| Harbor (레지스트리) | - | - | - | O |

### 아키텍처

```
macOS 호스트
├── tart hypervisor
│   ├── platform 클러스터 (Prometheus, Grafana, ArgoCD, Jenkins, Vault)
│   ├── dev 클러스터 (Istio, Cilium, HPA, Trivy Operator)
│   ├── staging 클러스터 (배포 검증)
│   └── prod 클러스터 (Gatekeeper, Sealed Secrets, Velero, Harbor)
│
├── CI/CD 흐름 (Jenkins on platform → ArgoCD → 각 클러스터)
│   └── Lint → Test → Trivy Scan → Build → Push to Harbor → ArgoCD Sync
│
└── DevSecOps 보안 레이어
    ├── [스캔] Trivy Operator: 클러스터 내 이미지 취약점 지속 감시
    ├── [정책] OPA Gatekeeper: prod 배포 시 정책 위반 자동 차단
    ├── [네트워크] CiliumNetworkPolicy: L3/L4/L7 제로트러스트
    ├── [시크릿] Sealed Secrets + Vault: 암호화 + 중앙 관리
    ├── [접근] RBAC: 서비스 어카운트별 최소 권한
    └── [복구] Velero + etcd 스냅샷: 백업/DR
```

---

## 전제 조건

이 프로젝트는 **IaC_apple_sillicon 프로젝트가 구축한 tart VM 10대** 위에서 동작한다.
VM 생성, K8s 클러스터 초기화, 도구 설치는 IaC_apple_sillicon에서 이미 완료된 상태다.

```bash
# VM 존재 확인
tart list
# platform-master, platform-worker1, platform-worker2,
# dev-master, dev-worker1, staging-master, staging-worker1,
# prod-master, prod-worker1, prod-worker2 가 보여야 한다

# 도구 설치 확인
tart --version && kubectl version --client && terraform --version && ansible --version && trivy --version && helm version
```

---

## 사용법

### 1단계: VM 시작 (macOS에서)

```bash
# 전체 VM 시작
./scripts/setup.sh --step vms

# 또는 개별 시작 (백그라운드 실행)
tart run platform-master --net-softnet-allow=0.0.0.0/0 &
tart run platform-worker1 --net-softnet-allow=0.0.0.0/0 &
tart run platform-worker2 --net-softnet-allow=0.0.0.0/0 &
tart run dev-master --net-softnet-allow=0.0.0.0/0 &
tart run dev-worker1 --net-softnet-allow=0.0.0.0/0 &
# ... 나머지 5대도 동일

# IP 확인 (macOS에서)
tart ip dev-master      # 예: 192.168.64.5
tart ip dev-worker1     # 예: 192.168.64.6
```

`--net-softnet-allow=0.0.0.0/0`는 VM이 호스트 및 다른 VM과 통신할 수 있도록 한다.
이 플래그 없이 실행하면 VM 간 네트워크가 차단된다.

### 2단계: kubeconfig 수집 (macOS에서)

kubectl이 tart VM 안의 K8s API 서버에 접속하려면 kubeconfig가 필요하다.
VM의 master 노드에서 `/etc/kubernetes/admin.conf`를 가져온다.

```bash
# 자동 수집
./scripts/setup.sh --step config

# 수동으로 할 경우:
mkdir -p kubeconfig
DEV_IP=$(tart ip dev-master)
sshpass -p admin scp -o StrictHostKeyChecking=no \
    admin@${DEV_IP}:/etc/kubernetes/admin.conf kubeconfig/dev.yaml

# kubeconfig의 server 주소를 실제 VM IP로 교체
# (kubeadm이 생성한 기본값은 localhost:6443이므로 macOS에서 접근 불가)
sed -i '' "s|https://.*:6443|https://${DEV_IP}:6443|g" kubeconfig/dev.yaml

# 연결 테스트 (macOS에서 실행, VM의 API 서버에 접속)
kubectl --kubeconfig kubeconfig/dev.yaml get nodes
```

### 3단계: Terraform으로 보안 리소스 생성 (macOS에서)

Terraform은 kubeconfig 파일을 통해 **원격으로** 각 클러스터의 API 서버에 접속한다.
VM에 SSH 접속하지 않는다.

```bash
cd infrastructure/terraform
terraform init      # kubernetes 프로바이더 다운로드
terraform plan      # 생성할 리소스 미리보기
terraform apply     # 적용

# 확인 (macOS에서)
kubectl --kubeconfig ../../kubeconfig/dev.yaml get namespace devsecops
kubectl --kubeconfig ../../kubeconfig/dev.yaml get resourcequota -n devsecops
kubectl --kubeconfig ../../kubeconfig/dev.yaml get networkpolicy -n devsecops
kubectl --kubeconfig ../../kubeconfig/prod.yaml get role -n devsecops
```

생성되는 리소스:
- dev/staging/prod 클러스터에 `devsecops` 네임스페이스
- ResourceQuota (환경별 CPU/메모리 상한)
- LimitRange (컨테이너 기본 리소스 제한)
- RBAC Role + RoleBinding + ServiceAccount
- NetworkPolicy (기본 전체 차단 + DNS만 허용)

### 4단계: Ansible로 보안 도구 배포 (macOS에서)

Ansible은 `localhost`에서 `kubectl`/`helm` 명령을 실행한다.
`--kubeconfig` 플래그로 대상 클러스터를 지정하므로, VM에 SSH 접속하지 않는다.

```bash
cd infrastructure/ansible

# 전체 배포
ansible-playbook playbooks/setup-cluster.yml

# 또는 태그별 선택 배포
ansible-playbook playbooks/setup-cluster.yml --tags "trivy"       # Trivy Operator
ansible-playbook playbooks/setup-cluster.yml --tags "gatekeeper"  # OPA Gatekeeper
ansible-playbook playbooks/setup-cluster.yml --tags "vault"       # Vault

# 확인 (macOS에서)
kubectl --kubeconfig ../../kubeconfig/dev.yaml get pods -n trivy-system
kubectl --kubeconfig ../../kubeconfig/prod.yaml get pods -n gatekeeper-system
kubectl --kubeconfig ../../kubeconfig/platform.yaml get pods -n vault
```

### 5단계: 대시보드 앱 빌드 및 배포

**빌드** (macOS에서):
```bash
cd dashboard
npm install
npm run build       # dist/ 디렉토리에 정적 파일 생성
```

**Docker 이미지 빌드** (macOS에서):
```bash
docker build -t dashboard:dev .
```

**이미지를 VM에 전송** (macOS → VM):
tart VM의 containerd는 Docker Hub에서 pull할 수 있지만,
로컬 빌드 이미지는 직접 전송해야 한다.

```bash
# 방법 1: containerd로 직접 import (macOS에서 실행)
docker save dashboard:dev | sshpass -p admin ssh -o StrictHostKeyChecking=no \
    admin@$(tart ip dev-worker1) "sudo ctr -n k8s.io images import -"

# 방법 2: Harbor 레지스트리 사용 (prod 클러스터에 설치됨)
HARBOR_IP=$(tart ip prod-worker1)
docker tag dashboard:dev ${HARBOR_IP}:30500/devsecops/dashboard:dev
docker push ${HARBOR_IP}:30500/devsecops/dashboard:dev
```

**K8s에 배포** (macOS에서):
```bash
kubectl apply -k kubernetes/overlays/dev/ --kubeconfig kubeconfig/dev.yaml
kubectl --kubeconfig kubeconfig/dev.yaml get pods -n devsecops
```

### 6단계: 보안 스캔 (macOS에서)

```bash
# 로컬 스캔 (macOS에서 실행, 로컬 파일/이미지 검사)
./scripts/scan.sh --config     # K8s 매니페스트 + Dockerfile 보안 검사
./scripts/scan.sh --image      # Docker 이미지 취약점 스캔

# 클러스터 내 스캔 결과 조회 (macOS에서 실행, 원격 API 서버 조회)
./scripts/scan.sh --cluster
# 또는 직접:
kubectl --kubeconfig kubeconfig/dev.yaml get vulnerabilityreports -A
kubectl --kubeconfig kubeconfig/prod.yaml get constraints -A
```

### 7단계: 서비스 접속 (macOS 브라우저에서)

platform 클러스터의 서비스는 NodePort로 노출되어 있다.
macOS 브라우저에서 VM IP + NodePort로 접속한다.

```bash
PLATFORM_IP=$(tart ip platform-worker1)

# 각 서비스 URL 출력
echo "Grafana:      http://$PLATFORM_IP:30300  (ID: admin / PW: admin)"
echo "ArgoCD:       http://$PLATFORM_IP:30800"
echo "Jenkins:      http://$PLATFORM_IP:30900"
echo "AlertManager: http://$PLATFORM_IP:30903"
echo "Harbor:       http://$PLATFORM_IP:30400  (ID: admin / PW: Harbor12345)"
```

### 8단계: VM 디버깅 (VM에 SSH 접속)

문제가 발생했을 때만 VM 내부에 접속한다.

```bash
# VM에 SSH 접속 (macOS에서)
sshpass -p admin ssh -o StrictHostKeyChecking=no admin@$(tart ip dev-master)

# VM 내부에서 실행하는 명령:
sudo systemctl status kubelet
sudo journalctl -u kubelet --no-pager -n 50
sudo crictl ps                          # 실행 중인 컨테이너
sudo crictl logs <container-id>         # 컨테이너 로그
sudo cilium status                      # Cilium 상태
```

---

## 디렉토리 구조

```
devsecops/
├── config/
│   └── clusters.json                  # 4-클러스터 VM 구성 (Single Source of Truth)
├── infrastructure/
│   ├── terraform/                     # 네임스페이스, RBAC, NetworkPolicy (멀티클러스터)
│   │   ├── main.tf                    # dev/staging/prod 프로바이더별 리소스 정의
│   │   ├── variables.tf               # kubeconfig 경로 변수
│   │   └── outputs.tf
│   └── ansible/
│       ├── ansible.cfg
│       ├── inventory/hosts.yml        # tart VM 10대 호스트 목록
│       └── playbooks/
│           └── setup-cluster.yml      # Trivy, Gatekeeper, Vault 배포
├── kubernetes/
│   ├── base/                          # 공통 매니페스트 (Deployment, Service, HPA, PDB)
│   ├── overlays/
│   │   ├── dev/kustomization.yml      # replicas=1, 리소스 적게
│   │   ├── staging/kustomization.yml  # replicas=2
│   │   └── prod/kustomization.yml     # replicas=3, 리소스 넉넉
│   ├── policies/                      # OPA Gatekeeper 정책 (prod 적용)
│   │   ├── block-latest-tag.yml       # :latest 태그 금지
│   │   ├── require-labels.yml         # 필수 라벨 강제
│   │   └── block-privileged.yml       # 특권 컨테이너 금지
│   └── monitoring/
│       ├── prometheus-rules.yml       # 알럿 규칙
│       └── grafana-dashboard.json
├── ci/
│   └── argocd-app.yml                 # ArgoCD Application 정의 (GitOps)
├── scripts/                           # 전부 macOS에서 실행
│   ├── setup.sh                       # VM 시작 → kubeconfig 수집 → 보안 도구 배포
│   ├── status.sh                      # 4-클러스터 상태 확인
│   ├── scan.sh                        # Trivy 보안 스캔
│   └── teardown.sh                    # devsecops 리소스 정리 (VM은 유지)
├── dashboard/                         # React 대시보드
│   ├── Dockerfile                     # 멀티스테이지 빌드, non-root nginx
│   ├── nginx.conf
│   └── src/App.jsx                    # 4-클러스터 상태 시각화
└── blogs/                             # 개발 기록, 실습 가이드
    ├── 001-project-kickoff.md
    ├── 002-terraform-hands-on.md
    ├── 003-kubernetes-hands-on.md
    └── 004-devsecops-hands-on.md
```

---

## 블로그

| 번호 | 제목 | 내용 |
|------|------|------|
| 001 | [프로젝트 킥오프](blogs/001-project-kickoff.md) | tart 4-클러스터 설계 배경 |
| 002 | [Terraform 실습](blogs/002-terraform-hands-on.md) | 멀티클러스터 IaC |
| 003 | [Kubernetes 실습](blogs/003-kubernetes-hands-on.md) | tart에서의 K8s 운영 |
| 004 | [DevSecOps 실습](blogs/004-devsecops-hands-on.md) | Trivy, Gatekeeper, Vault |
