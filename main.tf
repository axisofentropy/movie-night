# Configure the Google Cloud provider
terraform {
  backend "gcs" {
    bucket  = "movie-night-vollrath-tfstate"
    prefix  = "state" # A folder within the bucket for this project's state
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    discord-interactions = {
      source  = "roleypoly/discord-interactions"
      version = "0.1.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "discord-interactions" {
  application_id           = var.discord_application_id
  client_credentials_token = var.discord_client_credentials_token
}

# --- API ENABLER ---
# This block iterates through the list of APIs defined in variables.tf
# and enables each one for the project.
resource "google_project_service" "apis" {
  for_each = toset(var.gcp_apis)
  project  = var.gcp_project_id
  service  = each.value

  # This is important! It prevents Terraform from disabling the APIs
  # when you run 'terraform destroy'.
  disable_on_destroy = false
}

# --- GCS BUCKET FOR STARTUP SCRIPT ---
resource "google_storage_bucket" "projector_vm_config" {
  name          = "${var.gcp_project_id}-movie-projector-scripts"
  location      = var.gcp_region
  force_destroy = true

  versioning {
    enabled = true
  }

  # Explicitly depend on the APIs being enabled first.
  depends_on = [google_project_service.apis]
}

resource "google_storage_bucket_object" "startup_script" {
  name   = "startup.sh"
  bucket = google_storage_bucket.projector_vm_config.name
  source = "${path.module}/startup-script.sh"
}

resource "google_storage_bucket_object" "mediamtx_config" {
  name   = "mediamtx.yml"
  bucket = google_storage_bucket.projector_vm_config.name
  source = "${path.module}/mediamtx.yml"
}

# --- SERVICE ACCOUNT & IAM ---
resource "google_service_account" "movie_projector_sa" {
  account_id   = "movie-projector-sa"
  display_name = "Service Account for Movie Night VM"
  depends_on   = [google_project_service.apis]
}

resource "google_storage_bucket_iam_member" "startup_script_reader" {
  bucket = google_storage_bucket.projector_vm_config.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.movie_projector_sa.email}"
}

resource "google_project_iam_member" "secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.movie_projector_sa.email}"
}

resource "google_project_iam_member" "logging_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.movie_projector_sa.email}"
}

resource "google_project_iam_member" "monitoring_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.movie_projector_sa.email}"
}

# Grant the VM's service account permission to manage Cloud DNS records.
resource "google_project_iam_member" "dns_admin" {
  project = var.gcp_project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.movie_projector_sa.email}"
}

# --- DISCORD BOT SERVICE ACCOUNT & IAM ---
resource "google_project_iam_custom_role" "mig_scaler" {
  project     = var.gcp_project_id
  role_id     = "migScaler"
  title       = "MIG Scaler Role"
  description = "Allows resizing a Managed Instance Group"
  permissions = [
    "compute.instanceGroupManagers.update",
  ]
}

resource "google_service_account" "discord_bot_sa" {
  account_id   = "discord-bot-sa"
  display_name = "Service Account for Discord Bot on Cloud Run"
  depends_on   = [google_project_service.apis]
}

# Grant the bot SA permission to access its secrets
resource "google_project_iam_member" "bot_secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.discord_bot_sa.email}"
}

# Grant the bot SA permission to scale the GCE instance group
resource "google_project_iam_member" "bot_mig_scaler" {
  project = var.gcp_project_id
  role    = google_project_iam_custom_role.mig_scaler.id # Use the ID of our new custom role
  member  = "serviceAccount:${google_service_account.discord_bot_sa.email}"
}

# --- INSTANCE TEMPLATE ---
resource "google_compute_instance_template" "movie_projector_template" {
  name_prefix  = "movie-projector-template-"
  machine_type = "e2-small"
  region       = var.gcp_region

  disk {
    source_image = "cos-cloud/cos-stable"
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
  }

  network_interface {
    network = "default"
    access_config {
        network_tier = "STANDARD"
    }
  }

  service_account {
    email  = google_service_account.movie_projector_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script-url = "gs://${google_storage_bucket.projector_vm_config.name}/${google_storage_bucket_object.startup_script.name}"
    google-logging-enabled    = "true"
    google-monitoring-enabled = "true"

    domain-name               = var.domain_name
    hostname                  = var.hostname
    dns-zone-name             = google_dns_managed_zone.movie_night_zone.name
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_project_service.apis]
}

