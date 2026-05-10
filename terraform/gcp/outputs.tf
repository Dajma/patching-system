output "service_account_email" {
  description = "Patching service account email — assign to GCE VMs"
  value       = module.patching.service_account_email
}

output "patch_deployment_linux_id" {
  description = "Full resource name of the Linux OS Config patch deployment"
  value       = module.patching.patch_deployment_linux_id
}

output "patch_deployment_windows_id" {
  description = "Full resource name of the Windows OS Config patch deployment"
  value       = module.patching.patch_deployment_windows_id
}

output "pubsub_topic_id" {
  description = "Resource ID of the patch events Pub/Sub topic"
  value       = module.patching.pubsub_topic_id
}

output "log_sink_bucket_name" {
  description = "GCS bucket name storing OS Config patch logs"
  value       = module.patching.log_sink_bucket_name
}

output "scheduler_job_linux" {
  description = "Cloud Scheduler job triggering Linux patching"
  value       = module.patching.scheduler_job_linux
}
