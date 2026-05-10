packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "~> 2"
    }
  }
}

variable "subscription_id" {
  type    = string
  default = env("ARM_SUBSCRIPTION_ID")
}

variable "resource_group" {
  type    = string
  default = "patching-system-rg"
}

variable "location" {
  type    = string
  default = "eastus"
}

locals {
  timestamp = formatdate("YYYYMMDDhhmm", timestamp())
}

source "azure-arm" "ubuntu_waagent" {
  subscription_id = var.subscription_id

  # Managed image destination
  managed_image_name                = "patching-system-ubuntu2204-waagent-${local.timestamp}"
  managed_image_resource_group_name = var.resource_group

  location = var.location
  vm_size  = "Standard_B1s"

  # Same image used by create-vms.sh
  image_publisher = "Canonical"
  image_offer     = "0001-com-ubuntu-server-jammy"
  image_sku       = "22_04-lts"

  os_type         = "Linux"
  ssh_username    = "packer"

  azure_tags = {
    Project    = "patching-system"
    BaseImage  = "ubuntu-22.04"
    AgentBaked = "walinuxagent"
    BuildTime  = local.timestamp
  }
}

build {
  sources = ["source.azure-arm.ubuntu_waagent"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update -qq",
      "sudo apt-get install -y walinuxagent",
      "sudo systemctl enable walinuxagent",
      "sudo systemctl start walinuxagent",
      "sudo systemctl is-active walinuxagent",
      # Deprovision so the image can be generalized for reuse
      "sudo waagent -force -deprovision+user",
      "export HISTSIZE=0",
    ]
  }
}
