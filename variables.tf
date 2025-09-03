variable "gcp_project_id" {
  description = "The GCP project ID to deploy resources into."
  type        = string
  default     = "example-movie-night"
}

variable "gcp_region" {
  description = "The GCP region for the resources."
  type        = string
  default     = "us-east1"
}

variable "gcp_zone" {
  description = "The GCP zone for the instance group."
  type        = string
  default     = "us-east1-b"
}

variable "domain_name" {
  description = "The domain name for the DDNS update."
  type        = string
  default     = "example.com"
}

variable "hostname" {
  description = "The hostname for the DDNS update."
  type        = string
  default     = "movienight"
}

# NEW: A list of the APIs that this project requires.
variable "gcp_apis" {
  description = "The list of GCP APIs to enable on the project."
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "run.googleapis.com",
    "dns.googleapis.com",
  ]
}

variable "discord_application_id" {
  description = "The application ID of the Discord bot."
  type        = string
}

variable "discord_client_credentials_token" {
  description = "The client credentials token for the Discord application."
  type        = string
  sensitive   = true
}
