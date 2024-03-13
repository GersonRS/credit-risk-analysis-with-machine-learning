locals {
  helm_values = [{
    oidc = {
      url           = "${var.oidc.issuer_url}/.well-known/openid-configuration"
      client_id     = var.oidc.client_id
      client_secret = var.oidc.client_secret
    }
    nifikop = {
      image = {
        tag = "v1.7.0-release"
      }
      resources = {
        requests = {
          memory = "256Mi"
          cpu    = "250m"
        }
        limits = {
          memory = "256Mi"
          cpu    = "550m"
        }
      }
      namespaces = ["nifi"]
    }
  }]
}
