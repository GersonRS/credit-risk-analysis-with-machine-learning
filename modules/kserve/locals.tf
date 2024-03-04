locals {
  helm_values = [{
    kserving = {
      certManager = {
        enabled = false
      }
      kserve = {
        storage = {
          s3 = {
            accessKeyIdName     = "AWS_ACCESS_KEY_ID"
            secretAccessKeyName = "AWS_SECRET_ACCESS_KEY"
          }
        }
      }
    }
  }]
}
