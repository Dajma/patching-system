output "instance_profile_name" {
  description = "IAM instance profile name — attach to EC2 launch templates"
  value       = aws_iam_instance_profile.ssm.name
}

output "instance_profile_arn" {
  description = "IAM instance profile ARN — attach to EC2 launch templates"
  value       = aws_iam_instance_profile.ssm.arn
}

output "ssm_role_arn" {
  description = "ARN of the IAM role used by SSM-managed instances"
  value       = aws_iam_role.ssm_instance.arn
}

output "patch_baseline_id_linux" {
  description = "SSM patch baseline ID for Amazon Linux 2023"
  value       = aws_ssm_patch_baseline.linux.id
}

output "patch_baseline_id_windows" {
  description = "SSM patch baseline ID for Windows Server"
  value       = aws_ssm_patch_baseline.windows.id
}

output "maintenance_window_id" {
  description = "SSM maintenance window ID"
  value       = aws_ssm_maintenance_window.main.id
}

output "s3_log_bucket_name" {
  description = "Name of the S3 bucket storing SSM Run Command output"
  value       = aws_s3_bucket.patch_logs.bucket
}

output "s3_log_bucket_arn" {
  description = "ARN of the S3 patch compliance log bucket"
  value       = aws_s3_bucket.patch_logs.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic receiving patch failure events"
  value       = aws_sns_topic.patch_alerts.arn
}
