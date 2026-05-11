#!/usr/bin/env bash
# create-vms.sh — Provision cheapest test VMs across AWS, Azure, and GCP
# Tags: Environment=testing, Project=patching-system, TTL=24h
# Each VM has the cloud-native patch agent pre-installed or activated.

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-2f791c46-1726-4a0c-94e8-48314ac8f1b4}"
GCP_PROJECT="${GCP_PROJECT:-learn-image-project}"

AWS_REGION="${AWS_REGION:-us-east-1}"
AZURE_REGION="${AZURE_REGION:-centralus}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"

RESOURCE_GROUP="patching-system-rg"
PREFIX="patch-test"

COMMON_TAGS="Environment=testing Project=patching-system TTL=24h"
AZURE_TAGS="Environment=testing Project=patching-system TTL=24h"
GCP_LABELS="environment=testing,project=patching-system,ttl=24h"

# State file — tracks created resource IDs for destroy-vms.sh
STATE_FILE="$(dirname "$0")/.vm-state.env"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[$(date -u '+%H:%M:%S')] $*"; }
ok()   { echo "[$(date -u '+%H:%M:%S')] ✓ $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] ⚠ $*" >&2; }
die()  { echo "[$(date -u '+%H:%M:%S')] ✗ $*" >&2; exit 1; }

usage() {
  echo "Usage: $0 [--aws-only | --azure-only | --gcp-only] [--no-aws | --no-azure | --no-gcp] [--status] [--dry-run]"
  exit 0
}

# ── Argument parsing ──────────────────────────────────────────────────────────
RUN_AWS=true; RUN_AZURE=true; RUN_GCP=true
DRY_RUN=false; STATUS_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --aws-only)   RUN_AZURE=false; RUN_GCP=false ;;
    --azure-only) RUN_AWS=false;   RUN_GCP=false ;;
    --gcp-only)   RUN_AWS=false;   RUN_AZURE=false ;;
    --no-aws)     RUN_AWS=false ;;
    --no-azure)   RUN_AZURE=false ;;
    --no-gcp)     RUN_GCP=false ;;
    --dry-run)    DRY_RUN=true ;;
    --status)     STATUS_ONLY=true ;;
    --help|-h)    usage ;;
  esac
done

# ── Status mode ───────────────────────────────────────────────────────────────
if [[ "$STATUS_ONLY" == "true" ]]; then
  [[ -f "$STATE_FILE" ]] || die "No state file found. Run create-vms.sh first."
  # shellcheck disable=SC1090
  source "$STATE_FILE"
  echo "=== AWS ==="
  [[ -n "${AWS_LINUX_ID:-}" ]] && \
    aws ec2 describe-instances --instance-ids "$AWS_LINUX_ID" "$AWS_WINDOWS_ID" \
      --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]' \
      --output table --region "$AWS_REGION" 2>/dev/null || echo "  (no state)"
  echo "=== Azure ==="
  [[ -n "${AZURE_RG:-}" ]] && \
    az vm list --resource-group "$AZURE_RG" --show-details \
      --query '[].{Name:name,State:powerState,IP:publicIps}' --output table 2>/dev/null || echo "  (no state)"
  echo "=== GCP ==="
  [[ -n "${GCP_LINUX_NAME:-}" ]] && \
    gcloud compute instances list --project "$GCP_PROJECT" \
      --filter "labels.project=patching-system" \
      --format "table(name,status,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "  (no state)"
  exit 0
fi

# ── Pre-flight checks ─────────────────────────────────────────────────────────
log "Running pre-flight checks..."

if [[ "$RUN_AWS" == "true" ]]; then
  aws sts get-caller-identity --query 'Account' --output text > /dev/null 2>&1 \
    || die "AWS: not authenticated. Run 'aws configure' or export AWS credentials."
  ok "AWS auth OK"
fi

