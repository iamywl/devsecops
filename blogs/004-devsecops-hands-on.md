# 004. DevSecOps 실습 — tart 멀티클러스터 보안 체계

**날짜**: 2025-03-24

---

## 보안 레이어 구성

```
코드 작성
  ↓
[Layer 1] 로컬 Trivy CLI로 이미지/매니페스트 스캔
  ↓
[Layer 2] CI 파이프라인에서 자동 Trivy 스캔
  ↓
[Layer 3] Trivy Operator가 클러스터 내에서 지속 스캔 (dev + prod)
  ↓
[Layer 4] OPA Gatekeeper가 prod 배포 시 정책 위반 차단
  ↓
[Layer 5] CiliumNetworkPolicy로 L3/L4/L7 제로트러스트
  ↓
[Layer 6] Sealed Secrets + Vault로 시크릿 암호화
  ↓
[Layer 7] Velero로 백업/DR
```

## Layer 1: Trivy CLI — 로컬 스캔

```bash
# 이미지 취약점 스캔
trivy image dashboard:dev

# K8s 매니페스트 보안 검사
trivy config kubernetes/

# Dockerfile 보안 검사
trivy config dashboard/Dockerfile

# 전체 스캔 스크립트
./scripts/scan.sh
```

## Layer 3: Trivy Operator — 클러스터 내 지속 스캔

Trivy Operator는 클러스터에 배포되어 **모든 이미지를 자동으로 스캔**한다.

```bash
# dev 클러스터의 취약점 보고서
kubectl get vulnerabilityreports -A --kubeconfig kubeconfig/dev.yaml

# 특정 이미지의 상세 취약점
kubectl describe vulnerabilityreport <name> -n devsecops --kubeconfig kubeconfig/dev.yaml

# CIS 벤치마크 결과
kubectl get configauditreports -A --kubeconfig kubeconfig/dev.yaml
```

## Layer 4: OPA Gatekeeper — 정책 엔진 (prod)

prod 클러스터에만 Gatekeeper를 설치하여 엄격한 정책을 적용한다.

```bash
# 현재 적용된 정책 확인
kubectl get constraints -A --kubeconfig kubeconfig/prod.yaml

# 정책 위반 테스트: latest 태그 → 거부됨
kubectl apply --kubeconfig kubeconfig/prod.yaml -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-latest
  namespace: devsecops
  labels: { app: test, environment: prod }
spec:
  selector: { matchLabels: { app: test } }
  template:
    metadata: { labels: { app: test } }
    spec:
      containers:
        - name: test
          image: nginx:latest
EOF
# Error: 이미지 'nginx:latest'에 :latest 태그 사용 금지
```

## Layer 5: CiliumNetworkPolicy — 제로트러스트

dev 클러스터에는 이미 L3/L4/L7 수준의 CiliumNetworkPolicy가 적용되어 있다.

```bash
# 현재 네트워크 정책 확인
kubectl get ciliumnetworkpolicy -A --kubeconfig kubeconfig/dev.yaml

# Hubble로 트래픽 흐름 관측
kubectl --kubeconfig kubeconfig/dev.yaml exec -n kube-system ds/cilium -- \
    hubble observe --namespace devsecops --verdict DROPPED
```

## Layer 6: Sealed Secrets + Vault

```bash
# Sealed Secrets (prod): 암호화된 시크릿을 Git에 저장할 수 있다
kubectl get sealedsecrets -A --kubeconfig kubeconfig/prod.yaml

# Vault (platform): 시크릿 중앙 관리
kubectl port-forward svc/vault -n vault 8200:8200 --kubeconfig kubeconfig/platform.yaml
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=root
vault kv put secret/dashboard db_password="supersecret"
vault kv get secret/dashboard
```

## Layer 7: Velero — 백업/DR

```bash
# 백업 목록 확인
kubectl get backups -n velero --kubeconfig kubeconfig/prod.yaml

# etcd 스냅샷 (master 노드에서 직접)
sshpass -p admin ssh admin@$(tart ip prod-master) \
    "sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key"
```

## CI/CD 보안 통합

```
Push → Lint → Test → Trivy Scan → Build → Push to Harbor
                                              ↓
                                    ArgoCD Sync → dev
                                              ↓ (수동 승인)
                                    ArgoCD Sync → staging → prod
                                              ↓
                                    Gatekeeper 정책 검증 → 위반 시 거부
```

## 트러블슈팅

### Trivy Operator DB 업데이트 느림

VM의 네트워크가 느릴 경우 DB 다운로드에 시간이 걸린다.

```bash
# Trivy Operator 로그 확인
kubectl logs -n trivy-system -l app.kubernetes.io/name=trivy-operator \
    --kubeconfig kubeconfig/dev.yaml
```

### Gatekeeper webhook timeout

```bash
# Gatekeeper Pod 상태 확인
kubectl get pods -n gatekeeper-system --kubeconfig kubeconfig/prod.yaml

# 급한 경우 webhook 비활성화 (임시)
kubectl delete validatingwebhookconfigurations \
    gatekeeper-validating-webhook-configuration \
    --kubeconfig kubeconfig/prod.yaml
```
