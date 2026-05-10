terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Remote state: uncomment and configure before applying to shared environments
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "patching-system/gcp"
  # }
}
