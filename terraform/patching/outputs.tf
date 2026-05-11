output "aws_linux_baseline_id" {
  description = "SSM patch baseline ID for Amazon Linux 2023"
  value       = aws_ssm_patch_baseline.linux.id
}

output "aws_windows_baseline_id" {
  description = "SSM patch baseline ID for Windows Server"
  value       = aws_ssm_patch_baseline.windows.id
}

output "aws_maintenance_window_id" {
  description = "SSM maintenance window ID"
  value       = aws_ssm_maintenance_window.patching.id
}

output "azure_linux_maintenance_config_id" {
  description = "Azure maintenance configuration ID for Linux VMs"
  value       = azurerm_maintenance_configuration.linux.id
}

output "azure_windows_maintenance_config_id" {
  description = "Azure maintenance configuration ID for Windows VMs"
  value       = azurerm_maintenance_configuration.windows.id
}

output "gcp_linux_patch_deployment" {
  description = "GCP OS Config patch deployment name for Linux"
  value       = google_os_config_patch_deployment.linux.name
}

output "gcp_windows_patch_deployment" {
  description = "GCP OS Config patch deployment name for Windows"
  value       = google_os_config_patch_deployment.windows.name
}
