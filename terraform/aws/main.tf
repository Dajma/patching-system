module "patching" {
  source = "../../modules/aws-patching"

  environment                 = var.environment
  project_name                = var.project_name
  region                      = var.region
  patch_schedule_cron         = var.patch_schedule_cron
  maintenance_window_duration = var.maintenance_window_duration
  maintenance_window_cutoff   = var.maintenance_window_cutoff
  alert_email                 = var.alert_email
  s3_log_retention_days       = var.s3_log_retention_days
  tags                        = var.tags
}
