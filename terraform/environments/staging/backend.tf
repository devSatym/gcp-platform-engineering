terraform {
  backend "gcs" {
    prefix = "staging/foundation"
  }
}