if [[ "$RUN_AZURE" == "true" ]]; then
  az account show --subscription "$AZURE_SUBSCRIPTION_ID" --query 'id' -o tsv > /dev/null 2>&1 \
    || die "Azure: not logged in or subscription not accessible. Run 'az login'."
  az account set --subscription "$AZURE_SUBSCRIPTION_ID"
  ok "Azure auth OK (subscription: $AZURE_SUBSCRIPTION_ID)"
fi

if [[ "$RUN_GCP" == "true" ]]; then
  gcloud projects describe "$GCP_PROJECT" --quiet > /dev/null 2>&1 \
    || die "GCP: project $GCP_PROJECT not accessible. Run 'gcloud auth login'."
  ok "GCP auth OK (project: $GCP_PROJECT)"
fi

[[ "$DRY_RUN" == "true" ]] && log "DRY RUN — no resources will be created." && exit 0

# ── State file init ───────────────────────────────────────────────────────────
# Full run: fresh file. Partial run: preserve existing cloud entries.
if [[ "$RUN_AWS" == "true" && "$RUN_AZURE" == "true" && "$RUN_GCP" == "true" ]]; then
  cat > "$STATE_FILE" <<EOF
# VM State — written by create-vms.sh on $(date -u)
# Source this file to get resource IDs for destroy-vms.sh
AZURE_SUBSCRIPTION_ID="$AZURE_SUBSCRIPTION_ID"
GCP_PROJECT="$GCP_PROJECT"
AWS_REGION="$AWS_REGION"
AZURE_REGION="$AZURE_REGION"
GCP_ZONE="$GCP_ZONE"
EOF
else
  # Partial run — preserve existing state, just update the header timestamp
  [[ -f "$STATE_FILE" ]] || cat > "$STATE_FILE" <<EOF
# VM State — written by create-vms.sh on $(date -u)
AZURE_SUBSCRIPTION_ID="$AZURE_SUBSCRIPTION_ID"
GCP_PROJECT="$GCP_PROJECT"
AWS_REGION="$AWS_REGION"
AZURE_REGION="$AZURE_REGION"
GCP_ZONE="$GCP_ZONE"
EOF
fi

