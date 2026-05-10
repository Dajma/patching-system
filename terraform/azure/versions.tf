terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  # Remote state: uncomment and configure before applying to shared environments
  # backend "azurerm" {
  #   resource_group_name  = "terraform-state-rg"
  #   storage_account_name = "tfstate<unique>"
  #   container_name       = "tfstate"
  #   key                  = "patching-system/azure/terraform.tfstate"
  # }
}
