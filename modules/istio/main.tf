resource "null_resource" "dependencies" {
  triggers = var.dependency_ids
}

resource "argocd_project" "this" {
  count = var.argocd_project == null ? 1 : 0

  metadata {
    name      = var.destination_cluster != "in-cluster" ? "istio-${var.destination_cluster}" : "istio"
    namespace = var.argocd_namespace
    annotations = {
      "modern-gitops-stack.io/argocd_namespace" = var.argocd_namespace
    }
  }

  spec {
    description  = "istio application project for cluster ${var.destination_cluster}"
    source_repos = [var.project_source_repo]


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

resource "argocd_application" "base" {
  metadata {
    name      = var.destination_cluster != "in-cluster" ? "istio-base-${var.destination_cluster}" : "istio-base"
    namespace = var.argocd_namespace
    labels = merge({
      "application" = "istio-base"
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
      repo_url        = var.project_source_repo
      path            = "charts/istio-base"
      target_revision = var.target_revision
      helm {
        values = data.utils_deep_merge_yaml.values.output
      }
    }

    ignore_difference {
      group         = "admissionregistration.k8s.io"
      kind          = "ValidatingWebhookConfiguration"
      name          = "istiod-default-validator"
      json_pointers = ["/webhooks/0/failurePolicy"]
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
        "CreateNamespace=true",
      ]

      # managed_namespace_metadata {
      #   labels = {
      #     "istio-injection" = "disabled"
      #   }
      # }
    }
  }

  depends_on = [
    resource.null_resource.dependencies,
  ]
}

resource "argocd_application" "istiod" {
  metadata {
    name      = var.destination_cluster != "in-cluster" ? "istio-istiod-${var.destination_cluster}" : "istio-istiod"
    namespace = var.argocd_namespace
    labels = merge({
      "application" = "istio-istiod"
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
      repo_url        = var.project_source_repo
      path            = "charts/istio-istiod"
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
    }
  }

  depends_on = [
    resource.argocd_application.base
  ]
}

resource "argocd_application" "gateway" {
  metadata {
    name      = var.destination_cluster != "in-cluster" ? "istio-ingressgateway-${var.destination_cluster}" : "istio-ingressgateway"
    namespace = var.argocd_namespace
    labels = merge({
      "application" = "istio-ingressgateway"
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
      repo_url        = var.project_source_repo
      path            = "charts/istio-gateway"
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
    }
  }

  depends_on = [
    resource.argocd_application.istiod
  ]
}

resource "null_resource" "this" {
  depends_on = [
    resource.argocd_application.gateway,
  ]
}

data "kubernetes_service" "istio" {
  metadata {
    name      = "istio-ingressgateway"
    namespace = var.namespace
  }

  depends_on = [
    resource.argocd_application.gateway,
  ]
}