# ══════════════════════════════════════════════════════════════════════════════
# AWS
# VM type:  t3.micro (2 vCPU, 1 GB) — ~$0.0104/hr Linux, ~$0.0164/hr Windows
# Linux:    Amazon Linux 2023 (SSM Agent built-in, free tier)
# Windows:  Windows Server 2022 Base (SSM Agent built-in)
# Auth:     IAM Instance Profile with AmazonSSMManagedInstanceCore
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$RUN_AWS" == "true" ]]; then
  log "=== AWS: Creating VMs ==="

  # ── IAM instance profile for SSM ────────────────────────────────────────────
  ROLE_NAME="patching-system-ssm-role"
  PROFILE_NAME="patching-system-ssm-profile"

  if ! aws iam get-role --role-name "$ROLE_NAME" > /dev/null 2>&1; then
    log "Creating IAM role $ROLE_NAME..."
    aws iam create-role --role-name "$ROLE_NAME" \
      --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
      --tags Key=Project,Value=patching-system Key=Environment,Value=testing \
      --output text --query 'Role.RoleName' > /dev/null

    aws iam attach-role-policy --role-name "$ROLE_NAME" \
      --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
    ok "IAM role created"
  else
    ok "IAM role $ROLE_NAME already exists"
  fi

  if ! aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" > /dev/null 2>&1; then
    aws iam create-instance-profile --instance-profile-name "$PROFILE_NAME" \
      --tags Key=Project,Value=patching-system > /dev/null
    aws iam add-role-to-instance-profile --instance-profile-name "$PROFILE_NAME" \
      --role-name "$ROLE_NAME"
    ok "Instance profile created"
    sleep 10  # IAM propagation delay
  else
    ok "Instance profile $PROFILE_NAME already exists"
  fi

  # ── Security group: outbound 443 only (no inbound) ───────────────────────
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION")
  [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]] && die "No default VPC found in $AWS_REGION"

  SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${PREFIX}-sg" "Name=vpc-id,Values=${VPC_ID}" \
    --query 'SecurityGroups[0].GroupId' --output text --region "$AWS_REGION" 2>/dev/null || true)

  if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
    SG_ID=$(aws ec2 create-security-group \
      --group-name "${PREFIX}-sg" \
      --description "Patching test VMs - SSM only, no inbound" \
      --vpc-id "$VPC_ID" \
      --query 'GroupId' --output text --region "$AWS_REGION")

    # Remove default outbound rule and re-add only 443
    aws ec2 revoke-security-group-egress --group-id "$SG_ID" \
      --protocol -1 --port -1 --cidr 0.0.0.0/0 --region "$AWS_REGION" 2>/dev/null || true
    aws ec2 authorize-security-group-egress --group-id "$SG_ID" \
      --protocol tcp --port 443 --cidr 0.0.0.0/0 --region "$AWS_REGION" > /dev/null

    aws ec2 create-tags --resources "$SG_ID" \
      --tags Key=Name,Value="${PREFIX}-sg" Key=Project,Value=patching-system --region "$AWS_REGION"
    ok "Security group created: $SG_ID"
  else
    ok "Security group already exists: $SG_ID"
  fi

  # ── Amazon Linux 2023 (latest) ────────────────────────────────────────────
  AL2023_AMI=$(aws ssm get-parameter \
    --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64 \
    --query 'Parameter.Value' --output text --region "$AWS_REGION")
  log "Amazon Linux 2023 AMI: $AL2023_AMI"

  AWS_LINUX_ID=$(aws ec2 run-instances \
    --image-id "$AL2023_AMI" \
    --instance-type t3.micro \
    --iam-instance-profile Name="$PROFILE_NAME" \
    --security-group-ids "$SG_ID" \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=${PREFIX}-linux},{Key=Environment,Value=testing},{Key=Project,Value=patching-system},{Key=TTL,Value=24h},{Key=OS,Value=linux}]" \
    --metadata-options "HttpTokens=required,HttpPutResponseHopLimit=1" \
    --query 'Instances[0].InstanceId' --output text --region "$AWS_REGION")
  ok "AWS Linux VM: $AWS_LINUX_ID"

  # ── Windows Server 2022 ───────────────────────────────────────────────────
  WIN2022_AMI=$(aws ssm get-parameter \
    --name /aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base \
    --query 'Parameter.Value' --output text --region "$AWS_REGION")
  log "Windows Server 2022 AMI: $WIN2022_AMI"

  AWS_WINDOWS_ID=$(aws ec2 run-instances \
    --image-id "$WIN2022_AMI" \
    --instance-type t3.micro \
    --iam-instance-profile Name="$PROFILE_NAME" \
    --security-group-ids "$SG_ID" \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=${PREFIX}-windows},{Key=Environment,Value=testing},{Key=Project,Value=patching-system},{Key=TTL,Value=24h},{Key=OS,Value=windows}]" \
    --metadata-options "HttpTokens=required,HttpPutResponseHopLimit=1" \
    --query 'Instances[0].InstanceId' --output text --region "$AWS_REGION")
  ok "AWS Windows VM: $AWS_WINDOWS_ID"

  # Save state
  cat >> "$STATE_FILE" <<EOF
AWS_LINUX_ID="$AWS_LINUX_ID"
AWS_WINDOWS_ID="$AWS_WINDOWS_ID"
AWS_SG_ID="$SG_ID"
AWS_IAM_ROLE="$ROLE_NAME"
AWS_IAM_PROFILE="$PROFILE_NAME"
EOF
  log "Waiting for AWS instances to reach running state..."
  aws ec2 wait instance-running --instance-ids "$AWS_LINUX_ID" "$AWS_WINDOWS_ID" --region "$AWS_REGION"
  ok "AWS VMs running"
fi

