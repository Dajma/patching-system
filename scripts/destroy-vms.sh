#!/usr/bin/env bash
# destroy-vms.sh — Tear down all test VMs created by create-vms.sh
# Reads resource IDs from .vm-state.env to avoid accidental deletion of wrong resources.

set -euo pipefail

STATE_FILE="$(dirname "$0")/.vm-state.env"

log()  { echo "[$(date -u '+%H:%M:%S')] $*"; }
ok()   { echo "[$(date -u '+%H:%M:%S')] ✓ $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] ⚠ $*" >&2; }
die()  { echo "[$(date -u '+%H:%M:%S')] ✗ $*" >&2; exit 1; }

# ── Argument parsing ──────────────────────────────────────────────────────────
RUN_AWS=true; RUN_AZURE=true; RUN_GCP=true
FORCE=false

for arg in "$@"; do
  case "$arg" in
    --aws-only)   RUN_AZURE=false; RUN_GCP=false ;;
    --azure-only) RUN_AWS=false;   RUN_GCP=false ;;
    --gcp-only)   RUN_AWS=false;   RUN_AZURE=false ;;
    --force|-f)   FORCE=true ;;
    --help|-h)
      echo "Usage: $0 [--aws-only | --azure-only | --gcp-only] [--force]"
      echo "  --force  Skip confirmation prompt"
      exit 0 ;;
  esac
done

# ── Load state ────────────────────────────────────────────────────────────────
[[ -f "$STATE_FILE" ]] || die "State file not found: $STATE_FILE\nRun create-vms.sh first."
# shellcheck disable=SC1090
source "$STATE_FILE"

# ── Confirm ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  RESOURCES TO BE DESTROYED:"
echo "═══════════════════════════════════════════════════════════════"
[[ "$RUN_AWS" == "true" && -n "${AWS_LINUX_ID:-}" ]] && \
  echo "  AWS: $AWS_LINUX_ID, $AWS_WINDOWS_ID (region: ${AWS_REGION})"
[[ "$RUN_AZURE" == "true" && -n "${AZURE_RG:-}" ]] && \
  echo "  Azure: resource group '$AZURE_RG' (ALL resources in it)"
[[ "$RUN_GCP" == "true" && -n "${GCP_LINUX_NAME:-}" ]] && \
  echo "  GCP: $GCP_LINUX_NAME, $GCP_WINDOWS_NAME (zone: ${GCP_ZONE})"
echo "═══════════════════════════════════════════════════════════════"

if [[ "$FORCE" != "true" ]]; then
  read -r -p "Are you sure you want to destroy these resources? [y/N] " confirm
  [[ "${confirm,,}" == "y" ]] || { log "Aborted."; exit 0; }
fi

# ══════════════════════════════════════════════════════════════════════════════
# AWS
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$RUN_AWS" == "true" && -n "${AWS_LINUX_ID:-}" ]]; then
  log "=== AWS: Terminating EC2 instances ==="

  aws ec2 terminate-instances \
    --instance-ids "$AWS_LINUX_ID" "$AWS_WINDOWS_ID" \
    --region "$AWS_REGION" \
    --output none
  ok "Termination initiated: $AWS_LINUX_ID, $AWS_WINDOWS_ID"

  log "Waiting for instances to terminate..."
  aws ec2 wait instance-terminated \
    --instance-ids "$AWS_LINUX_ID" "$AWS_WINDOWS_ID" \
    --region "$AWS_REGION"
  ok "Instances terminated"

  # Delete security group (after instances terminate)
  if [[ -n "${AWS_SG_ID:-}" ]]; then
    aws ec2 delete-security-group --group-id "$AWS_SG_ID" --region "$AWS_REGION" 2>/dev/null \
      && ok "Security group deleted: $AWS_SG_ID" \
      || warn "Security group $AWS_SG_ID not deleted (may still be in use)"
  fi

  # Detach and delete IAM instance profile
  if [[ -n "${AWS_IAM_PROFILE:-}" && -n "${AWS_IAM_ROLE:-}" ]]; then
    aws iam remove-role-from-instance-profile \
      --instance-profile-name "$AWS_IAM_PROFILE" \
      --role-name "$AWS_IAM_ROLE" 2>/dev/null || true
    aws iam delete-instance-profile \
      --instance-profile-name "$AWS_IAM_PROFILE" 2>/dev/null \
      && ok "Instance profile deleted" || warn "Instance profile already gone"
    aws iam detach-role-policy \
      --role-name "$AWS_IAM_ROLE" \
      --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
    aws iam delete-role --role-name "$AWS_IAM_ROLE" 2>/dev/null \
      && ok "IAM role deleted" || warn "IAM role already gone"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# AZURE — Delete the entire resource group (fastest, cleanest approach)
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$RUN_AZURE" == "true" && -n "${AZURE_RG:-}" ]]; then
  log "=== Azure: Deleting resource group '$AZURE_RG' ==="
  log "This deletes ALL resources in the group. Starting async delete..."

  az group delete \
    --name "$AZURE_RG" \
    --subscription "$AZURE_SUBSCRIPTION_ID" \
    --yes \
    --no-wait \
    --output none
  ok "Azure resource group deletion initiated: $AZURE_RG (runs async in background)"
  log "Note: Azure RG deletion takes 3-10 minutes. Check portal to confirm completion."
fi

# ══════════════════════════════════════════════════════════════════════════════
# GCP
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$RUN_GCP" == "true" && -n "${GCP_LINUX_NAME:-}" ]]; then
  log "=== GCP: Deleting VM instances ==="

  gcloud compute instances delete "$GCP_LINUX_NAME" "$GCP_WINDOWS_NAME" \
    --project "$GCP_PROJECT" \
    --zone "$GCP_ZONE" \
    --quiet
  ok "GCP VMs deleted: $GCP_LINUX_NAME, $GCP_WINDOWS_NAME"
fi

# ── Cleanup state file ────────────────────────────────────────────────────────
rm -f "$STATE_FILE"
ok "State file removed"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  DESTRUCTION COMPLETE"
echo "  All test VMs and associated resources have been removed."
echo "═══════════════════════════════════════════════════════════════"
