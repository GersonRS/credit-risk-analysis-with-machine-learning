locals {
  helm_values = [{
    zookeeper = {
      global = {
        storageClass = "standard"
      }
      replicaCount = 1
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
    }
  }]
}
