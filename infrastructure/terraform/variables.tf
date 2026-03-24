# =============================================================================
# 변수 정의
#
# tart VM 기반 4-클러스터의 kubeconfig 경로를 지정한다.
# IaC_apple_sillicon 프로젝트가 생성한 kubeconfig를 참조한다.
# =============================================================================

variable "kubeconfig_dev" {
  description = "dev 클러스터 kubeconfig 경로"
  type        = string
  default     = "../../kubeconfig/dev.yaml"
}

variable "kubeconfig_staging" {
  description = "staging 클러스터 kubeconfig 경로"
  type        = string
  default     = "../../kubeconfig/staging.yaml"
}

variable "kubeconfig_prod" {
  description = "prod 클러스터 kubeconfig 경로"
  type        = string
  default     = "../../kubeconfig/prod.yaml"
}
