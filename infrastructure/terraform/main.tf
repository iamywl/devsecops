# =============================================================================
# Terraform: tart 4-클러스터 환경의 K8s 보안 리소스 프로비저닝
#
# 기존 IaC_apple_sillicon 프로젝트가 생성한 4개 클러스터 위에
# DevSecOps에 필요한 네임스페이스, RBAC, ResourceQuota, NetworkPolicy를 적용한다.
#
# 전제:
#   - tart VM 10대가 이미 실행 중이어야 한다
#   - kubeconfig 파일이 ~/.kube/ 또는 지정 경로에 있어야 한다
#
# 사용법:
#   cd infrastructure/terraform
#   terraform init
#   terraform plan
#   terraform apply
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# -----------------------------------------------------------------------------
# 프로바이더: 각 클러스터별 kubeconfig로 접근
# tart VM의 kubeconfig 경로는 변수로 지정한다
# -----------------------------------------------------------------------------
provider "kubernetes" {
  alias       = "dev"
  config_path = var.kubeconfig_dev
}

provider "kubernetes" {
  alias       = "staging"
  config_path = var.kubeconfig_staging
}

provider "kubernetes" {
  alias       = "prod"
  config_path = var.kubeconfig_prod
}

# -----------------------------------------------------------------------------
# Dev 클러스터: 보안 네임스페이스 + RBAC + NetworkPolicy
# -----------------------------------------------------------------------------
resource "kubernetes_namespace" "dev_apps" {
  provider = kubernetes.dev

  metadata {
    name = "devsecops"
    labels = {
      managed-by  = "terraform"
      environment = "dev"
    }
  }
}

resource "kubernetes_resource_quota" "dev_quota" {
  provider = kubernetes.dev

  metadata {
    name      = "devsecops-quota"
    namespace = kubernetes_namespace.dev_apps.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = "2"
      "requests.memory" = "4Gi"
      "limits.cpu"      = "4"
      "limits.memory"   = "8Gi"
      "pods"            = "30"
    }
  }
}

resource "kubernetes_limit_range" "dev_limits" {
  provider = kubernetes.dev

  metadata {
    name      = "devsecops-limits"
    namespace = kubernetes_namespace.dev_apps.metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}

# RBAC: 배포 담당자 역할
resource "kubernetes_role" "dev_deployer" {
  provider = kubernetes.dev

  metadata {
    name      = "deployer"
    namespace = kubernetes_namespace.dev_apps.metadata[0].name
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["services", "configmaps", "secrets", "pods", "pods/log"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
}

resource "kubernetes_service_account" "dev_cicd" {
  provider = kubernetes.dev

  metadata {
    name      = "cicd-deployer"
    namespace = kubernetes_namespace.dev_apps.metadata[0].name
  }
}

resource "kubernetes_role_binding" "dev_cicd_binding" {
  provider = kubernetes.dev

  metadata {
    name      = "cicd-deployer-binding"
    namespace = kubernetes_namespace.dev_apps.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.dev_deployer.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.dev_cicd.metadata[0].name
    namespace = kubernetes_namespace.dev_apps.metadata[0].name
  }
}

# Zero Trust: 기본 통신 차단 + DNS만 허용
resource "kubernetes_network_policy" "dev_default_deny" {
  provider = kubernetes.dev

  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace.dev_apps.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy" "dev_allow_dns" {
  provider = kubernetes.dev

  metadata {
    name      = "allow-dns"
    namespace = kubernetes_namespace.dev_apps.metadata[0].name
  }

  spec {
    pod_selector {}
    egress {
      ports {
        port     = 53
        protocol = "UDP"
      }
      ports {
        port     = 53
        protocol = "TCP"
      }
    }
    policy_types = ["Egress"]
  }
}

# -----------------------------------------------------------------------------
# Staging 클러스터: 동일 구조
# -----------------------------------------------------------------------------
resource "kubernetes_namespace" "staging_apps" {
  provider = kubernetes.staging

  metadata {
    name = "devsecops"
    labels = {
      managed-by  = "terraform"
      environment = "staging"
    }
  }
}

resource "kubernetes_resource_quota" "staging_quota" {
  provider = kubernetes.staging

  metadata {
    name      = "devsecops-quota"
    namespace = kubernetes_namespace.staging_apps.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = "3"
      "requests.memory" = "6Gi"
      "limits.cpu"      = "6"
      "limits.memory"   = "12Gi"
      "pods"            = "40"
    }
  }
}

# -----------------------------------------------------------------------------
# Prod 클러스터: 더 엄격한 리소스 + 보안 설정
# -----------------------------------------------------------------------------
resource "kubernetes_namespace" "prod_apps" {
  provider = kubernetes.prod

  metadata {
    name = "devsecops"
    labels = {
      managed-by  = "terraform"
      environment = "prod"
    }
  }
}

resource "kubernetes_resource_quota" "prod_quota" {
  provider = kubernetes.prod

  metadata {
    name      = "devsecops-quota"
    namespace = kubernetes_namespace.prod_apps.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = "4"
      "requests.memory" = "8Gi"
      "limits.cpu"      = "8"
      "limits.memory"   = "16Gi"
      "pods"            = "50"
    }
  }
}

resource "kubernetes_network_policy" "prod_default_deny" {
  provider = kubernetes.prod

  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace.prod_apps.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy" "prod_allow_dns" {
  provider = kubernetes.prod

  metadata {
    name      = "allow-dns"
    namespace = kubernetes_namespace.prod_apps.metadata[0].name
  }

  spec {
    pod_selector {}
    egress {
      ports {
        port     = 53
        protocol = "UDP"
      }
      ports {
        port     = 53
        protocol = "TCP"
      }
    }
    policy_types = ["Egress"]
  }
}
