locals {
  helm_values = [{
    oidc = {
      url           = "${var.oidc.issuer_url}/.well-known/openid-configuration"
      client_id     = var.oidc.client_id
      client_secret = var.oidc.client_secret
    }
  }]
}
