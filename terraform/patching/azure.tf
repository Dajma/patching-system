# ── Maintenance Configuration ──────────────────────────────────────────────────
# Defines the patch policy and window. VMs are enrolled by setting their
# patchMode to AutomaticByPlatform (done below via null_resource).

resource "azurerm_maintenance_configuration" "linux" {
  name                     = "patching-system-linux"
  resource_group_name      = var.azure_resource_group
  location                 = var.azure_region
  scope                    = "InGuestPatch"
  in_guest_user_patch_mode = "User"

  window {
    start_date_time = "2024-01-10 06:00"
    time_zone       = "UTC"
    duration        = "02:00"
    recur_every     = "1Week Wednesday"
  }

  install_patches {
    reboot = "IfRequired"

    linux {
      classifications_to_include = ["Critical", "Security", "Other"]
    }
  }

  tags = {
    Project   = "patching-system"
    ManagedBy = "terraform"
  }
}

resource "azurerm_maintenance_configuration" "windows" {
  name                     = "patching-system-windows"
  resource_group_name      = var.azure_resource_group
  location                 = var.azure_region
  scope                    = "InGuestPatch"
  in_guest_user_patch_mode = "User"

  window {
    start_date_time = "2024-01-10 06:00"
    time_zone       = "UTC"
    duration        = "02:00"
    recur_every     = "1Week Wednesday"
  }

  install_patches {
    reboot = "IfRequired"

    windows {
      classifications_to_include = ["Critical", "Security"]
    }
  }

  tags = {
    Project   = "patching-system"
    ManagedBy = "terraform"
  }
}

# ── Patch Mode Configuration ───────────────────────────────────────────────────
# AutomaticByPlatform on both assessment and patch mode is required for
# Update Manager to continuously track available patches and for the
# maintenance configurations above to apply patches on schedule.
# The az CLI is used here because azurerm has no resource for mutating the
# patch settings of a VM it does not own (created outside Terraform).

resource "null_resource" "azure_patch_mode_linux" {
  triggers = { config = "1" }

  provisioner "local-exec" {
    command = <<-EOT
      az vm update \
        --resource-group ${var.azure_resource_group} \
        --name ${var.azure_linux_vm_name} \
        --subscription ${var.azure_subscription_id} \
        --set "osProfile.linuxConfiguration.patchSettings.patchMode=AutomaticByPlatform" \
        --set "osProfile.linuxConfiguration.patchSettings.assessmentMode=AutomaticByPlatform" \
        --output none 2>/dev/null || true
    EOT
  }
}

resource "null_resource" "azure_patch_mode_windows" {
  triggers = { config = "1" }

  provisioner "local-exec" {
    command = <<-EOT
      az vm update \
        --resource-group ${var.azure_resource_group} \
        --name ${var.azure_windows_vm_name} \
        --subscription ${var.azure_subscription_id} \
        --set "osProfile.windowsConfiguration.patchSettings.patchMode=AutomaticByPlatform" \
        --set "osProfile.windowsConfiguration.patchSettings.assessmentMode=AutomaticByPlatform" \
        --output none 2>/dev/null || true
    EOT
  }
}
