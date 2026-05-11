#!/usr/bin/env bash
# verify-agents.sh — Confirm cloud-native patch agents are online before patching proceeds.
#
# Reads scripts/.vm-state.env for instance IDs/names written by create-vms.sh.
# Exits 0 only when ALL selected agents are confirmed online.
# Exits 1 if any agent fails or times out.
#
# Usage: ./scripts/verify-agents.sh [--aws-only | --azure-only | --gcp-only]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STATE_FILE="$(dirname "$0")/.vm-state.env"

log()  { echo "[$(date -u '+%H:%M:%S')] $*"; }
ok()   { echo -e "[$(date -u '+%H:%M:%S')] ${GREEN}✓${NC} $*"; }
warn() { echo -e "[$(date -u '+%H:%M:%S')] ${YELLOW}⚠${NC} $*" >&2; }
die()  { echo -e "[$(date -u '+%H:%M:%S')] ${RED}✗${NC} $*" >&2; exit 1; }

# ── Argument parsing ──────────────────────────────────────────────────────────
RUN_AWS=true; RUN_AZURE=true; RUN_GCP=true

for arg in "$@"; do
  case "$arg" in
    --aws-only)   RUN_AZURE=false; RUN_GCP=false ;;
    --azure-only) RUN_AWS=false;   RUN_GCP=false ;;
    --gcp-only)   RUN_AWS=false;   RUN_AZURE=false ;;
    --help|-h)
      echo "Usage: $0 [--aws-only | --azure-only | --gcp-only]"
      exit 0
      ;;
  esac
done

# ── Load state ────────────────────────────────────────────────────────────────
[[ -f "$STATE_FILE" ]] || die "State file not found: $STATE_FILE — run create-vms.sh first."
# shellcheck disable=SC1090
source "$STATE_FILE"

FAILED=0

# ══════════════════════════════════════════════════════════════════════════════
# AWS — SSM Agent must report PingStatus=Online
# Polls every 20 s, up to 8 minutes (24 attempts)
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$RUN_AWS" == "true" ]]; then
  log "=== AWS: Verifying SSM Agent ==="

  [[ -n "${AWS_LINUX_ID:-}"   ]] || die "AWS_LINUX_ID not set in state file."
  [[ -n "${AWS_WINDOWS_ID:-}" ]] || die "AWS_WINDOWS_ID not set in state file."
  [[ -n "${AWS_REGION:-}"     ]] || die "AWS_REGION not set in state file."

  AWS_VERIFIED=false
  for i in $(seq 1 24); do
    ONLINE_IDS=$(aws ssm describe-instance-information \
      --filters \
        "Key=InstanceIds,Values=${AWS_LINUX_ID},${AWS_WINDOWS_ID}" \
        "Key=PingStatus,Values=Online" \
      --query "InstanceInformationList[].InstanceId" \
      --output text \
      --region "$AWS_REGION" 2>/dev/null || true)

    ONLINE_COUNT=$(echo "$ONLINE_IDS" | tr '\t' '\n' | grep -c "^i-" || true)
    log "  SSM agents online: $ONLINE_COUNT / 2  (attempt $i/24)"

    if [[ "$ONLINE_COUNT" -ge 2 ]]; then
      ok "AWS SSM Agent: both instances online"
      AWS_VERIFIED=true
      break
    fi

    if [[ "$i" -eq 24 ]]; then
      warn "SSM Agent verification timed out after 8 minutes."
      warn "  Linux  ($AWS_LINUX_ID):   check IAM role has AmazonSSMManagedInstanceCore"
      warn "  Windows ($AWS_WINDOWS_ID): check IAM role has AmazonSSMManagedInstanceCore"
      warn "  If using a non-standard AMI, build: packer/aws/amazon-linux-ssm.pkr.hcl"
      FAILED=1
    fi

    sleep 20
  done

  if [[ "$AWS_VERIFIED" == "false" && "$FAILED" -eq 0 ]]; then
    FAILED=1
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Azure — Azure VM Agent must report ProvisioningState/succeeded → "Ready"
# Uses platform-reported status (no SSH/run-command needed).
# Polls every 20 s, up to 5 minutes (15 attempts)
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$RUN_AZURE" == "true" ]]; then
  log "=== Azure: Verifying Azure VM Agent ==="

  [[ -n "${AZURE_RG:-}"           ]] || die "AZURE_RG not set in state file."
  [[ -n "${AZURE_LINUX_NAME:-}"   ]] || die "AZURE_LINUX_NAME not set in state file."
  [[ -n "${AZURE_WINDOWS_NAME:-}" ]] || die "AZURE_WINDOWS_NAME not set in state file."

  AZURE_VERIFIED=0

  for VM in "$AZURE_LINUX_NAME" "$AZURE_WINDOWS_NAME"; do
    VM_READY=false
    for i in $(seq 1 15); do
      AGENT_STATUS=$(az vm get-instance-view \
        --resource-group "$AZURE_RG" \
        --name "$VM" \
        --query "instanceView.vmAgent.statuses[?code=='ProvisioningState/succeeded'].displayStatus" \
        --output tsv 2>/dev/null || true)

      log "  $VM agent status: '${AGENT_STATUS:-<not ready>}'  (attempt $i/15)"

      if [[ "$AGENT_STATUS" == "Ready" ]]; then
        ok "Azure VM Agent: $VM — Ready"
        AZURE_VERIFIED=$((AZURE_VERIFIED + 1))
        VM_READY=true
        break
      fi

      if [[ "$i" -eq 15 ]]; then
        warn "Azure VM Agent not ready on $VM after 5 minutes."
        warn "  Linux:   sudo systemctl status walinuxagent"
        warn "  Windows: Get-Service WindowsAzureGuestAgent"
        warn "  If using a non-standard image, build: packer/azure/ubuntu-waagent.pkr.hcl"
        FAILED=1
      fi

      sleep 20
    done
  done

  if [[ "$AZURE_VERIFIED" -ge 2 ]]; then
    ok "Azure VM Agent: both VMs verified"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# GCP — OS Config Agent must have submitted an inventory report
