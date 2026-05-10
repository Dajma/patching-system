variable "environment" {
  description = "Deployment environment: dev, staging, or prod"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod"
  }
}

variable "project_name" {
  description = "Name prefix applied to all resources"
  type        = string
  default     = "patching-system"
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region (e.g. us-central1)"
  type        = string
}

variable "patch_schedule_cron" {
  description = "Unix cron expression for recurring patch deployments"
  type        = string
  default     = "0 2 * * SAT"
}

variable "patch_schedule_timezone" {
  description = "Timezone for the patch schedule cron"
  type        = string
  default     = "UTC"
}

variable "pubsub_message_retention" {
  description = "How long Pub/Sub retains undelivered messages"
  type        = string
  default     = "604800s"
}

variable "log_sink_bucket_location" {
  description = "GCS multi-region location for patch log storage (e.g. US, EU)"
  type        = string
  default     = "US"
}

variable "log_retention_days" {
  description = "Days before patch logs are deleted from GCS"
  type        = number
  default     = 30
}

variable "alert_email" {
  description = "Email address for patch failure notifications (Cloud Monitoring channel)"
  type        = string
  default     = ""
}
