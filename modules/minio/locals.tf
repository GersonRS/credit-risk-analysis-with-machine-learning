resource "random_password" "minio_root_secretkey" {
  length  = 32
  special = false
}

locals {
  domain      = format("minio.apps.%s", var.base_domain)
  domain_full = format("minio.apps.%s.%s", var.cluster_name, var.base_domain)

  self_signed_cert_enabled = var.cluster_issuer == "ca-issuer" || var.cluster_issuer == "letsencrypt-staging"

  self_signed_cert = {
    extraVolumeMounts = [
      {
        name      = "certificate"
        mountPath = format("/etc/ssl/certs/%s", var.cluster_issuer == "letsencrypt-staging" ? "tls.crt" : "ca.crt")
        subPath   = var.cluster_issuer == "letsencrypt-staging" ? "tls.crt" : "ca.crt"
      },
    ]
    extraVolumes = [
      {
        name = "certificate"
        secret = {
          secretName = "minio-tls"
        }
      }
    ]
  }

  oidc_config = var.oidc != null ? merge(
    {
      oidc = {
        enabled      = true
        configUrl    = "${var.oidc.issuer_url}/.well-known/openid-configuration"
        clientId     = var.oidc.client_id
        clientSecret = var.oidc.client_secret
        claimName    = "policy"
        scopes       = "openid,profile,email"
        redirectUri  = format("https://%s/oauth_callback", local.domain_full)
        claimPrefix  = ""
        comment      = ""
      }
    },
    local.self_signed_cert_enabled ? local.self_signed_cert : null
  ) : null

  helm_values = [{
    minio-operator = {
      operator = {
        replicaCount = 1
        env = [
          {
            name  = "MINIO_IDENTITY_OPENID_CONFIG_URL"
            value = "${var.oidc.issuer_url}/.well-known/openid-configuration"
          },
          {
            name  = "MINIO_IDENTITY_OPENID_CLIENT_ID"
            value = var.oidc.client_id
          },
          {
            name  = "MINIO_IDENTITY_OPENID_CLIENT_SECRET"
            value = var.oidc.client_secret
          },
          {
            name  = "MINIO_IDENTITY_OPENID_CLAIM_NAME"
            value = "policy"
          },
          {
            name  = "MINIO_IDENTITY_OPENID_CLAIM_PREFIX"
            value = ""
          },
          {
            name  = "MINIO_IDENTITY_OPENID_SCOPES"
            value = "openid,profile,email"
          },
          {
            name  = "MINIO_IDENTITY_OPENID_REDIRECT_URI"
            value = format("https://%s/oauth_callback", format("minio-console.apps.%s.%s", var.cluster_name, var.base_domain))
          },
          {
            name  = "MINIO_IDENTITY_OPENID_COMMENT"
            value = ""
          },
        ]
      }
      console = {
        ingress = {
          enabled          = true
          ingressClassName = "traefik"
          annotations = {
            "cert-manager.io/cluster-issuer"                   = "${var.cluster_issuer}"
            "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
            "traefik.ingress.kubernetes.io/router.middlewares" = "traefik-withclustername@kubernetescrd"
            "traefik.ingress.kubernetes.io/router.tls"         = "true"
            "ingress.kubernetes.io/ssl-redirect"               = "true"
            "kubernetes.io/ingress.allow-http"                 = "false"
          }
          tls = [{
            secretName = "minio-operator-tls"
            hosts      = [format("minio-console.apps.%s.%s", var.cluster_name, var.base_domain)]
          }]
          host = format("minio-console.apps.%s.%s", var.cluster_name, var.base_domain)
        }
      }
    }
    tenant = {
      secrets = {
        name      = "minio-env-configuration"
        accessKey = "minio"
        secretKey = "${random_password.minio_root_secretkey.result}"
      }
      tenant = {
        name = "minio"
        configuration = {
          name = "minio-env-configuration"
        }
        pools = [{
          servers          = 2
          volumesPerServer = 2
          size             = "10Gi"
        }]
        buckets = local.minio_config.buckets
        users = [
          {
            CONSOLE_ACCESS_KEY = "airflow-user"
            CONSOLE_SECRET_KEY = random_password.minio_root_secretkey.result
          }
        ]
        env = [
          {
            name  = "MINIO_IDENTITY_OPENID_CONFIG_URL"
            value = "${var.oidc.issuer_url}/.well-known/openid-configuration"
          },
          {
            name  = "MINIO_IDENTITY_OPENID_CLIENT_ID"
            value = var.oidc.client_id
          },
          {
            name  = "MINIO_IDENTITY_OPENID_CLIENT_SECRET"
            value = var.oidc.client_secret
          },
          {
            name  = "MINIO_IDENTITY_OPENID_CLAIM_NAME"
            value = "policy"
          },
          {
            name  = "MINIO_IDENTITY_OPENID_CLAIM_PREFIX"
            value = ""
          },
          {
            name  = "MINIO_IDENTITY_OPENID_SCOPES"
            value = "openid,profile,email"
          },
          {
            name  = "MINIO_IDENTITY_OPENID_REDIRECT_URI"
            value = format("https://%s/oauth_callback", format("minio-tenant.apps.%s.%s", var.cluster_name, var.base_domain))
          },
          {
            name  = "MINIO_IDENTITY_OPENID_COMMENT"
            value = ""
          },
        ]
      }
      ingress = {
        console = {
          enabled = true
          ingressClassName : "traefik"
          annotations = {
            "cert-manager.io/cluster-issuer"                   = "${var.cluster_issuer}"
            "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
            "traefik.ingress.kubernetes.io/router.middlewares" = "traefik-withclustername@kubernetescrd"
            "traefik.ingress.kubernetes.io/router.tls"         = "true"
            "ingress.kubernetes.io/ssl-redirect"               = "true"
            "kubernetes.io/ingress.allow-http"                 = "false"
          }
          tls = [{
            secretName = "minio-tenant-tls"
            hosts = [
              format("minio-tenant.apps.%s.%s", var.cluster_name, var.base_domain),
            ]
          }]
          host = format("minio-tenant.apps.%s.%s", var.cluster_name, var.base_domain)
        }
      }
    }
    minio = merge(
      {
        mode = "standalone" # Set the deployment mode of MinIO to standalone
        persistence = {
          size : "20Gi"
        }
        resources = {
          requests = {
            memory = "128Mi"
          }
        }
        consoleIngress = {
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
            local.domain,
            local.domain_full,
          ]
          tls = [{
            secretName = "minio-tls"
            hosts = [
              local.domain,
              local.domain_full,
            ]
          }]
        }
        metrics = {
          serviceMonitor = {
            enabled = var.enable_service_monitor
          }
        }
        rootUser     = "root"
        rootPassword = random_password.minio_root_secretkey.result
        users        = local.minio_config.users
        buckets      = local.minio_config.buckets
        policies     = local.minio_config.policies
      },
      local.oidc_config
    )
  }]

  minio_config = {
    policies = [
      {
        name = "loki-policy"
        statements = [
          {
            resources = ["arn:aws:s3:::loki-bucket"]
            actions   = ["s3:CreateBucket", "s3:DeleteBucket", "s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
          },
          {
            resources = ["arn:aws:s3:::loki-bucket/*"]
            actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          }
        ]
      },
      {
        name = "thanos-policy"
        statements = [
          {
            resources = ["arn:aws:s3:::thanos-bucket"]
            actions   = ["s3:CreateBucket", "s3:DeleteBucket", "s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
          },
          {
            resources = ["arn:aws:s3:::thanos-bucket/*"]
            actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          }
        ]
      },
      {
        name = "mlflow-policy"
        statements = [
          {
            resources = ["arn:aws:s3:::mlflow-bucket"]
            actions   = ["s3:CreateBucket", "s3:DeleteBucket", "s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
          },
          {
            resources = ["arn:aws:s3:::mlflow-bucket/*"]
            actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          }
        ]
      },
      {
        name = "jupyterhub-policy"
        statements = [
          {
            resources = ["arn:aws:s3:::jupyterhub-bucket"]
            actions   = ["s3:CreateBucket", "s3:DeleteBucket", "s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
          },
          {
            resources = ["arn:aws:s3:::jupyterhub-bucket/*"]
            actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          }
        ]
      },
      {
        name = "airflow-policy"
        statements = [
          {
            resources = ["arn:aws:s3:::airflow-bucket"]
            actions   = ["s3:CreateBucket", "s3:DeleteBucket", "s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
          },
          {
            resources = ["arn:aws:s3:::airflow-bucket/*"]
            actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          }
        ]
      }
    ],
    users = [
      {
        accessKey = "mlflow-user"
        secretKey = random_password.minio_root_secretkey.result
        policy    = "mlflow-policy"
      },
      {
        accessKey = "airflow-user"
        secretKey = random_password.minio_root_secretkey.result
        policy    = "airflow-policy"
      },
      {
        accessKey = "jupterhub-user"
        secretKey = random_password.minio_root_secretkey.result
        policy    = "jupterhub-policy"
      },
      {
        accessKey = "loki-user"
        secretKey = random_password.minio_root_secretkey.result
        policy    = "loki-policy"
      },
      {
        accessKey = "thanos-user"
        secretKey = random_password.minio_root_secretkey.result
        policy    = "thanos-policy"
      }
    ],
    buckets = [
      {
        name = "loki-bucket"
      },
      {
        name = "thanos-bucket"
      },
      {
        name = "mlflow"
      },
      {
        name = "airflow"
      },
      {
        name = "landing"
      },
      {
        name = "processing"
      },
      {
        name = "curated"
      },
      {
        name = "bronze"
      },
      {
        name = "silver"
      },
      {
        name = "gold"
      }
    ]
  }
}
