# =============================================================================
# 출력값
# =============================================================================

output "dev_namespace" {
  value = kubernetes_namespace.dev_apps.metadata[0].name
}

output "staging_namespace" {
  value = kubernetes_namespace.staging_apps.metadata[0].name
}

output "prod_namespace" {
  value = kubernetes_namespace.prod_apps.metadata[0].name
}
