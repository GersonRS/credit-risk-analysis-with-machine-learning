locals {
  helm_values = [{
    global = {
      storageClass = "standard"
    }
    replicaCount = 3
    resources = {
      requests = {
        memory = "256Mi"
        cpu    = "250m"
      }
      limits = {
        memory = "256Mi"
        cpu    = "250m"
      }
    }
    networkPolicy = {
      enabled = true
    }
  }]
}
