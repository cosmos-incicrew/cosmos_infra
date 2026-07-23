data "google_project" "current" {}

data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2404-lts-amd64"
  project = "ubuntu-os-cloud"
}

locals {
  artifact_repository = "cosmos"
  api_instance_name   = "cosmos-api-dev"
  langfuse_name       = "cosmos-langfuse-dev"
  github_pool_name    = "projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/github"

  secret_ids = toset([
    "cosmos-supabase-url",
    "cosmos-supabase-service-role-key",
    "cosmos-kakao-admin-key",
    "cosmos-docs-basic-auth-hash",
    "cosmos-langfuse-public-key",
    "cosmos-langfuse-secret-key",
    "cosmos-langfuse-disable-signup",
    "cosmos-langfuse-nextauth-secret",
    "cosmos-langfuse-salt",
    "cosmos-langfuse-encryption-key",
    "cosmos-langfuse-postgres-password",
    "cosmos-langfuse-clickhouse-password",
    "cosmos-langfuse-redis-password",
    "cosmos-langfuse-minio-password",
    "cosmos-langfuse-init-user-email",
    "cosmos-langfuse-init-user-password",
  ])
}

resource "google_compute_network" "cosmos" {
  name                    = "cosmos-development"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "cosmos" {
  name          = "cosmos-development-${var.region}"
  region        = var.region
  network       = google_compute_network.cosmos.id
  ip_cidr_range = "10.42.0.0/24"
}

resource "google_compute_firewall" "web" {
  name    = "cosmos-development-web"
  network = google_compute_network.cosmos.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["cosmos-web"]
}

resource "google_compute_firewall" "iap_ssh" {
  name    = "cosmos-development-iap-ssh"
  network = google_compute_network.cosmos.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["cosmos-iap-ssh"]
}

resource "google_compute_firewall" "api_to_langfuse" {
  name    = "cosmos-development-api-to-langfuse"
  network = google_compute_network.cosmos.name

  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }

  source_tags = ["cosmos-api"]
  target_tags = ["cosmos-langfuse"]
}

resource "google_compute_address" "api" {
  name   = "cosmos-api-dev"
  region = var.region
}

resource "google_compute_address" "langfuse" {
  name   = "cosmos-langfuse-dev"
  region = var.region
}

resource "google_artifact_registry_repository" "cosmos" {
  location      = var.region
  repository_id = local.artifact_repository
  format        = "DOCKER"
  description   = "Immutable Cosmos application images"
}

resource "google_secret_manager_secret" "development" {
  for_each = local.secret_ids

  secret_id = each.value

  replication {
    auto {}
  }
}
