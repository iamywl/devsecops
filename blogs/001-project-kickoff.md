# 001. 프로젝트 킥오프 — tart 4-클러스터 DevSecOps

**날짜**: 2025-03-24

---

## 배경

CielMobility DevOps 및 운영엔지니어 직무의 핵심 요구사항:
- On-premises + Cloud 하이브리드 인프라
- GPU/HPC 포함 대규모 클러스터 구축
- Kubernetes 컨테이너 오케스트레이션
- Terraform/Ansible IaC 자동화
- CI/CD 파이프라인
- DevSecOps 보안 인증 대응
- 모니터링 및 장애 대응

이를 증명하기 위해 **로컬에서 프로덕션급 멀티클러스터 DevSecOps 환경**을 구축한다.

## 왜 tart인가

| 비교 항목 | minikube | tart |
|-----------|----------|------|
| 가상화 | Docker 컨테이너 (가짜 노드) | 실제 VM (Apple Virtualization.framework) |
| 멀티클러스터 | 어려움 | 자연스러움 (VM 단위 분리) |
| 네트워크 | 단일 Docker 네트워크 | 클러스터별 독립 네트워크 |
| 실무 유사성 | 낮음 | 높음 (IDC 서버와 동일한 구조) |
| kubeadm 사용 | 불가 | 가능 (실제 클러스터 구성) |

M4 Max 128GB RAM이면 10대 VM을 동시에 돌려도 절반도 안 쓴다.

## 4-클러스터 설계

```
platform (3노드, 24GB) ─── 관리/관측 전용
    Prometheus, Grafana, Loki, ArgoCD, Jenkins, Vault

dev (2노드, 12GB) ─── 개발/테스트
    Istio, Cilium, HPA, Demo Apps, Trivy Operator

staging (2노드, 12GB) ─── 프로덕션 전 검증
    Cilium, 배포 검증

prod (3노드, 20GB) ─── 운영
    Gatekeeper, Sealed Secrets, Velero, Harbor, Trivy Operator
```

**왜 4개로 나누는가?**
- 실무에서 관리 도구(모니터링, CI/CD)와 워크로드를 같은 클러스터에 두지 않는다
- 장애 격리: dev에서 실험하다 platform 모니터링이 죽으면 안 된다
- 보안 분리: prod에만 엄격한 정책을 적용할 수 있다

## 트러블슈팅 로그

### tart VM 네트워크 softnet

tart run 시 `--net-softnet-allow=0.0.0.0/0` 플래그가 필요하다.
이것 없이 실행하면 VM 간 통신이 안 된다.

### kubeconfig server 주소

kubeadm init이 생성하는 kubeconfig의 server 주소가 `https://localhost:6443`이다.
호스트에서 접근하려면 `tart ip`로 얻은 실제 IP로 교체해야 한다.

```bash
sed -i '' "s|https://.*:6443|https://$(tart ip dev-master):6443|g" kubeconfig/dev.yaml
```
