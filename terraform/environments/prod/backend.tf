terraform {
  backend "gcs" {
    prefix = "prod/foundation"
  }
}
