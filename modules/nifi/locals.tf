locals {
  helm_values = [{
    nifi = {
      oidc = {
        url           = "${var.oidc.issuer_url}/.well-known/openid-configuration"
        client_id     = var.oidc.client_id
        client_secret = var.oidc.client_secret
      }
      ingress = {
        enabled = true
        annotations = {
          "cert-manager.io/cluster-issuer"                   = "${var.cluster_issuer}"
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
          "traefik.ingress.kubernetes.io/router.middlewares" = "traefik-withclustername@kubernetescrd"
          "traefik.ingress.kubernetes.io/router.tls"         = "true"
          "ingress.kubernetes.io/ssl-redirect"               = "true"
          "kubernetes.io/ingress.allow-http"                 = "false"
        }
        hosts = [
          {
            host = "nifi.apps.${var.base_domain}"
            path = "/nifi"
          },
          {
            host = "nifi.apps.${var.cluster_name}.${var.base_domain}"
            path = "/nifi"
          },
        ]
        tls = [{
          secretName = "nifi-tls"
          hosts = [
            "nifi.apps.${var.base_domain}",
            "nifi.apps.${var.cluster_name}.${var.base_domain}"
          ]
        }]
      }
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
