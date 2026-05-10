output "user_assigned_identity_id" {
  description = "Resource ID of the user-assigned managed identity"
  value       = module.patching.user_assigned_identity_id
}

output "user_assigned_identity_client_id" {
  description = "Client ID of the managed identity — reference in VM identity blocks"
  value       = module.patching.user_assigned_identity_client_id
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = module.patching.log_analytics_workspace_id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = module.patching.log_analytics_workspace_name
}

output "maintenance_config_linux_id" {
  description = "Resource ID of the Linux maintenance configuration"
  value       = module.patching.maintenance_config_linux_id
}

output "maintenance_config_windows_id" {
  description = "Resource ID of the Windows maintenance configuration"
  value       = module.patching.maintenance_config_windows_id
}

output "action_group_id" {
  description = "Resource ID of the patch failure monitor action group"
  value       = module.patching.action_group_id
}