# ══════════════════════════════════════════════════════════════════════════════
# AZURE
# VM type:  Standard_D2s_v3 (2 vCPU, 8 GB) — available in centralus: ~$0.096/hr
#           Standard_D2s_v3 (2 vCPU, 8 GB) — same SKU for Windows
# Linux:    Ubuntu 22.04 LTS (Azure Monitor Agent auto-enabled via policy)
# Windows:  Windows Server 2022 Datacenter (Windows Update Agent built-in)
# Auth:     System-assigned managed identity + Update Manager role
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$RUN_AZURE" == "true" ]]; then
  log "=== Azure: Creating VMs ==="

  # ── Resource group ────────────────────────────────────────────────────────
  if ! az group show --name "$RESOURCE_GROUP" --subscription "$AZURE_SUBSCRIPTION_ID" > /dev/null 2>&1; then
    az group create \
      --name "$RESOURCE_GROUP" \
      --location "$AZURE_REGION" \
      --subscription "$AZURE_SUBSCRIPTION_ID" \
      --tags $AZURE_TAGS \
      --output none
    ok "Resource group created: $RESOURCE_GROUP"
  else
    ok "Resource group already exists: $RESOURCE_GROUP"
  fi

  # ── Ubuntu 22.04 LTS VM (Standard_B1s) ───────────────────────────────────
  AZURE_LINUX_NAME="${PREFIX}-linux"
  az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AZURE_LINUX_NAME" \
    --image Ubuntu2204 \
    --size Standard_D2s_v3 \
    --admin-username azureuser \
    --generate-ssh-keys \
    --assign-identity "[system]" \
    --public-ip-sku Standard \
    --tags $AZURE_TAGS OS=linux \
    --subscription "$AZURE_SUBSCRIPTION_ID" \
    --output none \
    --no-wait
  ok "Azure Linux VM creation started: $AZURE_LINUX_NAME"

  # ── Windows Server 2022 VM (Standard_B2s) ────────────────────────────────
  AZURE_WINDOWS_NAME="${PREFIX}-win"
  AZURE_WIN_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | head -c16)Aa1!

  az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AZURE_WINDOWS_NAME" \
    --image Win2022Datacenter \
    --size Standard_D2s_v3 \
    --admin-username azureuser \
    --admin-password "$AZURE_WIN_PASSWORD" \
    --assign-identity "[system]" \
    --public-ip-sku Standard \
    --tags $AZURE_TAGS OS=windows \
    --subscription "$AZURE_SUBSCRIPTION_ID" \
    --output none \
    --no-wait
  ok "Azure Windows VM creation started: $AZURE_WINDOWS_NAME"

  # Save state (don't save the password to state — it's ephemeral)
  cat >> "$STATE_FILE" <<EOF
AZURE_RG="$RESOURCE_GROUP"
AZURE_LINUX_NAME="$AZURE_LINUX_NAME"
AZURE_WINDOWS_NAME="$AZURE_WINDOWS_NAME"
EOF

  log "Waiting for Azure VMs to finish provisioning (this takes 3-5 min)..."
  az vm wait --created --resource-group "$RESOURCE_GROUP" \
    --name "$AZURE_LINUX_NAME" --subscription "$AZURE_SUBSCRIPTION_ID"
  az vm wait --created --resource-group "$RESOURCE_GROUP" \
    --name "$AZURE_WINDOWS_NAME" --subscription "$AZURE_SUBSCRIPTION_ID"
  ok "Azure VMs running"

  # ── Enable Azure Update Manager patch assessment ──────────────────────────
  log "Enabling periodic assessment on Azure VMs..."
  for VM in "$AZURE_LINUX_NAME" "$AZURE_WINDOWS_NAME"; do
    az vm assess-patches \
      --resource-group "$RESOURCE_GROUP" \
      --name "$VM" \
      --subscription "$AZURE_SUBSCRIPTION_ID" \
      --output none 2>/dev/null || true
  done
  ok "Azure patch assessment triggered"
fi

