variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = "2f791c46-1726-4a0c-94e8-48314ac8f1b4"
}

variable "azure_resource_group" {
  description = "Azure resource group containing the VMs"
  type        = string
  default     = "patching-system-rg"
}

variable "azure_region" {
  description = "Azure region"
  type        = string
  default     = "centralus"
}

variable "azure_linux_vm_name" {
  description = "Name of the Azure Linux VM"
  type        = string
  default     = "patch-test-linux"
}

variable "azure_windows_vm_name" {
  description = "Name of the Azure Windows VM"
  type        = string
  default     = "patch-test-win"
}

variable "gcp_project" {
  description = "GCP project ID"
  type        = string
  default     = "learn-image-project"
}

variable "gcp_zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}
