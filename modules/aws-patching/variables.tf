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

variable "region" {
  description = "AWS region"
  type        = string
}

variable "patch_schedule_cron" {
  description = "SSM maintenance window cron expression (SSM format)"
  type        = string
  default     = "cron(0 2 ? * SAT *)"
}

variable "maintenance_window_duration" {
  description = "Maintenance window length in hours (minimum 1)"
  type        = number
  default     = 4
}

variable "maintenance_window_cutoff" {
  description = "Hours before window end to stop scheduling new tasks"
  type        = number
  default     = 1
}

variable "alert_email" {
  description = "Email address for SNS patch-failure alerts. Leave empty to skip subscription."
  type        = string
  default     = ""
}

variable "s3_log_retention_days" {
  description = "Days before patch compliance logs are expired from S3"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Common tags applied to every resource"
  type        = map(string)
  default     = {}
}
