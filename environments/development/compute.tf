resource "google_compute_disk" "langfuse_data" {
  name = "cosmos-langfuse-dev-data"
  type = "pd-balanced"
  zone = var.zone
  size = 100
}

resource "google_compute_resource_policy" "langfuse_snapshot" {
  name   = "cosmos-langfuse-dev-daily-snapshot"
  region = var.region

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "18:00"
      }
    }

    retention_policy {
      max_retention_days    = 7
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }

    snapshot_properties {
      storage_locations = [var.region]
      guest_flush       = false
    }
  }
}

resource "google_compute_disk_resource_policy_attachment" "langfuse_snapshot" {
  name = google_compute_resource_policy.langfuse_snapshot.name
  disk = google_compute_disk.langfuse_data.name
  zone = var.zone
}

resource "google_compute_instance" "langfuse" {
  name         = local.langfuse_name
  zone         = var.zone
  machine_type = var.langfuse_machine_type
  tags         = ["cosmos-web", "cosmos-iap-ssh", "cosmos-langfuse"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      type  = "pd-balanced"
      size  = 30
    }
  }

  attached_disk {
    source      = google_compute_disk.langfuse_data.id
    device_name = "langfuse-data"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.cosmos.id
    network_ip = "10.42.0.20"

    access_config {
      nat_ip = google_compute_address.langfuse.address
    }
  }

  service_account {
    email  = google_service_account.langfuse.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = templatefile("${path.module}/../../templates/langfuse-startup.sh.tftpl", {
    project_id         = var.project_id
    langfuse_host      = "langfuse.${replace(google_compute_address.langfuse.address, ".", "-")}.nip.io"
    langfuse_image_tag = var.langfuse_image_tag
    caddy_image_tag    = var.caddy_image_tag
    postgres_image     = var.postgres_image
    clickhouse_image   = var.clickhouse_image
    redis_image        = var.redis_image
    minio_image        = var.minio_image
    compose_b64        = base64encode(file("${path.module}/../../templates/langfuse-compose.yml"))
    caddyfile_b64      = base64encode(file("${path.module}/../../templates/langfuse.Caddyfile"))
    ops_agent_b64      = base64encode(file("${path.module}/../../templates/langfuse-ops-agent.yaml"))
    retention_script_b64 = base64encode(
      file("${path.module}/../../scripts/prune-langfuse-traces.sh")
    )
  })

  depends_on = [
    google_secret_manager_secret_iam_member.langfuse,
    google_compute_disk_resource_policy_attachment.langfuse_snapshot,
  ]
}

resource "google_compute_instance" "api" {
  name         = local.api_instance_name
  zone         = var.zone
  machine_type = var.api_machine_type
  tags         = ["cosmos-web", "cosmos-iap-ssh", "cosmos-api"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      type  = "pd-balanced"
      size  = 30
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.cosmos.id
    network_ip = "10.42.0.10"

    access_config {
      nat_ip = google_compute_address.api.address
    }
  }

  service_account {
    email  = google_service_account.api.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = templatefile("${path.module}/../../templates/api-startup.sh.tftpl", {
    project_id        = var.project_id
    region            = var.region
    api_host          = "api.${replace(google_compute_address.api.address, ".", "-")}.nip.io"
    langfuse_url      = "http://${google_compute_instance.langfuse.network_interface[0].network_ip}:3000"
    caddy_image_tag   = var.caddy_image_tag
    compose_b64       = base64encode(file("${path.module}/../../templates/api-compose.yml"))
    caddyfile_b64     = base64encode(file("${path.module}/../../templates/api.Caddyfile"))
    ops_agent_b64     = base64encode(file("${path.module}/../../templates/api-ops-agent.yaml"))
    deploy_script_b64 = base64encode(file("${path.module}/../../scripts/deploy-api.sh"))
  })

  depends_on = [
    google_secret_manager_secret_iam_member.api,
    google_artifact_registry_repository_iam_member.api_reader,
  ]
}
