packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "~> 1"
    }
  }
}

variable "project_id" {
  type    = string
  default = env("GCP_PROJECT")
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

locals {
  timestamp = formatdate("YYYYMMDDhhmm", timestamp())
}

source "googlecompute" "debian12_osconfig" {
  project_id = var.project_id
  zone       = var.zone

  # Same image family used by create-vms.sh
  source_image_family = "debian-12"
  source_image_project_id = ["debian-cloud"]

  machine_type = "e2-micro"
  ssh_username = "packer"

  image_name        = "patching-system-debian12-osconfig-${local.timestamp}"
  image_description = "Debian 12 with OS Config Agent guaranteed installed and enabled"

  image_labels = {
    project    = "patching-system"
    base_image = "debian-12"
    agent      = "google-osconfig-agent"
  }

  # Mirror the metadata set in create-vms.sh
  metadata = {
    enable-osconfig = "true"
  }
}

build {
  sources = ["source.googlecompute.debian12_osconfig"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update -qq",
      "sudo apt-get install -y google-osconfig-agent",
      "sudo systemctl enable google-osconfig-agent",
      "sudo systemctl start google-osconfig-agent",
      "sudo systemctl is-active google-osconfig-agent",
    ]
  }
}