# --- INSTANCE GROUP ---
resource "google_compute_instance_group_manager" "movie_projector_mig" {
  name               = "movie-projector-mig"
  zone               = var.gcp_zone
  base_instance_name = "movie-projector-vm"
  target_size        = 0
  version {
    instance_template = google_compute_instance_template.movie_projector_template.id
  }

  lifecycle {
    ignore_changes = [
        target_size,
    ]
  }

  depends_on = [google_project_service.apis]
}

# --- FIREWALL RULE ---
# A single rule to manage all ports for the movie night service
resource "google_compute_firewall" "allow_movie_night_traffic" {
  name    = "allow-movie-night-traffic"
  network = "default"
  allow {
    protocol = "tcp"
    # Port 80 (Certbot), 443 (mediamtx), 4443 (webhook), 8554 (RTSP)
    ports    = ["80", "443", "4443", "8554"]
  }
  source_ranges = ["0.0.0.0/0"]
  depends_on    = [google_project_service.apis]
}

# --- ARTIFACT REGISTRY REMOTE REPOSITORY ---
# This resource creates a caching proxy for the GitHub Container Registry.
resource "google_artifact_registry_repository" "ghcr_remote" {
  location      = var.gcp_region
  repository_id = "ghcr-remote"
  description   = "Remote repository proxy for ghcr.io"
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"

  remote_repository_config {
    docker_repository {
      # CORRECTED: For custom public registries like GHCR, use the 'custom_repository'
      # block and provide the upstream URI.
      custom_repository {
        uri = "https://ghcr.io"
      }
    }
  }

  depends_on = [google_project_service.apis]
}

# --- CLOUD RUN SERVICE ---
resource "google_cloud_run_v2_service" "discord_bot" {
  name     = "discord-bot"
  location = var.gcp_region
  depends_on = [
    google_project_service.apis,
    google_artifact_registry_repository.ghcr_remote # Ensure repo exists first
  ]

  template {
    service_account = google_service_account.discord_bot_sa.email

    containers {
      image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.ghcr_remote.repository_id}/axisofentropy/movie-night-bot:latest"
      
      ports {
        container_port = 8080
      }

      # --- Environment Variables ---
      # Set the GCE webhook's public URL
      env {
        name  = "GCE_WEBHOOK_URL"
        value = "https://${var.hostname}.${var.domain_name}:4443"
      }

      # Securely mount the bot's public key from Secret Manager
      env {
        name = "BOT_PUBLIC_KEY"
        value_source {
          secret_key_ref {
            secret  = "discord-bot-public-key"
            version = "latest"
          }
        }
      }

      # Securely mount the webhook's secret token from Secret Manager
      env {
        name = "WEBHOOK_SECRET_TOKEN"
        value_source {
          secret_key_ref {
            secret  = "webhook-secret-token"
            version = "latest"
          }
        }
      }
    }
  }
}

# --- IAM FOR PUBLIC ACCESS ---
# This makes the Cloud Run service accessible from the public internet
# resource "google_cloud_run_v2_service_iam_member" "allow_public_access" {
#  project  = google_cloud_run_v2_service.discord_bot.project
#  location = google_cloud_run_v2_service.discord_bot.location
#  name     = google_cloud_run_v2_service.discord_bot.name
#  role     = "roles/run.invoker"
#  member   = "allUsers"
# }

# --- CLOUD DNS ZONE ---
# Create a managed zone for your domain.
resource "google_dns_managed_zone" "movie_night_zone" {
  name        = "movie-night-zone"
  dns_name    = "${var.domain_name}." # Note the trailing dot
  description = "DNS zone for movie night"
  depends_on  = [google_project_service.apis]
}

resource "google_dns_record_set" "movie_night_a_record" {
  name         = "${var.hostname}.${var.domain_name}."
  type         = "A"
  # UPDATED: Set a low TTL and a placeholder IP. The startup script will update this.
  ttl          = 60
  managed_zone = google_dns_managed_zone.movie_night_zone.name
  rrdatas      = ["127.0.0.1"]
}

# --- OUTPUTS ---
# This will print the bot's public URL after you apply the configuration
output "discord_bot_url" {
  description = "The public URL for the Discord bot Cloud Run service."
  value       = google_cloud_run_v2_service.discord_bot.uri
}

# This will print the nameservers you need for GoDaddy.
output "dns_name_servers" {
  description = "Nameservers for the Cloud DNS zone."
  value       = google_dns_managed_zone.movie_night_zone.name_servers
}