resource "google_service_account" "api" {
  account_id   = "cosmos-api-dev"
  display_name = "Cosmos API development VM"
}

resource "google_service_account" "langfuse" {
  account_id   = "cosmos-langfuse-dev"
  display_name = "Cosmos Langfuse development VM"
}

resource "google_service_account" "deployer" {
  account_id   = "cosmos-api-deployer"
  display_name = "Cosmos API GitHub deployer"
}

locals {
  api_project_roles = toset([
    "roles/aiplatform.user",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])
  langfuse_project_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])
  deployer_project_roles = toset([
    "roles/compute.osAdminLogin",
    "roles/compute.viewer",
    "roles/iap.tunnelResourceAccessor",
  ])
  api_secret_ids = toset([
    "cosmos-supabase-url",
    "cosmos-supabase-service-role-key",
    "cosmos-kakao-admin-key",
    "cosmos-docs-basic-auth-hash",
    "cosmos-langfuse-public-key",
    "cosmos-langfuse-secret-key",
  ])
  langfuse_secret_ids = setsubtract(local.secret_ids, toset([
    "cosmos-supabase-url",
    "cosmos-supabase-service-role-key",
    "cosmos-kakao-admin-key",
    "cosmos-docs-basic-auth-hash",
  ]))
}

resource "google_project_iam_member" "api" {
  for_each = local.api_project_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.api.email}"
}

resource "google_project_iam_member" "langfuse" {
  for_each = local.langfuse_project_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.langfuse.email}"
}

resource "google_project_iam_member" "deployer" {
  for_each = local.deployer_project_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_artifact_registry_repository_iam_member" "api_reader" {
  location   = google_artifact_registry_repository.cosmos.location
  repository = google_artifact_registry_repository.cosmos.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.api.email}"
}

resource "google_artifact_registry_repository_iam_member" "deployer_writer" {
  location   = google_artifact_registry_repository.cosmos.location
  repository = google_artifact_registry_repository.cosmos.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_secret_manager_secret_iam_member" "api" {
  for_each  = local.api_secret_ids
  secret_id = google_secret_manager_secret.development[each.value].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

resource "google_secret_manager_secret_iam_member" "langfuse" {
  for_each  = local.langfuse_secret_ids
  secret_id = google_secret_manager_secret.development[each.value].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.langfuse.email}"
}

resource "google_service_account_iam_member" "deployer_github" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${local.github_pool_name}/attribute.repository/${var.github_organization}/cosmos_server"
}

resource "google_service_account_iam_member" "deployer_use_api" {
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}
