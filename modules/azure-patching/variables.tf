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

variable "resource_group_name" {
  description = "Resource group where all resources are deployed"
  type        = string
}

variable "location" {
  description = "Azure region (e.g. eastus, westeurope)"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID used for role assignment scope"
  type        = string
}

variable "maintenance_start_datetime" {
  description = "First occurrence of maintenance window (YYYY-MM-DD HH:MM)"
  type        = string
  default     = "2026-06-07 02:00"
}

variable "maintenance_recur_every" {
  description = "Maintenance recurrence pattern (e.g. '1Week Saturday')"
  type        = string
  default     = "1Week Saturday"
}

variable "maintenance_window_duration" {
  description = "Duration of the maintenance window (HH:MM, minimum 01:30)"
  type        = string
  default     = "04:00"
}

variable "log_retention_days" {
  description = "Log Analytics workspace data retention in days"
  type        = number
  default     = 30
}

variable "alert_email" {
  description = "Email address for patch failure action group alerts"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags applied to every resource"
  type        = map(string)
  default     = {}
}
