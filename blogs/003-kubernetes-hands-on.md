# 003. Kubernetes 실습 — tart 멀티클러스터 운영

**날짜**: 2025-03-24

---

## 실행 환경

**kubectl은 macOS에서 실행한다.**
`--kubeconfig` 플래그로 대상 클러스터를 지정한다.
kubectl이 kubeconfig에 적힌 API 서버 주소(tart VM IP:6443)로 HTTPS 요청을 보낸다.

```bash
# macOS에서 dev 클러스터에 명령 전달
kubectl --kubeconfig kubeconfig/dev.yaml get nodes

# alias 설정하면 편리하다 (macOS 쉘에 추가)
alias kdev="kubectl --kubeconfig $(pwd)/kubeconfig/dev.yaml"
alias kstaging="kubectl --kubeconfig $(pwd)/kubeconfig/staging.yaml"
alias kprod="kubectl --kubeconfig $(pwd)/kubeconfig/prod.yaml"
alias kplatform="kubectl --kubeconfig $(pwd)/kubeconfig/platform.yaml"

# 사용
kdev get pods -A
kprod get constraints
kplatform get pods -n monitoring
```

## 멀티클러스터 Kustomize 배포

base 매니페스트를 환경별 overlay로 분기하여 배포한다.

```bash
# dev 클러스터에 배포 (replicas=1, 리소스 최소)
kubectl apply -k kubernetes/overlays/dev/ --kubeconfig kubeconfig/dev.yaml

# staging 클러스터에 배포 (replicas=2)
kubectl apply -k kubernetes/overlays/staging/ --kubeconfig kubeconfig/staging.yaml

# prod 클러스터에 배포 (replicas=3, 리소스 넉넉)
kubectl apply -k kubernetes/overlays/prod/ --kubeconfig kubeconfig/prod.yaml

# 렌더링만 (적용하지 않고 결과 확인)
kubectl kustomize kubernetes/overlays/dev/
```

## Cilium 네트워크 관측 (macOS에서)

tart 클러스터는 kube-proxy 대신 Cilium eBPF를 CNI로 사용한다.
Hubble로 실시간 트래픽 흐름을 관측할 수 있다.

```bash
# Cilium 상태 확인 (macOS에서 dev 클러스터의 cilium Pod에 명령 전달)
kubectl --kubeconfig kubeconfig/dev.yaml exec -n kube-system ds/cilium -- cilium status

# Hubble로 devsecops 네임스페이스 트래픽 관측
kubectl --kubeconfig kubeconfig/dev.yaml exec -n kube-system ds/cilium -- \
    hubble observe --namespace devsecops

# 차단된 트래픽만 조회 (NetworkPolicy에 의한 DROP)
kubectl --kubeconfig kubeconfig/dev.yaml exec -n kube-system ds/cilium -- \
    hubble observe --namespace devsecops --verdict DROPPED
```

## 이미지 배포 방법

로컬(macOS)에서 빌드한 Docker 이미지를 tart VM의 containerd에 전달하는 방법:

### 방법 1: containerd 직접 import

```bash
# macOS에서 실행: 이미지를 tar로 내보내고 SSH로 VM에 전송
docker save dashboard:dev | sshpass -p admin ssh -o StrictHostKeyChecking=no \
    admin@$(tart ip dev-worker1) "sudo ctr -n k8s.io images import -"
```

### 방법 2: Harbor 레지스트리 (prod 클러스터에 설치됨)

```bash
# macOS에서 실행
HARBOR=$(tart ip prod-worker1):30500
docker tag dashboard:dev ${HARBOR}/devsecops/dashboard:dev
docker push ${HARBOR}/devsecops/dashboard:dev

# K8s 매니페스트에서 이미지 참조:
# image: <prod-worker1-ip>:30500/devsecops/dashboard:dev
```

## 트러블슈팅

### Pod가 Pending 상태

```bash
# macOS에서 실행
kubectl --kubeconfig kubeconfig/dev.yaml describe pod <pod-name> -n devsecops
# Events 섹션의 FailedScheduling 메시지 확인:
#   Insufficient cpu → ResourceQuota 초과 또는 노드 리소스 부족
#   no nodes available → 노드가 NotReady 상태
```

### 노드 NotReady (VM 재시작 후)

```bash
# 1. macOS에서 VM 상태 확인
tart list | grep dev

# 2. VM에 SSH 접속하여 kubelet 상태 확인
sshpass -p admin ssh admin@$(tart ip dev-master) "sudo systemctl status kubelet"

# 3. Cilium 상태 확인
kubectl --kubeconfig kubeconfig/dev.yaml exec -n kube-system ds/cilium -- cilium status

# 4. 노드가 SchedulingDisabled이면 uncordon
kubectl --kubeconfig kubeconfig/dev.yaml uncordon dev-worker1
```

### ImagePullBackOff

containerd가 이미지를 가져올 수 없을 때 발생한다.

```bash
# 원인 확인
kubectl --kubeconfig kubeconfig/dev.yaml describe pod <pod-name> -n devsecops | grep "Failed"

# 로컬 이미지를 사용하려면:
# 1. imagePullPolicy: Never 또는 IfNotPresent 설정
# 2. containerd import 또는 Harbor push로 이미지 전송
```
