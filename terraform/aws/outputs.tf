output "instance_profile_name" {
  description = "IAM instance profile name — attach to EC2 launch templates"
  value       = module.patching.instance_profile_name
}

output "instance_profile_arn" {
  description = "IAM instance profile ARN"
  value       = module.patching.instance_profile_arn
}

output "patch_baseline_id_linux" {
  description = "SSM patch baseline ID for Amazon Linux 2023"
  value       = module.patching.patch_baseline_id_linux
}

output "patch_baseline_id_windows" {
  description = "SSM patch baseline ID for Windows Server"
  value       = module.patching.patch_baseline_id_windows
}

output "maintenance_window_id" {
  description = "SSM maintenance window ID"
  value       = module.patching.maintenance_window_id
}

output "s3_log_bucket_name" {
  description = "S3 bucket storing patch compliance logs"
  value       = module.patching.s3_log_bucket_name
}

output "sns_topic_arn" {
  description = "SNS topic ARN receiving patch failure events"
  value       = module.patching.sns_topic_arn
}
