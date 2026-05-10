module "patching" {
  source = "../../modules/gcp-patching"

  environment              = var.environment
  project_name             = var.project_name
  project_id               = var.project_id
  region                   = var.region
  patch_schedule_cron      = var.patch_schedule_cron
  patch_schedule_timezone  = var.patch_schedule_timezone
  pubsub_message_retention = var.pubsub_message_retention
  log_sink_bucket_location = var.log_sink_bucket_location
  log_retention_days       = var.log_retention_days
  alert_email              = var.alert_email
}
