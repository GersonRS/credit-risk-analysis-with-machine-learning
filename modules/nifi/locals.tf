locals {
  helm_values = [{
    oicd = {
      url           = "${var.oidc.issuer_url}/.well-known/openid-configuration"
      client_id     = var.oicd.client_id
      client_secret = var.oicd.client_secret
    }
  }]
}
