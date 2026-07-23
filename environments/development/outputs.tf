output "api_url" {
  value = "https://api.${replace(google_compute_address.api.address, ".", "-")}.nip.io"
}

output "langfuse_url" {
  value = "https://langfuse.${replace(google_compute_address.langfuse.address, ".", "-")}.nip.io"
}

output "api_instance" {
  value = google_compute_instance.api.name
}

output "api_zone" {
  value = var.zone
}

output "artifact_repository" {
  value = google_artifact_registry_repository.cosmos.repository_id
}

output "deploy_service_account" {
  value = google_service_account.deployer.email
}
