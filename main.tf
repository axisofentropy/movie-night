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
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
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