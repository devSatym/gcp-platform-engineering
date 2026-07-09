terraform {
  backend "gcs" {
    # !! UPDATE THIS: replace with your actual GCS bucket name !!
    bucket = "platform-engineering-demo-tf-state"
    prefix = "prod/foundation"
  }
}
