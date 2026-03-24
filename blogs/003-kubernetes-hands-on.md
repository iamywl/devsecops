# 003. Kubernetes 실습 — tart 멀티클러스터 운영

**날짜**: 2025-03-24

---

## tart에서의 K8s 운영

minikube와 달리 tart에서는 **실제 kubeadm으로 구성한 클러스터**를 운영한다.
`kubectl` 실행 시 `--kubeconfig` 플래그로 대상 클러스터를 지정한다.

```bash
# dev 클러스터
kubectl --kubeconfig kubeconfig/dev.yaml get nodes

# prod 클러스터
kubectl --kubeconfig kubeconfig/prod.yaml get pods -A

# alias 설정하면 편리하다
alias kdev="kubectl --kubeconfig kubeconfig/dev.yaml"
alias kprod="kubectl --kubeconfig kubeconfig/prod.yaml"
alias kplatform="kubectl --kubeconfig kubeconfig/platform.yaml"
```

## 4-클러스터 구성 요소

| 클러스터 | CNI | 서비스메시 | 모니터링 | 보안 |
|----------|-----|-----------|---------|------|
| platform | Cilium + Hubble | - | Prometheus, Grafana, Loki | Vault |
| dev | Cilium + Hubble | Istio | - | Trivy Operator |
| staging | Cilium + Hubble | - | - | Trivy Operator |
| prod | Cilium + Hubble | - | - | Gatekeeper, Sealed Secrets, Velero |

## Kustomize로 멀티클러스터 배포

```bash
# dev에 배포 (replicas=1)
kubectl apply -k kubernetes/overlays/dev/ --kubeconfig kubeconfig/dev.yaml

# staging에 배포 (replicas=2)
kubectl apply -k kubernetes/overlays/staging/ --kubeconfig kubeconfig/staging.yaml

# prod에 배포 (replicas=3)
kubectl apply -k kubernetes/overlays/prod/ --kubeconfig kubeconfig/prod.yaml
```

## Cilium 네트워크 관측

tart 클러스터는 kube-proxy 대신 Cilium eBPF를 사용한다.

```bash
# Hubble로 트래픽 관측 (dev 클러스터)
kubectl --kubeconfig kubeconfig/dev.yaml exec -n kube-system ds/cilium -- \
    hubble observe --namespace devsecops

# CiliumNetworkPolicy 확인
kubectl --kubeconfig kubeconfig/dev.yaml get ciliumnetworkpolicy -A
```

## 트러블슈팅

### VM 재시작 후 노드 NotReady

tart VM을 재시작하면 kubelet이 자동 시작되지만 네트워크 초기화에 시간이 걸린다.

```bash
# SSH로 접속하여 확인
sshpass -p admin ssh admin@$(tart ip dev-master) "sudo systemctl status kubelet"

# Cilium 상태 확인
kubectl --kubeconfig kubeconfig/dev.yaml exec -n kube-system ds/cilium -- cilium status
```

### 이미지 배포 방법

tart VM에는 Docker Hub 접근이 가능하지만, 로컬 빌드 이미지를 사용하려면:

```bash
# 방법 1: Harbor (prod 클러스터에 설치됨)
docker tag dashboard:dev $(tart ip prod-worker1):30400/devsecops/dashboard:dev
docker push $(tart ip prod-worker1):30400/devsecops/dashboard:dev

# 방법 2: containerd로 직접 전송
docker save dashboard:dev | sshpass -p admin ssh admin@$(tart ip dev-worker1) \
    "sudo ctr -n k8s.io images import -"
```
