locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# --- IAM: EC2 instance role for SSM ---

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm_instance" {
  name               = "${local.name_prefix}-ssm-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${local.name_prefix}-ssm-instance-profile"
  role = aws_iam_role.ssm_instance.name
  tags = local.common_tags
}

# --- S3: patch compliance log storage ---

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "patch_logs" {
  bucket        = "${local.name_prefix}-patch-logs-${random_id.bucket_suffix.hex}"
  force_destroy = var.environment != "prod"
  tags          = local.common_tags
}

resource "aws_s3_bucket_versioning" "patch_logs" {
  bucket = aws_s3_bucket.patch_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "patch_logs" {
  bucket = aws_s3_bucket.patch_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "patch_logs" {
  bucket                  = aws_s3_bucket.patch_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "patch_logs" {
  bucket = aws_s3_bucket.patch_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.s3_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# --- SNS: patch failure alerts ---

resource "aws_sns_topic" "patch_alerts" {
  name = "${local.name_prefix}-patch-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.patch_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- SSM Patch Baselines ---

resource "aws_ssm_patch_baseline" "linux" {
  name             = "${local.name_prefix}-linux-baseline"
  description      = "Auto-approves Security and Critical patches for Amazon Linux 2023"
  operating_system = "AMAZON_LINUX_2023"
  tags             = local.common_tags

  approval_rule {
    approve_after_days  = 0
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

  approval_rule {
    approve_after_days  = 7
    enable_non_security = false

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Bugfix"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Medium", "Low"]
    }
  }

  rejected_patches                             = []
  rejected_patches_action                      = "BLOCK"
  approved_patches_enable_non_security         = false
}

resource "aws_ssm_patch_baseline" "windows" {
  name             = "${local.name_prefix}-windows-baseline"
  description      = "Auto-approves Security and Critical patches for Windows Server"
  operating_system = "WINDOWS"
  tags             = local.common_tags

  approval_rule {
    approve_after_days = 0

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["SecurityUpdates", "CriticalUpdates"]
    }

    patch_filter {
      key    = "MSRC_SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  approval_rule {
    approve_after_days = 7

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["UpdateRollups"]
    }

    patch_filter {
      key    = "MSRC_SEVERITY"
      values = ["Moderate", "Low", "Unspecified"]
    }
  }
}

# --- SSM Maintenance Window ---

resource "aws_ssm_maintenance_window" "main" {
  name                       = "${local.name_prefix}-maintenance-window"
  schedule                   = var.patch_schedule_cron
  duration                   = var.maintenance_window_duration
  cutoff                     = var.maintenance_window_cutoff
  allow_unassociated_targets = false
  enabled                    = true
  tags                       = local.common_tags
}

resource "aws_ssm_maintenance_window_target" "all" {
  window_id     = aws_ssm_maintenance_window.main.id
  name          = "${local.name_prefix}-all-patching-targets"
  description   = "All EC2 instances opted in to automated patching"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:ssm-patching"
    values = ["true"]
  }
}

resource "aws_ssm_maintenance_window_task" "run_patch_baseline" {
  window_id        = aws_ssm_maintenance_window.main.id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  max_concurrency  = "10%"
  max_errors       = "5%"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.all.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      document_version = "$LATEST"
      timeout_seconds  = 3600
      comment          = "Automated patch install via ${local.name_prefix}"

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

# --- EventBridge: route non-compliance events to SNS ---

resource "aws_cloudwatch_event_rule" "patch_non_compliant" {
  name        = "${local.name_prefix}-patch-non-compliant"
  description = "Fires when an instance becomes non-compliant with the patch baseline"
  tags        = local.common_tags

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["SSM Patch Compliance Status Changed"]
    detail = {
      Status = ["NON_COMPLIANT"]
    }
  })
}

resource "aws_cloudwatch_event_target" "sns" {
  rule      = aws_cloudwatch_event_rule.patch_non_compliant.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.patch_alerts.arn
}

data "aws_iam_policy_document" "sns_allow_eventbridge" {
  statement {
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.patch_alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn    = aws_sns_topic.patch_alerts.arn
  policy = data.aws_iam_policy_document.sns_allow_eventbridge.json
}
