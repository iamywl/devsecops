# 002. Terraform 실습 — 멀티클러스터 IaC

**날짜**: 2025-03-24

---

## 실행 환경

**Terraform은 macOS에서 실행한다.**
kubeconfig 파일을 통해 tart VM 안의 K8s API 서버에 원격 접속한다.
VM에 SSH 접속하지 않는다.

```
macOS (terraform apply)
  → kubeconfig/dev.yaml 읽음
  → https://<dev-master IP>:6443 으로 API 호출
  → dev 클러스터에 네임스페이스 생성
```

## 멀티클러스터 프로바이더 구조

단일 클러스터와 달리, 4-클러스터 환경에서는 프로바이더를 alias로 분리한다.

```hcl
# infrastructure/terraform/main.tf

provider "kubernetes" {
  alias       = "dev"
  config_path = var.kubeconfig_dev      # kubeconfig/dev.yaml
}

provider "kubernetes" {
  alias       = "prod"
  config_path = var.kubeconfig_prod     # kubeconfig/prod.yaml
}

# 리소스 생성 시 대상 클러스터를 명시한다
resource "kubernetes_namespace" "dev_apps" {
  provider = kubernetes.dev             # ← dev 클러스터에 생성
  metadata { name = "devsecops" }
}

resource "kubernetes_namespace" "prod_apps" {
  provider = kubernetes.prod            # ← prod 클러스터에 생성
  metadata { name = "devsecops" }
}
```

## 실습 (macOS에서 실행)

```bash
cd infrastructure/terraform

# 1. 초기화: kubernetes 프로바이더 다운로드
terraform init

# 2. 계획: 무엇이 생성되는지 확인
terraform plan
# Plan: 12 to add
#   + kubernetes_namespace.dev_apps
#   + kubernetes_resource_quota.dev_quota
#   + kubernetes_limit_range.dev_limits
#   + kubernetes_role.dev_deployer
#   + kubernetes_network_policy.dev_default_deny
#   ...

# 3. 적용
terraform apply

# 4. 결과 확인 (macOS에서 kubectl로 원격 확인)
kubectl --kubeconfig ../../kubeconfig/dev.yaml get namespace devsecops
kubectl --kubeconfig ../../kubeconfig/dev.yaml get resourcequota -n devsecops
kubectl --kubeconfig ../../kubeconfig/prod.yaml get networkpolicy -n devsecops
```

## 환경별 차등 리소스

```hcl
# dev: 개발 환경이므로 제한이 느슨하다
"requests.cpu"    = "2"
"requests.memory" = "4Gi"
"pods"            = "30"

# prod: 운영 환경이므로 제한이 넉넉하지만 상한이 있다
"requests.cpu"    = "4"
"requests.memory" = "8Gi"
"pods"            = "50"
```

## 트러블슈팅

### "Unable to connect to the server"

원인: VM이 꺼져 있거나, kubeconfig의 server IP가 현재 VM IP와 다르다.

```bash
# 1. VM 실행 확인 (macOS에서)
tart list | grep dev-master

# 2. 현재 IP 확인
tart ip dev-master                              # 예: 192.168.64.5

# 3. kubeconfig의 IP 확인
grep server ../../kubeconfig/dev.yaml           # server: https://192.168.64.3:6443

# 4. 불일치하면 갱신
./scripts/setup.sh --step config
```

### terraform state와 실제 상태 불일치

VM을 재생성했거나 네임스페이스를 수동 삭제한 경우 발생한다.

```bash
# state에서 해당 리소스 제거
terraform state rm 'kubernetes_namespace.dev_apps'

# 기존 리소스를 state에 가져오기 (import)
terraform import 'kubernetes_namespace.dev_apps' devsecops
```