# Polls every 20 s, up to 8 minutes (24 attempts)
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$RUN_GCP" == "true" ]]; then
  log "=== GCP: Verifying OS Config Agent ==="

  [[ -n "${GCP_LINUX_NAME:-}"   ]] || die "GCP_LINUX_NAME not set in state file."
  [[ -n "${GCP_WINDOWS_NAME:-}" ]] || die "GCP_WINDOWS_NAME not set in state file."
  [[ -n "${GCP_PROJECT:-}"      ]] || die "GCP_PROJECT not set in state file."
  [[ -n "${GCP_ZONE:-}"         ]] || die "GCP_ZONE not set in state file."

  GCP_VERIFIED=0

  GCP_TOKEN=$(gcloud auth print-access-token 2>/dev/null)

  for INSTANCE in "$GCP_LINUX_NAME" "$GCP_WINDOWS_NAME"; do
    INSTANCE_READY=false
    for i in $(seq 1 24); do
      # Use REST API directly — gcloud compute os-config inventories has a known
      # CLI quirk where it silently returns nothing even when the API has data.
      OS_NAME=$(curl -s -H "Authorization: Bearer $GCP_TOKEN" \
        "https://osconfig.googleapis.com/v1/projects/${GCP_PROJECT}/locations/${GCP_ZONE}/instances/${INSTANCE}/inventory" \
        2>/dev/null | python3 -c \
        "import json,sys; d=json.load(sys.stdin); print(d.get('osInfo',{}).get('longName',''))" \
        2>/dev/null || true)

      if [[ -n "$OS_NAME" ]]; then
        ok "GCP OS Config Agent: $INSTANCE — reporting ($OS_NAME)"
        GCP_VERIFIED=$((GCP_VERIFIED + 1))
        INSTANCE_READY=true
        break
      fi

      log "  $INSTANCE inventory: not yet available  (attempt $i/24)"

      if [[ "$i" -eq 24 ]]; then
        warn "OS Config Agent not reporting for $INSTANCE after 8 minutes."
        warn "  Verify: VM metadata has enable-osconfig=true"
        warn "  Verify: project metadata has enable-osconfig=true"
        warn "  If using a non-standard image, build: packer/gcp/debian-osconfig.pkr.hcl"
        FAILED=1
      fi

      sleep 20
    done
  done

  if [[ "$GCP_VERIFIED" -ge 2 ]]; then
    ok "GCP OS Config Agent: both instances verified"
  fi
fi

# ── Result ────────────────────────────────────────────────────────────────────
echo ""
if [[ "$FAILED" -ne 0 ]]; then
  die "One or more agents failed verification. See warnings above."
fi

echo -e "${GREEN}All selected agents verified successfully.${NC}"
