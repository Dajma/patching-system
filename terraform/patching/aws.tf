# ── Patch Baselines ────────────────────────────────────────────────────────────
# Critical + Security, 7-day approval lag so regressions surface before fleet rollout.

resource "aws_ssm_patch_baseline" "linux" {
  name             = "patching-system-linux"
  description      = "Security baseline for Amazon Linux 2023 — 7-day approval lag"
  operating_system = "AMAZON_LINUX_2023"

  approval_rule {
    approve_after_days  = 7
    enable_non_security = false

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }
    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  tags = {
    Project   = "patching-system"
    ManagedBy = "terraform"
  }
}

resource "aws_ssm_patch_baseline" "windows" {
  name             = "patching-system-windows"
  description      = "Security baseline for Windows Server — 7-day approval lag"
  operating_system = "WINDOWS"

  approval_rule {
    approve_after_days = 7

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["CriticalUpdates", "SecurityUpdates"]
    }
    patch_filter {
      key    = "MSRC_SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  tags = {
    Project   = "patching-system"
    ManagedBy = "terraform"
  }
}

# Register both baselines as the account-wide defaults for their OS so the
# pipeline's send-command (which targets by Project tag, not Patch Group) uses
# our approved baselines rather than the AWS-managed ones.
resource "aws_ssm_default_patch_baseline" "linux" {
  baseline_id      = aws_ssm_patch_baseline.linux.id
  operating_system = "AMAZON_LINUX_2023"
}

resource "aws_ssm_default_patch_baseline" "windows" {
  baseline_id      = aws_ssm_patch_baseline.windows.id
  operating_system = "WINDOWS"
}

# ── Maintenance Window ─────────────────────────────────────────────────────────
# Wednesday 06:00 UTC (day after Patch Tuesday) — matches the pipeline schedule.

resource "aws_ssm_maintenance_window" "patching" {
  name                       = "patching-system-window"
  description                = "Weekly patching window for all Project=patching-system instances"
  schedule                   = "cron(0 6 ? * WED *)"
  duration                   = 2
  cutoff                     = 1
  allow_unassociated_targets = false
  enabled                    = true

  tags = {
    Project   = "patching-system"
    ManagedBy = "terraform"
  }
}

resource "aws_ssm_maintenance_window_target" "project_vms" {
  window_id     = aws_ssm_maintenance_window.patching.id
  name          = "patching-system-vms"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:Project"
    values = ["patching-system"]
  }
}

resource "aws_ssm_maintenance_window_task" "install_patches" {
  window_id       = aws_ssm_maintenance_window.patching.id
  task_type       = "RUN_COMMAND"
  task_arn        = "AWS-RunPatchBaseline"
  priority        = 1
  max_concurrency = "10%"
  max_errors      = "5%"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.project_vms.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      timeout_seconds = 3600

      parameter {
        name   = "Operation"
        values = ["Install"]
      }
      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
    }
  }
}
