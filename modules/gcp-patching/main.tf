locals {
  name_prefix = "${var.project_name}-${var.environment}"
  sa_name     = "${local.name_prefix}-patch-sa"
}

# --- Service account ---

resource "google_service_account" "patching" {
  project      = var.project_id
  account_id   = local.sa_name
  display_name = "Patching System SA (${var.environment})"
  description  = "Least-privilege SA for GCP VM OS patch operations"
}

# --- IAM bindings for the service account ---

resource "google_project_iam_member" "patch_executor" {
  project = var.project_id
  role    = "roles/osconfig.patchJobExecutor"
  member  = "serviceAccount:${google_service_account.patching.email}"
}

resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.patching.email}"
}

resource "google_project_iam_member" "metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.patching.email}"
}

resource "google_project_iam_member" "inventory_viewer" {
  project = var.project_id
  role    = "roles/osconfig.inventoryViewer"
  member  = "serviceAccount:${google_service_account.patching.email}"
}

resource "google_project_iam_member" "service_usage_consumer" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = "serviceAccount:${google_service_account.patching.email}"
}

# --- OS Config patch deployments ---

resource "google_os_config_patch_deployment" "linux" {
  project           = var.project_id
  patch_deployment_id = "${local.name_prefix}-linux-patches"
  description       = "Recurring Linux patch deployment for ${var.environment}"

  instance_filter {
    all = false
    group_labels {
      labels = {
        "os-patch" = "enabled"
      }
    }
  }

  patch_config {
    reboot_config = "DEFAULT"

    apt {
      type     = "UPGRADE"
      excludes = []
    }

    yum {
      security = true
      minimal  = false
      excludes = []
    }

    zypper {
      with_optional = false
      with_update   = true
      categories    = ["security"]
    }
  }

  recurring_schedule {
    time_zone {
      id = var.patch_schedule_timezone
    }

    time_of_day {
      hours   = 2
      minutes = 0
      seconds = 0
      nanos   = 0
    }

    weekly {
      day_of_week = "SATURDAY"
    }
  }

  rollout {
    mode = "ZONE_BY_ZONE"

    disruption_budget {
      percentage = 25
    }
  }
}

resource "google_os_config_patch_deployment" "windows" {
  project           = var.project_id
  patch_deployment_id = "${local.name_prefix}-windows-patches"
  description       = "Recurring Windows patch deployment for ${var.environment}"

  instance_filter {
    all = false
    group_labels {
      labels = {
        "os-patch" = "enabled"
      }
    }
  }

  patch_config {
    reboot_config = "DEFAULT"

    windows_update {
      classifications = ["CRITICAL", "SECURITY", "UPDATE_ROLLUP"]
      excludes        = []
    }
  }

  recurring_schedule {
    time_zone {
      id = var.patch_schedule_timezone
    }

    time_of_day {
      hours   = 4
      minutes = 0
      seconds = 0
      nanos   = 0
    }

    weekly {
      day_of_week = "SUNDAY"
    }
  }

  rollout {
    mode = "ZONE_BY_ZONE"

    disruption_budget {
      percentage = 25
    }
  }
}

# --- Pub/Sub for patch completion events ---

resource "google_pubsub_topic" "patch_events" {
  project = var.project_id
  name    = "${local.name_prefix}-patch-events"

  message_retention_duration = var.pubsub_message_retention

  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }
}

resource "google_pubsub_subscription" "patch_events" {
  project = var.project_id
  name    = "${local.name_prefix}-patch-events-sub"
  topic   = google_pubsub_topic.patch_events.name

  message_retention_duration = var.pubsub_message_retention
  retain_acked_messages      = false
  ack_deadline_seconds       = 60

  expiration_policy {
    ttl = ""
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }
}

# --- Cloud Scheduler: trigger patch deployments on schedule ---

resource "google_cloud_scheduler_job" "trigger_linux_patch" {
  project     = var.project_id
  region      = var.region
  name        = "${local.name_prefix}-trigger-linux-patch"
  description = "Triggers the Linux OS Config patch deployment"
  schedule    = var.patch_schedule_cron
  time_zone   = var.patch_schedule_timezone

  http_target {
    uri         = "https://osconfig.googleapis.com/v1/projects/${var.project_id}/patchDeployments/${google_os_config_patch_deployment.linux.patch_deployment_id}:pause"
    http_method = "POST"

    oauth_token {
      service_account_email = google_service_account.patching.email
    }
  }
}

# --- GCS bucket for Cloud Logging sink ---

resource "google_storage_bucket" "patch_logs" {
  project                     = var.project_id
  name                        = "${local.name_prefix}-patch-logs-${var.project_id}"
  location                    = var.log_sink_bucket_location
  uniform_bucket_level_access = true
  force_destroy               = var.environment != "prod"

  lifecycle_rule {
    action {
      type = "Delete"
    }

    condition {
      age = var.log_retention_days
    }
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }
}

# --- Cloud Logging sink ---

resource "google_logging_project_sink" "patch_logs" {
  project                = var.project_id
  name                   = "${local.name_prefix}-patch-logs-sink"
  destination            = "storage.googleapis.com/${google_storage_bucket.patch_logs.name}"
  filter                 = "resource.type=\"gce_instance\" AND (log_id(\"OSConfigAgent\") OR log_id(\"compute.googleapis.com/os_config\"))"
  unique_writer_identity = true
}

resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.patch_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.patch_logs.writer_identity
}
