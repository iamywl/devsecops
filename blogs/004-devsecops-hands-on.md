# 004. DevSecOps 실습 — tart 멀티클러스터 보안 체계

**날짜**: 2025-03-24

---

## 실행 환경

| 도구 | 실행 위치 | 대상 |
|------|-----------|------|
| trivy CLI | macOS | 로컬 이미지, 로컬 파일 스캔 |
| Trivy Operator | tart VM 안 (Pod) | 클러스터 내 이미지 지속 스캔 |
| OPA Gatekeeper | tart VM 안 (Pod) | API 서버의 Admission Webhook |
| Vault | tart VM 안 (Pod) | 시크릿 저장소 |
| kubectl (조회) | macOS | 위 도구들의 결과를 원격 조회 |

Trivy CLI는 macOS에서 로컬 파일을 스캔한다.
Trivy Operator, Gatekeeper, Vault는 tart VM 안의 K8s Pod로 실행된다.
macOS에서 kubectl로 이들의 결과를 조회한다.

## 보안 레이어

```
코드 작성 (macOS)
  ↓
[Layer 1] trivy config kubernetes/     ← macOS에서 실행, 로컬 파일 스캔
[Layer 2] trivy image dashboard:dev    ← macOS에서 실행, 로컬 이미지 스캔
  ↓
[Layer 3] Trivy Operator               ← VM 안에서 자동 실행, 결과를 kubectl로 조회
  ↓
[Layer 4] OPA Gatekeeper               ← VM 안에서 자동 실행, 정책 위반 시 배포 거부
  ↓
[Layer 5] CiliumNetworkPolicy          ← VM 안에서 자동 집행
  ↓
[Layer 6] Sealed Secrets + Vault       ← VM 안에서 실행
  ↓
[Layer 7] Velero + etcd snapshot       ← VM 안에서 실행
```

## Layer 1-2: Trivy CLI (macOS에서 실행)

macOS 로컬에서 파일과 이미지를 스캔한다. VM에 접속하지 않는다.

```bash
# K8s 매니페스트 보안 검사 (macOS에서)
trivy config kubernetes/
# 결과: Deployment에 runAsNonRoot 미설정, resources 미설정 등

# Dockerfile 보안 검사 (macOS에서)
trivy config dashboard/Dockerfile
# 결과: USER 지시어 누락, HEALTHCHECK 미설정 등

# Docker 이미지 취약점 스캔 (macOS에서)
trivy image --severity HIGH,CRITICAL dashboard:dev
# 결과: CVE 목록, 영향받는 패키지, 수정 버전

# 전체 스캔 스크립트 (macOS에서)
./scripts/scan.sh
```

## Layer 3: Trivy Operator (VM 안에서 실행, macOS에서 조회)

Trivy Operator는 클러스터에 Pod로 배포되어, 새로 배포되는 모든 이미지를 자동 스캔한다.

```bash
# 설치 확인 (macOS에서 dev 클러스터 조회)
kubectl --kubeconfig kubeconfig/dev.yaml get pods -n trivy-system

# 취약점 보고서 조회 (macOS에서)
kubectl --kubeconfig kubeconfig/dev.yaml get vulnerabilityreports -A
kubectl --kubeconfig kubeconfig/dev.yaml describe vulnerabilityreport <name> -n devsecops

# CIS 벤치마크 결과 (macOS에서)
kubectl --kubeconfig kubeconfig/dev.yaml get configauditreports -A
```

## Layer 4: OPA Gatekeeper (VM 안에서 실행, macOS에서 테스트)

prod 클러스터에만 설치된다. kubectl apply 시 K8s API 서버가
Gatekeeper webhook을 호출하여 정책을 검사한다.

```bash
# 적용된 정책 확인 (macOS에서)
kubectl --kubeconfig kubeconfig/prod.yaml get constraints -A

# 테스트: latest 태그 배포 시도 (macOS에서)
kubectl --kubeconfig kubeconfig/prod.yaml apply -f - <<EOF
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
# 결과: Error from server: admission webhook denied the request:
#        이미지 'nginx:latest'에 :latest 태그 사용 금지

# 올바른 배포 (명시적 버전 태그)
# image: nginx:1.27-alpine  → 통과
```

## Layer 5: CiliumNetworkPolicy (VM 안에서 집행, macOS에서 관측)

```bash
# 현재 네트워크 정책 확인 (macOS에서)
kubectl --kubeconfig kubeconfig/dev.yaml get ciliumnetworkpolicy -A

# Hubble로 차단된 트래픽 관측 (macOS에서 cilium Pod에 명령 전달)
kubectl --kubeconfig kubeconfig/dev.yaml exec -n kube-system ds/cilium -- \
    hubble observe --namespace devsecops --verdict DROPPED
```

## Layer 6: Vault (VM 안에서 실행, macOS에서 접근)

```bash
# Vault UI 접속을 위한 포트포워딩 (macOS에서)
kubectl --kubeconfig kubeconfig/platform.yaml port-forward svc/vault -n vault 8200:8200 &

# macOS 브라우저에서 http://localhost:8200 접속 (Token: root)

# 또는 CLI로 접근 (macOS에서)
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=root
vault kv put secret/dashboard db_password="supersecret"
vault kv get secret/dashboard
```

## Layer 7: Velero 백업 (VM 안에서 실행, macOS에서 조회)

```bash
# 백업 목록 확인 (macOS에서)
kubectl --kubeconfig kubeconfig/prod.yaml get backups -n velero

# etcd 스냅샷은 master VM에 SSH 접속하여 실행
sshpass -p admin ssh admin@$(tart ip prod-master) \
    "sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key"

# 스냅샷을 macOS로 가져오기
sshpass -p admin scp admin@$(tart ip prod-master):/tmp/etcd-backup.db ./etcd-backup.db
```

## 트러블슈팅

### Trivy Operator가 보고서를 생성하지 않음

```bash
# Operator Pod 로그 확인 (macOS에서)
kubectl --kubeconfig kubeconfig/dev.yaml logs -n trivy-system \
    -l app.kubernetes.io/name=trivy-operator --tail=50

# DB 다운로드 진행 중일 수 있다 (초기 설치 시 수분 소요)
```

### Gatekeeper가 모든 배포를 차단

```bash
# Gatekeeper Pod 상태 확인 (macOS에서)
kubectl --kubeconfig kubeconfig/prod.yaml get pods -n gatekeeper-system

# webhook 일시 비활성화 (긴급 시, macOS에서)
kubectl --kubeconfig kubeconfig/prod.yaml delete validatingwebhookconfigurations \
    gatekeeper-validating-webhook-configuration

# 복구: Gatekeeper를 재배포하면 webhook이 재생성된다
```