# ══════════════════════════════════════════════════════════════════════════════
# GCP
# VM type:  e2-micro (2 vCPU shared, 1 GB) — cheapest GCE: ~$0.0067/hr
#           n1-standard-1 (1 vCPU, 3.75 GB) — cheapest Windows-capable: ~$0.035/hr
# Linux:    Debian 12 (OS Config Agent pre-installed on all official GCE images)
# Windows:  Windows Server 2022 (OS Config Agent included)
# Auth:     Compute service account with osconfig.patchJobExecutor role
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$RUN_GCP" == "true" ]]; then
  log "=== GCP: Creating VMs ==="

  # ── Enable required APIs ──────────────────────────────────────────────────
  log "Enabling GCP APIs (osconfig, compute)..."
  gcloud services enable osconfig.googleapis.com compute.googleapis.com \
    --project "$GCP_PROJECT" --quiet
  ok "GCP APIs enabled"

  # ── Enable OS Config for the project ─────────────────────────────────────
  gcloud compute project-info add-metadata \
    --metadata enable-osconfig=true \
    --project "$GCP_PROJECT" --quiet
  ok "OS Config enabled project-wide"

  # ── Debian 12 (e2-micro) ─────────────────────────────────────────────────
  GCP_LINUX_NAME="${PREFIX}-linux"
  gcloud compute instances create "$GCP_LINUX_NAME" \
    --project "$GCP_PROJECT" \
    --zone "$GCP_ZONE" \
    --machine-type e2-micro \
    --image-project debian-cloud \
    --image-family debian-12 \
    --labels "$GCP_LABELS,os=linux" \
    --metadata "enable-osconfig=true" \
    --scopes "https://www.googleapis.com/auth/cloud-platform" \
    --quiet
  ok "GCP Linux VM created: $GCP_LINUX_NAME"

  # ── Windows Server 2022 (n1-standard-1 — minimum for Windows) ────────────
  GCP_WINDOWS_NAME="${PREFIX}-windows"
  gcloud compute instances create "$GCP_WINDOWS_NAME" \
    --project "$GCP_PROJECT" \
    --zone "$GCP_ZONE" \
    --machine-type n1-standard-1 \
    --image-project windows-cloud \
    --image-family windows-2022 \
    --labels "$GCP_LABELS,os=windows" \
    --metadata "enable-osconfig=true,sysprep-specialize-script-ps1=Set-Service -Name 'google-osconfig-agent' -StartupType Automatic" \
    --scopes "https://www.googleapis.com/auth/cloud-platform" \
    --quiet
  ok "GCP Windows VM created: $GCP_WINDOWS_NAME"

  # Save state
  cat >> "$STATE_FILE" <<EOF
GCP_LINUX_NAME="$GCP_LINUX_NAME"
GCP_WINDOWS_NAME="$GCP_WINDOWS_NAME"
GCP_ZONE="$GCP_ZONE"
EOF
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  VM CREATION COMPLETE"
echo "═══════════════════════════════════════════════════════════════"
[[ "$RUN_AWS" == "true" ]] && echo "  AWS Linux:    $AWS_LINUX_ID  ($AWS_REGION)"
[[ "$RUN_AWS" == "true" ]] && echo "  AWS Windows:  $AWS_WINDOWS_ID ($AWS_REGION)"
[[ "$RUN_AZURE" == "true" ]] && echo "  Azure Linux:  $AZURE_LINUX_NAME  ($AZURE_REGION)"
[[ "$RUN_AZURE" == "true" ]] && echo "  Azure Windows:$AZURE_WINDOWS_NAME ($AZURE_REGION)"
[[ "$RUN_GCP" == "true" ]] && echo "  GCP Linux:    $GCP_LINUX_NAME  ($GCP_ZONE)"
[[ "$RUN_GCP" == "true" ]] && echo "  GCP Windows:  $GCP_WINDOWS_NAME ($GCP_ZONE)"
echo ""
echo "  State saved to: $STATE_FILE"
echo "  To destroy all VMs: ./scripts/destroy-vms.sh"
echo "  TTL: 24 hours — REMEMBER to destroy to avoid charges!"
echo "═══════════════════════════════════════════════════════════════"
