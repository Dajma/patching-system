output "user_assigned_identity_id" {
  description = "Resource ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.patching.id
}

output "user_assigned_identity_client_id" {
  description = "Client ID of the managed identity — used in VM identity blocks"
  value       = azurerm_user_assigned_identity.patching.client_id
}

output "user_assigned_identity_principal_id" {
  description = "Principal (object) ID of the managed identity"
  value       = azurerm_user_assigned_identity.patching.principal_id
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.patching.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.patching.name
}

output "log_analytics_primary_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.patching.primary_shared_key
  sensitive   = true
}

output "maintenance_config_linux_id" {
  description = "Resource ID of the Linux maintenance configuration"
  value       = azurerm_maintenance_configuration.linux.id
}

output "maintenance_config_windows_id" {
  description = "Resource ID of the Windows maintenance configuration"
  value       = azurerm_maintenance_configuration.windows.id
}

output "action_group_id" {
  description = "Resource ID of the patch failure monitor action group"
  value       = azurerm_monitor_action_group.patch_alerts.id
}
