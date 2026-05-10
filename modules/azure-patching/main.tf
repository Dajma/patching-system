locals {
  name_prefix = "${var.project_name}-${var.environment}"
  sub_scope   = "/subscriptions/${var.subscription_id}"
}

# --- User-assigned managed identity for VMs ---

resource "azurerm_user_assigned_identity" "patching" {
  name                = "${local.name_prefix}-patching-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = merge(var.tags, { Environment = var.environment, ManagedBy = "terraform" })
}

# --- Role assignments ---

# Allows the identity to trigger patch assessments and installs
resource "azurerm_role_assignment" "scheduled_patching_contributor" {
  scope                = local.sub_scope
  role_definition_name = "Scheduled Patching Contributor"
  principal_id         = azurerm_user_assigned_identity.patching.principal_id
}

# Allows reading VM inventory across the subscription
resource "azurerm_role_assignment" "reader" {
  scope                = local.sub_scope
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.patching.principal_id
}

# --- Log Analytics workspace for patch compliance ---

resource "azurerm_log_analytics_workspace" "patching" {
  name                = "${local.name_prefix}-patch-logs"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = merge(var.tags, { Environment = var.environment, ManagedBy = "terraform" })
}

# --- Maintenance configurations ---

resource "azurerm_maintenance_configuration" "linux" {
  name                     = "${local.name_prefix}-linux-maintenance"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  scope                    = "InGuestPatch"
  in_guest_user_patch_mode = "User"
  tags                     = merge(var.tags, { Environment = var.environment, ManagedBy = "terraform" })

  window {
    start_date_time = var.maintenance_start_datetime
    time_zone       = "UTC"
    duration        = var.maintenance_window_duration
    recur_every     = var.maintenance_recur_every
  }

  install_patches {
    reboot = "IfRequired"

    linux {
      classifications_to_include    = ["Critical", "Security", "Other"]
      package_names_mask_to_exclude = []
      package_names_mask_to_include = []
    }
  }
}

resource "azurerm_maintenance_configuration" "windows" {
  name                     = "${local.name_prefix}-windows-maintenance"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  scope                    = "InGuestPatch"
  in_guest_user_patch_mode = "User"
  tags                     = merge(var.tags, { Environment = var.environment, ManagedBy = "terraform" })

  window {
    start_date_time = var.maintenance_start_datetime
    time_zone       = "UTC"
    duration        = var.maintenance_window_duration
    recur_every     = var.maintenance_recur_every
  }

  install_patches {
    reboot = "IfRequired"

    windows {
      classifications_to_include = ["Critical", "Security", "UpdateRollup", "FeaturePack", "ServicePack", "Definition", "Tools", "Updates"]
      kb_numbers_to_exclude      = []
      kb_numbers_to_include      = []
    }
  }
}

# --- Alerting ---

resource "azurerm_monitor_action_group" "patch_alerts" {
  name                = "${local.name_prefix}-patch-alerts"
  resource_group_name = var.resource_group_name
  short_name          = "patchalert"
  tags                = merge(var.tags, { Environment = var.environment, ManagedBy = "terraform" })

  dynamic "email_receiver" {
    for_each = var.alert_email != "" ? [var.alert_email] : []

    content {
      name          = "email-alert"
      email_address = email_receiver.value
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "patch_failures" {
  name                = "${local.name_prefix}-patch-failure-alert"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = merge(var.tags, { Environment = var.environment, ManagedBy = "terraform" })

  evaluation_frequency = "PT1H"
  window_duration      = "PT1H"
  scopes               = [azurerm_log_analytics_workspace.patching.id]
  severity             = 2
  enabled              = true
  description          = "Alert when patch operations fail on any VM"

  criteria {
    query = <<-KQL
      UpdateRunProgress
      | where Status == "Failed"
      | summarize FailureCount = count() by Computer, TimeGenerated
      | where FailureCount > 0
    KQL

    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.patch_alerts.id]
  }
}

# --- Azure Policy: enforce periodic patch assessment ---

data "azurerm_policy_definition" "periodic_assessment" {
  display_name = "Configure periodic checking for missing system updates on azure virtual machines"
}

resource "azurerm_subscription_policy_assignment" "enforce_patching" {
  name                 = "${local.name_prefix}-enforce-patching"
  subscription_id      = local.sub_scope
  policy_definition_id = data.azurerm_policy_definition.periodic_assessment.id
  description          = "Ensures all VMs have periodic patch assessment enabled"
  display_name         = "${local.name_prefix} — Enforce periodic patch assessment"

  identity {
    type = "SystemAssigned"
  }

  location = var.location
}
