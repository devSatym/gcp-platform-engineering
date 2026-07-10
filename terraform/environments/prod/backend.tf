terraform {
  backend "gcs" {
    # !! UPDATE THIS: replace with your actual GCS bucket name !!
    bucket = "valiant-house-502004-k2-tf-state"
    prefix = "prod/foundation"
  }
}
