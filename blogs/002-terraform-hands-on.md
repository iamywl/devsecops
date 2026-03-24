# 002. Terraform 실습 — 멀티클러스터 IaC

**날짜**: 2025-03-24

---

## tart 환경에서의 Terraform

단일 클러스터(minikube)와 달리, tart 4-클러스터에서는 **프로바이더를 클러스터별로 분리**한다.

```hcl
provider "kubernetes" {
  alias       = "dev"
  config_path = var.kubeconfig_dev      # kubeconfig/dev.yaml
}

provider "kubernetes" {
  alias       = "prod"
  config_path = var.kubeconfig_prod     # kubeconfig/prod.yaml
}
```

리소스를 생성할 때 `provider = kubernetes.dev` 처럼 어떤 클러스터에 적용할지 명시한다.

## 실습

```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```

생성되는 리소스:
- dev/staging/prod 각 클러스터에 `devsecops` 네임스페이스
- ResourceQuota (환경별 차등)
- LimitRange (컨테이너 기본 리소스)
- RBAC (deployer 역할 + cicd-deployer 서비스 어카운트)
- NetworkPolicy (기본 차단 + DNS 허용)

```bash
# 확인
kubectl get namespace devsecops --kubeconfig kubeconfig/dev.yaml
kubectl get resourcequota -n devsecops --kubeconfig kubeconfig/dev.yaml
kubectl get networkpolicy -n devsecops --kubeconfig kubeconfig/dev.yaml
```

## 멀티클러스터 Terraform의 핵심

### kubeconfig 관리

tart VM의 IP는 재시작마다 바뀔 수 있다.
kubeconfig의 server 주소를 갱신하는 스크립트가 필요하다:

```bash
./scripts/setup.sh --step config   # kubeconfig 자동 수집 + IP 갱신
```

### 환경별 차등 리소스

```hcl
# dev: 가벼운 제한
"requests.cpu" = "2"
"requests.memory" = "4Gi"

# prod: 엄격한 제한
"requests.cpu" = "4"
"requests.memory" = "8Gi"
```

## 트러블슈팅

### "Unable to connect to the server"

VM이 꺼져 있거나 kubeconfig의 IP가 틀렸을 때 발생한다.

```bash
tart ip dev-master                  # 현재 IP 확인
cat kubeconfig/dev.yaml | grep server  # kubeconfig의 IP 확인
# 불일치하면 ./scripts/setup.sh --step config 로 갱신
```

### state lock 충돌

```bash
# 로컬 백엔드에서는 드물지만, 발생 시:
rm -f .terraform.lock.hcl
terraform init
```
