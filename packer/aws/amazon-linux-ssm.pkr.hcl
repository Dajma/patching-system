packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

locals {
  # Same SSM parameter used by create-vms.sh
  al2023_ami_parameter = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  timestamp            = formatdate("YYYYMMDD-hhmm", timestamp())
}

data "amazon-parameterstore" "al2023" {
  name   = local.al2023_ami_parameter
  region = var.aws_region
}

source "amazon-ebs" "al2023_ssm" {
  region        = var.aws_region
  source_ami    = data.amazon-parameterstore.al2023.value
  instance_type = "t3.micro"
  ssh_username  = "ec2-user"

  ami_name        = "patching-system-al2023-ssm-${local.timestamp}"
  ami_description = "Amazon Linux 2023 with SSM Agent guaranteed installed and enabled"

  tags = {
    Project     = "patching-system"
    BaseImage   = "al2023"
    AgentBaked  = "ssm-agent"
    BuildTime   = local.timestamp
  }
}

build {
  sources = ["source.amazon-ebs.al2023_ssm"]

  provisioner "shell" {
    inline = [
      "sudo dnf install -y amazon-ssm-agent",
      "sudo systemctl enable amazon-ssm-agent",
      "sudo systemctl start amazon-ssm-agent",
      "sudo systemctl is-active amazon-ssm-agent",
    ]
  }
}
