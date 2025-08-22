# Configure the Google Cloud provider
terraform {
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
resource "google_storage_bucket" "startup_script_bucket" {
  name          = "${var.gcp_project_id}-movie-night-scripts"
  location      = var.gcp_region
  force_destroy = true

  # Explicitly depend on the APIs being enabled first.
  depends_on = [google_project_service.apis]
}

resource "google_storage_bucket_object" "startup_script" {
  name   = "startup.sh"
  bucket = google_storage_bucket.startup_script_bucket.name
  source = "${path.module}/startup-script.sh"
}

# --- SERVICE ACCOUNT & IAM ---
resource "google_service_account" "movie_night_sa" {
  account_id   = "movie-night-vm-sa"
  display_name = "Service Account for Movie Night VM"
  depends_on   = [google_project_service.apis]
}

resource "google_storage_bucket_iam_member" "startup_script_reader" {
  bucket = google_storage_bucket.startup_script_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.movie_night_sa.email}"
}

resource "google_project_iam_member" "secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.movie_night_sa.email}"
}

# --- INSTANCE TEMPLATE ---
resource "google_compute_instance_template" "movie_night_template" {
  name_prefix  = "movie-night-template-"
  machine_type = "e2-medium"
  region       = var.gcp_region

  disk {
    source_image = "cos-cloud/cos-stable"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network = "default"
    access_config {}
  }

  service_account {
    email  = google_service_account.movie_night_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script-url = "gs://${google_storage_bucket.startup_script_bucket.name}/${google_storage_bucket_object.startup_script.name}"
  }

  depends_on = [google_project_service.apis]
}

# --- INSTANCE GROUP ---
resource "google_compute_instance_group_manager" "movie_night_mig" {
  name               = "movie-night-mig"
  zone               = var.gcp_zone
  base_instance_name = "movienight-vm"
  target_size        = 0
  version {
    instance_template = google_compute_instance_template.movie_night_template.id
  }
}

# --- FIREWALL RULES ---
resource "google_compute_firewall" "allow_webhook" {
  name    = "allow-movie-night-webhook"
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["5000"]
  }
  source_ranges = ["0.0.0.0/0"]
  depends_on    = [google_project_service.apis]
}

resource "google_compute_firewall" "allow_mediamtx" {
  name    = "allow-movie-night-mediamtx"
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["8888", "8554"]
  }
  source_ranges = ["0.0.0.0/0"]
  depends_on    = [google_project_service.apis]
}