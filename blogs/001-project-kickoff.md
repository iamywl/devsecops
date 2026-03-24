# 001. 프로젝트 킥오프 — tart 4-클러스터 DevSecOps

**날짜**: 2025-03-24

---

## 실행 환경

이 프로젝트의 모든 도구는 **macOS 호스트에서 실행**한다.
tart VM 안에서 직접 작업하는 것이 아니다.

| 도구 | 실행 위치 | 접속 대상 |
|------|-----------|-----------|
| tart | macOS | VM 생성/시작/중지 |
| kubectl | macOS | VM 안의 K8s API 서버 (kubeconfig 경유) |
| terraform | macOS | VM 안의 K8s API 서버 (kubeconfig 경유) |
| ansible | macOS (localhost) | kubectl/helm 명령 실행 (kubeconfig 경유) |
| trivy | macOS | 로컬 이미지/파일 스캔 |
| docker build | macOS | 로컬 이미지 빌드 |
| ssh/scp | macOS → VM | 디버깅, kubeconfig 복사, 이미지 전송 |

VM 내부에서 실행되는 것은 K8s 컴포넌트(kubelet, containerd, cilium, Pod)뿐이다.

## 배경

CielMobility DevOps 및 운영엔지니어 직무의 핵심 요구사항을 충족하기 위해
로컬에서 프로덕션급 멀티클러스터 DevSecOps 환경을 구축한다.

## tart 선택 이유

tart는 Apple Silicon의 Virtualization.framework를 사용하는 VM 관리 도구다.

| 항목 | minikube | tart |
|------|----------|------|
| 노드 구현 | Docker 컨테이너 (커널 공유) | 독립 VM (커널 격리) |
| K8s 구성 방식 | minikube가 자동 구성 | kubeadm으로 수동 구성 (실무 동일) |
| 멀티클러스터 | 프로파일 교체 방식 (동시 실행 제한) | VM 단위 독립 (동시 10대 실행) |
| 네트워크 | 단일 Docker 네트워크 | VM별 독립 IP, 클러스터별 독립 CIDR |
| SSH 접속 | 불가 | 가능 (admin/admin) |
| 실무 유사성 | 낮음 | IDC 서버와 동일한 구조 |

M4 Max 128GB RAM에서 10대 VM(68GB)을 동시에 실행해도 60GB 여유가 있다.

## 4-클러스터 설계 이유

| 분리 기준 | 이유 |
|-----------|------|
| platform ↔ 워크로드 | 모니터링 시스템이 워크로드 장애에 영향받지 않아야 한다 |
| dev ↔ staging ↔ prod | 환경별 보안 정책을 차등 적용한다 (dev: 느슨, prod: 엄격) |
| 독립 Pod CIDR | 클러스터 간 IP 충돌을 방지한다 (10.10/10.20/10.30/10.40) |

## 트러블슈팅 기록

### tart VM IP 변동

tart VM은 재시작 시 IP가 바뀔 수 있다.
kubeconfig의 `server: https://<IP>:6443` 주소가 맞지 않으면 kubectl이 실패한다.

해결: `./scripts/setup.sh --step config` 실행 시 자동으로 현재 IP를 감지하고 kubeconfig를 갱신한다.

### softnet 네트워크 플래그

`tart run` 시 `--net-softnet-allow=0.0.0.0/0` 없이 실행하면
VM 간 통신이 차단되어 kubeadm join, Cilium 통신이 실패한다.
