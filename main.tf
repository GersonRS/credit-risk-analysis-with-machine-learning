module "kind" {
  source             = "./modules/kind"
  cluster_name       = local.cluster_name
  kubernetes_version = local.kubernetes_version
}

module "metallb" {
  source = "./modules/metallb"
  subnet = module.kind.kind_subnet
}

module "argocd_bootstrap" {
  source = "./modules/argocd_bootstrap"
  argocd_projects = {
    "${local.cluster_name}" = {
      destination_cluster = "in-cluster"
    }
  }
  depends_on = [module.kind]
}

module "metrics-server" {
  source               = "./modules/metrics-server"
  argocd_project       = local.cluster_name
  argocd_namespace     = module.argocd_bootstrap.argocd_namespace
  kubelet_insecure_tls = true
  target_revision      = local.target_revision
  project_source_repo  = local.project_source_repo
  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

module "traefik" {
  source                 = "./modules/traefik/kind"
  cluster_name           = local.cluster_name
  base_domain            = "172-18-0-100.nip.io"
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  enable_service_monitor = local.enable_service_monitor
  target_revision        = local.target_revision
  project_source_repo    = local.project_source_repo
  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

module "istio" {
  source                 = "./modules/istio"
  cluster_name           = local.cluster_name
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  enable_service_monitor = local.enable_service_monitor
  target_revision        = local.target_revision
  project_source_repo    = local.project_source_repo
  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

module "cert-manager" {
  source                 = "./modules/cert-manager/self-signed"
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  enable_service_monitor = local.enable_service_monitor
  target_revision        = local.target_revision
  project_source_repo    = local.project_source_repo
  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

module "knative" {
  source              = "./modules/knative"
  cluster_name        = local.cluster_name
  base_domain         = local.gateway_base_domain
  cluster_issuer      = local.cluster_issuer
  argocd_namespace    = module.argocd_bootstrap.argocd_namespace
  target_revision     = local.target_revision
  project_source_repo = local.project_source_repo
  dependency_ids = {
    istio        = module.istio.id
    cert-manager = module.cert-manager.id
  }
}

module "kserve" {
  source              = "./modules/kserve"
  cluster_name        = local.cluster_name
  argocd_namespace    = module.argocd_bootstrap.argocd_namespace
  target_revision     = local.target_revision
  project_source_repo = local.project_source_repo
  dependency_ids = {
    istio        = module.istio.id
    cert-manager = module.cert-manager.id
    knative      = module.knative.id
  }
}

module "keycloak" {
  source              = "./modules/keycloak"
  cluster_name        = local.cluster_name
  base_domain         = local.base_domain
  cluster_issuer      = local.cluster_issuer
  argocd_namespace    = module.argocd_bootstrap.argocd_namespace
  target_revision     = local.target_revision
  project_source_repo = local.project_source_repo
  dependency_ids = {
    traefik      = module.traefik.id
    cert-manager = module.cert-manager.id
  }
}

module "oidc" {
  source              = "./modules/oidc"
  cluster_name        = local.cluster_name
  base_domain         = local.base_domain
  cluster_issuer      = local.cluster_issuer
  project_source_repo = local.project_source_repo
  dependency_ids = {
    keycloak = module.keycloak.id
  }
}

module "minio" {
  source                 = "./modules/minio"
  cluster_name           = local.cluster_name
  base_domain            = local.base_domain
  cluster_issuer         = local.cluster_issuer
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  enable_service_monitor = local.enable_service_monitor
  oidc                   = module.oidc.oidc
  target_revision        = local.target_revision
  project_source_repo    = local.project_source_repo
  dependency_ids = {
    traefik      = module.traefik.id
    cert-manager = module.cert-manager.id
    oidc         = module.oidc.id
  }
}

module "loki-stack" {
  source           = "./modules/loki-stack/kind"
  argocd_namespace = module.argocd_bootstrap.argocd_namespace
  logs_storage = {
    bucket_name = "loki-bucket"
    endpoint    = module.minio.cluster_dns
    access_key  = module.minio.minio_root_user_credentials.username
    secret_key  = module.minio.minio_root_user_credentials.password
  }
  target_revision     = local.target_revision
  project_source_repo = local.project_source_repo
  dependency_ids = {
    minio = module.minio.id
  }
}

module "thanos" {
  source           = "./modules/thanos/kind"
  cluster_name     = local.cluster_name
  base_domain      = local.base_domain
  cluster_issuer   = local.cluster_issuer
  argocd_namespace = module.argocd_bootstrap.argocd_namespace
  metrics_storage = {
    bucket_name = "thanos-bucket"
    endpoint    = module.minio.cluster_dns
    access_key  = module.minio.minio_root_user_credentials.username
    secret_key  = module.minio.minio_root_user_credentials.password
  }
  thanos = {
    oidc = module.oidc.oidc
  }
  target_revision     = local.target_revision
  project_source_repo = local.project_source_repo
  dependency_ids = {
    argocd       = module.argocd_bootstrap.id
    traefik      = module.traefik.id
    cert-manager = module.cert-manager.id
    minio        = module.minio.id
    keycloak     = module.keycloak.id
    oidc         = module.oidc.id
  }
}

module "kube-prometheus-stack" {
  source           = "./modules/kube-prometheus-stack/kind"
  cluster_name     = local.cluster_name
  base_domain      = local.base_domain
  cluster_issuer   = local.cluster_issuer
  argocd_namespace = module.argocd_bootstrap.argocd_namespace
  metrics_storage = {
    bucket_name = "thanos-bucket"
    endpoint    = module.minio.cluster_dns
    access_key  = module.minio.minio_root_user_credentials.username
    secret_key  = module.minio.minio_root_user_credentials.password
  }
  prometheus = {
    oidc = module.oidc.oidc
  }
  alertmanager = {
    oidc = module.oidc.oidc
  }
  grafana = {
    oidc = module.oidc.oidc
  }
  target_revision     = local.target_revision
  project_source_repo = local.project_source_repo
  dependency_ids = {
    traefik      = module.traefik.id
    cert-manager = module.cert-manager.id
    minio        = module.minio.id
    oidc         = module.oidc.id
  }
}

# module "reflector" {
#   source                 = "./modules/reflector"
#   cluster_name           = local.cluster_name
#   base_domain            = local.base_domain
#   cluster_issuer         = local.cluster_issuer
#   argocd_namespace       = module.argocd_bootstrap.argocd_namespace
#   enable_service_monitor = local.enable_service_monitor
#   target_revision        = local.target_revision
#   project_source_repo    = local.project_source_repo
#   dependency_ids = {
#     argocd = module.argocd_bootstrap.id
#   }
# }

module "postgresql" {
  source                 = "./modules/postgresql"
  cluster_name           = local.cluster_name
  base_domain            = local.base_domain
  cluster_issuer         = local.cluster_issuer
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  enable_service_monitor = local.enable_service_monitor
  target_revision        = local.target_revision
  project_source_repo    = local.project_source_repo
  dependency_ids = {
    traefik = module.traefik.id
    argocd  = module.argocd_bootstrap.id
  }
}

module "spark" {
  source                 = "./modules/spark"
  cluster_name           = local.cluster_name
  base_domain            = local.base_domain
  cluster_issuer         = local.cluster_issuer
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  enable_service_monitor = local.enable_service_monitor
  target_revision        = local.target_revision
  project_source_repo    = local.project_source_repo
  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

module "strimzi" {
  source                 = "./modules/strimzi"
  cluster_name           = local.cluster_name
  base_domain            = local.base_domain
  cluster_issuer         = local.cluster_issuer
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  enable_service_monitor = local.enable_service_monitor
  target_revision        = local.target_revision
  project_source_repo    = local.project_source_repo
  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

module "kafka" {
  source                 = "./modules/kafka"
  cluster_name           = local.cluster_name
  base_domain            = local.base_domain
  cluster_issuer         = local.cluster_issuer
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  enable_service_monitor = local.enable_service_monitor
  target_revision        = local.target_revision
  argocd_project         = module.strimzi.argocd_project_name
  project_source_repo    = local.project_source_repo
  dependency_ids = {
    argocd  = module.argocd_bootstrap.id
    traefik = module.traefik.id
    strimzi = module.strimzi.id
  }
}

module "cp-schema-registry" {
  source                 = "./modules/cp-schema-registry"
  cluster_name           = local.cluster_name
  base_domain            = local.base_domain
  cluster_issuer         = local.cluster_issuer
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  enable_service_monitor = local.enable_service_monitor
  target_revision        = local.target_revision
  argocd_project         = module.strimzi.argocd_project_name
  kafka_broker_name      = module.kafka.broker_name
  project_source_repo    = local.project_source_repo
  dependency_ids = {
    argocd = module.argocd_bootstrap.id
    kafka  = module.kafka.id
  }
}

module "kafka-ui" {
  source                 = "./modules/kafka-ui"
  cluster_name           = local.cluster_name
  base_domain            = local.base_domain
  cluster_issuer         = local.cluster_issuer
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  enable_service_monitor = local.enable_service_monitor
  target_revision        = local.target_revision
  kafka_broker_name      = module.kafka.broker_name
  project_source_repo    = local.project_source_repo
  dependency_ids = {
    argocd             = module.argocd_bootstrap.id
    kafka              = module.kafka.id
    cp-schema-registry = module.cp-schema-registry.id
  }
}

# module "mysql" {
#   source                 = "./modules/mysql"
#   cluster_name           = local.cluster_name
#   base_domain            = local.base_domain
#   cluster_issuer         = local.cluster_issuer
#   argocd_namespace       = module.argocd_bootstrap.argocd_namespace
#   enable_service_monitor = local.enable_service_monitor
#   target_revision        = local.target_revision
#   project_source_repo    = local.project_source_repo
#   dependency_ids = {
#     argocd  = module.argocd_bootstrap.id
#     traefik = module.traefik.id
#   }
# }

# module "vault" {
#   source                 = "./modules/vault"
#   cluster_name           = local.cluster_name
#   base_domain            = local.base_domain
#   cluster_issuer         = local.cluster_issuer
#   argocd_namespace       = module.argocd_bootstrap.argocd_namespace
#   enable_service_monitor = local.enable_service_monitor
#   target_revision        = local.target_revision
#   project_source_repo    = local.project_source_repo
#   dependency_ids = {
#     argocd  = module.argocd_bootstrap.id
#     traefik = module.traefik.id
#   }
# }

# module "pinot" {
#   source                 = "./modules/pinot"
#   cluster_name           = local.cluster_name
#   base_domain            = local.base_domain
#   cluster_issuer         = local.cluster_issuer
#   argocd_namespace       = module.argocd_bootstrap.argocd_namespace
#   enable_service_monitor = local.enable_service_monitor
#   target_revision        = local.target_revision
#   storage = {
#     bucket_name       = "pinot"
#     endpoint          = module.minio.cluster_dns
#     access_key        = module.minio.minio_root_user_credentials.username
#     secret_access_key = module.minio.minio_root_user_credentials.password
#   }
#   project_source_repo = local.project_source_repo
#   dependency_ids = {
#     argocd  = module.argocd_bootstrap.id
#     traefik = module.traefik.id
#     oidc    = module.oidc.id
#     minio   = module.minio.id
#   }
# }

# module "trino" {
#   source                 = "./modules/trino"
#   cluster_name           = local.cluster_name
#   base_domain            = local.base_domain
#   cluster_issuer         = local.cluster_issuer
#   argocd_namespace       = module.argocd_bootstrap.argocd_namespace
#   enable_service_monitor = local.enable_service_monitor
#   target_revision        = local.target_revision
#   pinot_dns              = module.pinot.cluster_dns
#   storage = {
#     bucket_name       = "trino"
#     endpoint          = module.minio.cluster_dns
#     access_key        = module.minio.minio_root_user_credentials.username
#     secret_access_key = module.minio.minio_root_user_credentials.password
#   }
#   database = {
#     user     = module.postgresql.credentials.user
#     password = module.postgresql.credentials.password
#     database = "curated"
#     service  = module.postgresql.cluster_ip
#   }
#   project_source_repo = local.project_source_repo
#   dependency_ids = {
#     argocd     = module.argocd_bootstrap.id
#     traefik    = module.traefik.id
#     oidc       = module.oidc.id
#     minio      = module.minio.id
#     postgresql = module.postgresql.id
#     pinot      = module.pinot.id
#   }
# }

module "mlflow" {
  source                 = "./modules/mlflow"
  cluster_name           = local.cluster_name
  base_domain            = local.base_domain
  cluster_issuer         = local.cluster_issuer
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  enable_service_monitor = local.enable_service_monitor
  target_revision        = local.target_revision
  storage = {
    bucket_name       = "mlflow"
    endpoint          = module.minio.cluster_dns
    access_key        = module.minio.minio_root_user_credentials.username
    secret_access_key = module.minio.minio_root_user_credentials.password
  }
  database = {
    user     = module.postgresql.credentials.user
    password = module.postgresql.credentials.password
    database = "mlflow"
    service  = module.postgresql.cluster_dns
  }
  project_source_repo = local.project_source_repo
  dependency_ids = {
    argocd     = module.argocd_bootstrap.id
    traefik    = module.traefik.id
    minio      = module.minio.id
    postgresql = module.postgresql.id
  }
}

# # module "ray" {
# #   source                 = "./modules/ray"
# #   cluster_name           = local.cluster_name
# #   base_domain            = local.base_domain
# #   cluster_issuer         = local.cluster_issuer
# #   argocd_namespace       = module.argocd_bootstrap.argocd_namespace
# #   enable_service_monitor = local.enable_service_monitor
# #   target_revision        = local.target_revision
# #   project_source_repo    = local.project_source_repo
# #   dependency_ids = {
# #     argocd  = module.argocd_bootstrap.id
# #     traefik = module.traefik.id
# #   }
# # }

module "jupyterhub" {
  source                 = "./modules/jupyterhub"
  cluster_name           = local.cluster_name
  base_domain            = local.base_domain
  cluster_issuer         = local.cluster_issuer
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  enable_service_monitor = local.enable_service_monitor
  target_revision        = local.target_revision
  oidc                   = module.oidc.oidc
  storage = {
    bucket_name       = "jupyterhub"
    endpoint          = module.minio.cluster_dns
    access_key        = module.minio.minio_root_user_credentials.username
    secret_access_key = module.minio.minio_root_user_credentials.password
  }
  database = {
    user     = module.postgresql.credentials.user
    password = module.postgresql.credentials.password
    database = "jupyterhub"
    endpoint = module.postgresql.cluster_dns
  }
  mlflow = {
    endpoint = module.mlflow.cluster_dns
  }
  # ray = {
  #   endpoint = module.ray.cluster_dns
  # }
  project_source_repo = local.project_source_repo
  dependency_ids = {
    argocd     = module.argocd_bootstrap.id
    traefik    = module.traefik.id
    oidc       = module.oidc.id
    minio      = module.minio.id
    postgresql = module.postgresql.id
    mlflow     = module.mlflow.id
    # ray        = module.ray.id
  }
}

# module "airflow" {
#   source                 = "./modules/airflow"
#   cluster_name           = local.cluster_name
#   base_domain            = local.base_domain
#   cluster_issuer         = local.cluster_issuer
#   argocd_namespace       = module.argocd_bootstrap.argocd_namespace
#   enable_service_monitor = local.enable_service_monitor
#   target_revision        = local.target_revision
#   oidc                   = module.oidc.oidc
#   fernetKey              = local.airflow_fernetKey
#   storage = {
#     bucket_name       = "airflow"
#     endpoint          = module.minio.cluster_dns
#     access_key        = module.minio.minio_root_user_credentials.username
#     secret_access_key = module.minio.minio_root_user_credentials.password
#   }
#   database = {
#     user     = module.postgresql.credentials.user
#     password = module.postgresql.credentials.password
#     database = "airflow"
#     endpoint = module.postgresql.cluster_dns
#   }
#   mlflow = {
#     endpoint = module.mlflow.cluster_dns
#   }
#   # ray = {
#   #   endpoint = module.ray.cluster_dns
#   # }
#   project_source_repo = local.project_source_repo
#   dependency_ids = {
#     argocd     = module.argocd_bootstrap.id
#     traefik    = module.traefik.id
#     oidc       = module.oidc.id
#     minio      = module.minio.id
#     postgresql = module.postgresql.id
#     mlflow     = module.mlflow.id
#     # ray        = module.ray.id
#   }
# }

# module "gitlab" {
#   source                 = "./modules/gitlab"
#   cluster_name           = local.cluster_name
#   base_domain            = local.base_domain
#   cluster_issuer         = local.cluster_issuer
#   argocd_namespace       = module.argocd_bootstrap.argocd_namespace
#   enable_service_monitor = local.enable_service_monitor
#   target_revision        = local.target_revision
#   oidc                   = module.oidc.oidc
#   metrics_storage = {
#     bucket_name       = "registry"
#     endpoint          = module.minio.cluster_dns
#     access_key        = module.minio.minio_root_user_credentials.username
#     secret_access_key = module.minio.minio_root_user_credentials.password
#   }
#   project_source_repo = local.project_source_repo
#   dependency_ids = {
#     argocd     = module.argocd_bootstrap.id
#     traefik    = module.traefik.id
#     oidc       = module.oidc.id
#     minio      = module.minio.id
#     postgresql = module.postgresql.id
#   }
# }

module "argocd" {
  source                   = "./modules/argocd"
  base_domain              = local.base_domain
  cluster_name             = local.cluster_name
  cluster_issuer           = local.cluster_issuer
  server_secretkey         = module.argocd_bootstrap.argocd_server_secretkey
  accounts_pipeline_tokens = module.argocd_bootstrap.argocd_accounts_pipeline_tokens
  admin_enabled            = false
  exec_enabled             = true
  oidc = {
    name         = "OIDC"
    issuer       = module.oidc.oidc.issuer_url
    clientID     = module.oidc.oidc.client_id
    clientSecret = module.oidc.oidc.client_secret
    requestedIDTokenClaims = {
      groups = {
        essential = true
      }
    }
  }
  rbac = {
    policy_csv = <<-EOT
      g, pipeline, role:admin
      g, modern-gitops-stack-admins, role:admin
    EOT
  }
  target_revision     = local.target_revision
  project_source_repo = local.project_source_repo
  dependency_ids = {
    traefik               = module.traefik.id
    cert-manager          = module.cert-manager.id
    oidc                  = module.oidc.id
    kube-prometheus-stack = module.kube-prometheus-stack.id
  }
}


# kubectl apply -n kserve-test -f - <<EOF
# apiVersion: "serving.kserve.io/v1beta1"
# kind: "InferenceService"
# metadata:
#   name: "sklearn-iris"
# annotations:
#   serving.kserve.io/enable-prometheus-scraping: "true"
# spec:
#   predictor:
#     model:
#       args: ["--enable_docs_url=True"]
#       modelFormat:
#         name: sklearn
#       protocolVersion: v2
#       storageUri: "s3://mlflow/0/094aee50826a45c09a2227ce8589ee3d/artifacts/random-forest-model/model.pkl"
# EOF

# cat <<EOF > "./iris-input.json"
# {
#   "instances": [
#     [6.8,  2.8],
#     [6.0,  3.4]
#   ]
# }
# EOF


module "zookeeper" {
  source                 = "./modules/zookeeper"
  cluster_name           = local.cluster_name
  base_domain            = local.base_domain
  cluster_issuer         = local.cluster_issuer
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  enable_service_monitor = local.enable_service_monitor
  oidc                   = module.oidc.oidc
  target_revision        = local.target_revision
  project_source_repo    = local.project_source_repo
  dependency_ids = {
    traefik      = module.traefik.id
    cert-manager = module.cert-manager.id
    oidc         = module.oidc.id
  }
}

module "nifi" {
  source                 = "./modules/nifi"
  cluster_name           = local.cluster_name
  base_domain            = local.base_domain
  cluster_issuer         = local.cluster_issuer
  argocd_namespace       = module.argocd_bootstrap.argocd_namespace
  enable_service_monitor = local.enable_service_monitor
  oidc                   = module.oidc.oidc
  target_revision        = local.target_revision
  project_source_repo    = local.project_source_repo
  dependency_ids = {
    traefik      = module.traefik.id
    cert-manager = module.cert-manager.id
    oidc         = module.oidc.id
    zookeeper    = module.zookeeper.id
  }
}
