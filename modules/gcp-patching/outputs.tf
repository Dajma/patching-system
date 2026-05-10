output "service_account_email" {
  description = "Email address of the patching service account — assign to GCE VMs"
  value       = google_service_account.patching.email
}

output "service_account_id" {
  description = "Unique ID of the patching service account"
  value       = google_service_account.patching.unique_id
}

output "patch_deployment_linux_id" {
  description = "Full resource name of the Linux OS Config patch deployment"
  value       = google_os_config_patch_deployment.linux.id
}

output "patch_deployment_windows_id" {
  description = "Full resource name of the Windows OS Config patch deployment"
  value       = google_os_config_patch_deployment.windows.id
}

output "pubsub_topic_id" {
  description = "Resource ID of the patch events Pub/Sub topic"
  value       = google_pubsub_topic.patch_events.id
}

output "pubsub_subscription_id" {
  description = "Resource ID of the patch events Pub/Sub pull subscription"
  value       = google_pubsub_subscription.patch_events.id
}

output "log_sink_bucket_name" {
  description = "GCS bucket name where OS Config patch logs are exported"
  value       = google_storage_bucket.patch_logs.name
}

output "scheduler_job_linux" {
  description = "Name of the Cloud Scheduler job that triggers Linux patching"
  value       = google_cloud_scheduler_job.trigger_linux_patch.name
}
