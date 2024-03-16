resource "random_password" "airflow_fernetKey" {
  length  = 32
  special = false
}
locals {
  kubernetes_version     = "v1.29.0"
  cluster_name           = "kind"
  base_domain            = format("%s.nip.io", replace(module.traefik.external_ip, ".", "-"))
  subdomain              = "apps"
  cluster_issuer         = module.cert-manager.cluster_issuers.ca
  enable_service_monitor = false # Can be enabled after the first bootstrap.
  app_autosync           = true ? { allow_empty = false, prune = true, self_heal = true } : {}
  gateway_base_domain    = format("%s.nip.io", replace(module.istio.external_ip, ".", "-"))
  target_revision        = "develop"
  airflow_fernetKey      = base64encode(resource.random_password.airflow_fernetKey.result)
  project_source_repo    = "https://github.com/GersonRS/credit-risk-analysis-with-machine-learning.git"
}
