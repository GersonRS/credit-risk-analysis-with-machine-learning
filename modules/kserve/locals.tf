locals {
  helm_values = [{
    kserve = {
      certManager = {
        enabled = false
      }
      "cert-manager" = {
        enabled = false
      }
    }
  }]
}
