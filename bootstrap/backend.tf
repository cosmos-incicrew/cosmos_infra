terraform {
  backend "gcs" {
    bucket = "kt-tech-up-01-cosmos-terraform-state"
    prefix = "bootstrap"
  }
}
