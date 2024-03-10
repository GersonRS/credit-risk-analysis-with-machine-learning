resource "null_resource" "dependencies" {
  triggers = var.dependency_ids
}

resource "argocd_project" "this" {
  count = var.argocd_project == null ? 1 : 0

  metadata {
    name      = var.destination_cluster != "in-cluster" ? "knative-${var.destination_cluster}" : "knative"
    namespace = var.argocd_namespace
    annotations = {
      "modern-gitops-stack.io/argocd_namespace" = var.argocd_namespace
    }
  }

  spec {
    description  = "knative application project for cluster ${var.destination_cluster}"
    source_repos = [var.project_source_repo]


    destination {
      name      = var.destination_cluster
      namespace = var.namespace
    }

    destination {
      name      = var.destination_cluster
      namespace = "istio-system"
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

resource "argocd_application" "serving_crds" {
  metadata {
    name      = var.destination_cluster != "in-cluster" ? "knative-serving-crds-${var.destination_cluster}" : "knative-serving-crds"
    namespace = var.argocd_namespace
    labels = merge({
      "application" = "knative-serving-crds"
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
      path            = "charts/knative-serving/crds"
      target_revision = var.target_revision
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
        limit = "0"
      }
    }
  }

  depends_on = [
    resource.null_resource.dependencies,
  ]
}

resource "argocd_application" "this" {
  metadata {
    name      = var.destination_cluster != "in-cluster" ? "knative-serving-${var.destination_cluster}" : "knative-serving"
    namespace = var.argocd_namespace
    labels = merge({
      "application" = "knative-serving"
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
      path            = "charts/knative-serving/templates"
      target_revision = var.target_revision
      directory {
        recurse = true
      }
    }

    ignore_difference {
      group         = "admissionregistration.k8s.io"
      kind          = "MutatingWebhookConfiguration"
      name          = "webhook.domainmapping.serving.knative.dev"
      json_pointers = ["/webhooks/0/rules"]
    }

    ignore_difference {
      group         = "admissionregistration.k8s.io"
      kind          = "MutatingWebhookConfiguration"
      name          = "webhook.serving.knative.dev"
      json_pointers = ["/webhooks/0/rules"]
    }

    ignore_difference {
      group         = "admissionregistration.k8s.io"
      kind          = "ValidatingWebhookConfiguration"
      name          = "validation.webhook.domainmapping.serving.knative.dev"
      json_pointers = ["/webhooks/0/rules"]
    }
    ignore_difference {
      group         = "admissionregistration.k8s.io"
      kind          = "ValidatingWebhookConfiguration"
      name          = "validation.webhook.serving.knative.dev"
      json_pointers = ["/webhooks/0/rules"]
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
          allow_empty = true
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

      managed_namespace_metadata {
        labels = {
          "app.kubernetes.io/name"    = "knative-serving"
          "app.kubernetes.io/version" = "1.10.1"
        }
      }
    }
  }

  depends_on = [
    resource.argocd_application.serving_crds
  ]
}

resource "null_resource" "this" {
  depends_on = [
    resource.argocd_application.this,
  ]
}

resource "kubernetes_config_map_v1_data" "patch" {
  metadata {
    name      = "config-domain"
    namespace = var.namespace
  }
  data = {
    "${var.base_domain}" = ""
  }
  depends_on = [
    resource.argocd_application.this,
  ]
}
