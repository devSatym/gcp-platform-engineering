terraform {
  backend "gcs" {
    bucket = "valiant-house-502004-k2-tfstate"
    prefix = "dev/foundation"
  }
}
