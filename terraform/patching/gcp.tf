# ── OS Config API ──────────────────────────────────────────────────────────────

resource "google_project_service" "osconfig" {
  project            = var.gcp_project
  service            = "osconfig.googleapis.com"
  disable_on_destroy = false
}

# ── Project-level OS Config enablement ────────────────────────────────────────
# Tells the OS Config agent on every VM in the project to phone home.

resource "google_compute_project_metadata_item" "osconfig_enabled" {
  project = var.gcp_project
  key     = "enable-osconfig"
  value   = "true"

  depends_on = [google_project_service.osconfig]
}

# ── Patch Deployments ─────────────────────────────────────────────────────────
# Recurring scheduled deployments targeting project=patching-system VMs.
# The pipeline also triggers on-demand jobs; these are the automatic fallback.

resource "google_os_config_patch_deployment" "linux" {
  project             = var.gcp_project
  patch_deployment_id = "patching-system-linux-weekly"
  description         = "Weekly Linux patches for project=patching-system VMs"

  depends_on = [google_project_service.osconfig]

  instance_filter {
    group_labels {
      labels = {
        project = "patching-system"
        os      = "linux"
      }
    }
  }

  patch_config {
    reboot_config = "DEFAULT"

    apt {
      type = "UPGRADE"
    }

    yum {
      security = true
      minimal  = false
    }
  }

  recurring_schedule {
    time_zone {
      id = "UTC"
    }

    time_of_day {
      hours   = 6
      minutes = 0
      seconds = 0
      nanos   = 0
    }

    weekly {
      day_of_week = "WEDNESDAY"
    }
  }
}

resource "google_os_config_patch_deployment" "windows" {
  project             = var.gcp_project
  patch_deployment_id = "patching-system-windows-weekly"
  description         = "Weekly Windows patches for project=patching-system VMs"

  depends_on = [google_project_service.osconfig]

  instance_filter {
    group_labels {
      labels = {
        project = "patching-system"
        os      = "windows"
      }
    }
  }

  patch_config {
    reboot_config = "DEFAULT"

    windows_update {
      classifications = ["CRITICAL", "SECURITY"]
    }
  }

  recurring_schedule {
    time_zone {
      id = "UTC"
    }

    time_of_day {
      hours   = 6
      minutes = 0
      seconds = 0
      nanos   = 0
    }

    weekly {
      day_of_week = "WEDNESDAY"
    }
  }
}
