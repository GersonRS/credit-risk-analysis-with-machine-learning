resource "null_resource" "dependencies" {
  triggers = var.dependency_ids
}

resource "random_password" "db_password" {
  count   = var.database == null ? 1 : 0
  length  = 32
  special = false
}

resource "argocd_project" "this" {
  metadata {
    name      = "knative"
    namespace = var.argocd_namespace
  }

  spec {
    description = "knative application project"
    source_repos = [
      "https://github.com/GersonRS/credit-risk-analysis-with-machine-learning.git",
    ]

    destination {
      name      = "in-cluster"
      namespace = var.namespace
    }

    orphaned_resources {
      warn = true
    }

    cluster_resource_whitelist {
      group = "*"
      kind  = "*"
    }
  }
}

data "utils_deep_merge_yaml" "values" {
  input = [for i in concat(local.helm_values, var.helm_values) : yamlencode(i)]
}

resource "argocd_application" "operator" {
  metadata {
    name      = "knative-operator"
    namespace = var.argocd_namespace
  }

  wait = var.app_autosync == { "allow_empty" = tobool(null), "prune" = tobool(null), "self_heal" = tobool(null) } ? false : true

  spec {
    project = argocd_project.this.metadata.0.name

    source {
      repo_url        = var.project_source_repo
      path            = "charts/knative-operator"
      target_revision = var.target_revision
    }

    destination {
      name      = "in-cluster"
      namespace = var.namespace
    }

    sync_policy {
      dynamic "automated" {
        for_each = toset(var.app_autosync == { "allow_empty" = tobool(null), "prune" = tobool(null), "self_heal" = tobool(null) } ? [] : [var.app_autosync])
        content {
          prune       = automated.value.prune
          self_heal   = automated.value.self_heal
          allow_empty = automated.value.allow_empty
        }
      }

      retry {
        backoff {
          duration     = "20s"
          max_duration = "2m"
          factor       = "2"
        }
        limit = "5"
      }

      sync_options = [
        "CreateNamespace=true"
      ]
    }
  }

  depends_on = [
    resource.null_resource.dependencies,
  ]
}

resource "argocd_application" "serving" {
  metadata {
    name      = "knative-serving"
    namespace = var.argocd_namespace
  }

  timeouts {
    create = "15m"
    delete = "15m"
  }

  wait = var.app_autosync == { "allow_empty" = tobool(null), "prune" = tobool(null), "self_heal" = tobool(null) } ? false : true

  spec {
    project = argocd_project.this.metadata.0.name

    source {
      repo_url        = var.project_source_repo
      path            = "charts/knative-serving"
      target_revision = var.target_revision
      helm {
        values = data.utils_deep_merge_yaml.values.output
      }
    }

    destination {
      name      = "in-cluster"
      namespace = var.namespace
    }

    sync_policy {
      dynamic "automated" {
        for_each = toset(var.app_autosync == { "allow_empty" = tobool(null), "prune" = tobool(null), "self_heal" = tobool(null) } ? [] : [var.app_autosync])
        content {
          prune       = automated.value.prune
          self_heal   = automated.value.self_heal
          allow_empty = automated.value.allow_empty
        }
      }
      retry {
        backoff {
          duration     = "20s"
          max_duration = "5m"
          factor       = "2"
        }
        limit = "5"
      }

      sync_options = [
        "CreateNamespace=true"
      ]
    }
  }

  depends_on = [
    resource.argocd_application.operator,
  ]
}


resource "null_resource" "wait_for_knative" {
  provisioner "local-exec" {
    command = <<EOT
    while [ $(curl -k https://knative.apps.${var.cluster_name}.${var.base_domain} -I -s | head -n 1 | cut -d' ' -f2) != '200' ]; do
      sleep 5
    done
    EOT
  }

  depends_on = [
    resource.argocd_application.this,
  ]
}

data "kubernetes_secret" "admin_credentials" {
  metadata {
    name      = "knative-initial-admin"
    namespace = var.namespace
  }
  depends_on = [
    resource.null_resource.wait_for_knative,
  ]
}

resource "null_resource" "this" {
  depends_on = [
    resource.null_resource.wait_for_knative,
  ]
}
