resource "random_password" "password_secret" {
  length  = 32
  special = false
}

resource "kubernetes_namespace" "postgresql_namespace" {
  metadata {
    annotations = {
      name = var.namespace
    }
    name = var.namespace
  }
}

resource "kubernetes_secret" "postgresql_secret" {
  metadata {
    name      = "postgres-secrets"
    namespace = var.namespace
    annotations = {
      "postgresql.v1.k8s.emberstack.com/reflection-auto-enabled" : "true"
      "postgresql.v1.k8s.emberstack.com/reflection-allowed" : "true"
      "postgresql.v1.k8s.emberstack.com/reflection-allowed-namespaces" : "${var.namespace},processing"
    }
  }

  data = {
    password               = "${resource.random_password.password_secret.result}"
    postgres-password      = "${resource.random_password.password_secret.result}"
    replicationPasswordKey = "${resource.random_password.password_secret.result}"
  }

  depends_on = [kubernetes_namespace.postgresql_namespace]
}

resource "null_resource" "dependencies" {
  triggers = var.dependency_ids
}

resource "argocd_project" "this" {
  count = var.argocd_project == null ? 1 : 0

  metadata {
    name      = var.destination_cluster != "in-cluster" ? "postgresql-${var.destination_cluster}" : "postgresql"
    namespace = var.argocd_namespace
    annotations = {
      "modern-gitops-stack.io/argocd_namespace" = var.argocd_namespace
    }
  }

  spec {
    description  = "Postgres application project for cluster ${var.destination_cluster}"
    source_repos = ["https://github.com/GersonRS/credit-risk-analysis-with-machine-learning.git"]

    destination {
      name      = var.destination_cluster
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

resource "argocd_application" "this" {
  metadata {
    name      = var.destination_cluster != "in-cluster" ? "postgresql-${var.destination_cluster}" : "postgresql"
    namespace = var.argocd_namespace
    labels = merge({
      "application" = "postgresql"
      "cluster"     = var.destination_cluster
    }, var.argocd_labels)
  }

  timeouts {
    create = "15m"
    delete = "15m"
  }

  wait = var.app_autosync == { "allow_empty" = tobool(null), "prune" = tobool(null), "self_heal" = tobool(null) } ? false : true

  spec {
    project = var.argocd_project == null ? argocd_project.this[0].metadata.0.name : var.argocd_project

    source {
      repo_url        = "https://github.com/GersonRS/credit-risk-analysis-with-machine-learning.git"
      path            = "charts/postgresql"
      target_revision = var.target_revision
      helm {
        values = data.utils_deep_merge_yaml.values.output
      }
    }

    destination {
      name      = var.destination_cluster
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

resource "null_resource" "this" {
  depends_on = [
    resource.argocd_application.this,
  ]
}

data "kubernetes_service" "postgresql" {
  metadata {
    name      = "postgresql"
    namespace = var.namespace
  }

  depends_on = [
    null_resource.this
  ]
}
