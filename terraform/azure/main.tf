module "patching" {
  source = "../../modules/azure-patching"

  environment                 = var.environment
  project_name                = var.project_name
  resource_group_name         = var.resource_group_name
  location                    = var.location
  subscription_id             = var.subscription_id
  maintenance_start_datetime  = var.maintenance_start_datetime
  maintenance_recur_every     = var.maintenance_recur_every
  maintenance_window_duration = var.maintenance_window_duration
  log_retention_days          = var.log_retention_days
  alert_email                 = var.alert_email
  tags                        = var.tags
}
