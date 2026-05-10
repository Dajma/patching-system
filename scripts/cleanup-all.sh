#!/bin/bash
# cleanup-all.sh - Destroy all test VMs and optionally Terraform-managed infrastructure
# Usage: ./cleanup-all.sh [--aws-only | --azure-only | --gcp-only] [--include-terraform] [--force]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STATE_FILE="$SCRIPT_DIR/.vm-state.env"

CLOUD_FLAG=""
INCLUDE_TERRAFORM=false
FORCE=false

for arg in "$@"; do
    case "$arg" in
        --aws-only)          CLOUD_FLAG="--aws-only" ;;
        --azure-only)        CLOUD_FLAG="--azure-only" ;;
        --gcp-only)          CLOUD_FLAG="--gcp-only" ;;
        --include-terraform) INCLUDE_TERRAFORM=true ;;
        --force|-f)          FORCE=true ;;
        --help|-h)
            echo "Usage: $0 [--aws-only | --azure-only | --gcp-only] [--include-terraform] [--force]"
            echo "  --include-terraform  Also destroy Terraform-managed infrastructure"
            echo "  --force              Skip confirmation prompts"
            exit 0 ;;
    esac
done

echo "🧹 Patching System Cleanup"
echo "=========================="
echo ""

if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
    echo "📋 Resources to be destroyed:"
    [ -n "${AWS_LINUX_ID:-}" ]   && echo "   AWS:   $AWS_LINUX_ID, $AWS_WINDOWS_ID (region: ${AWS_REGION:-us-east-1})"
    [ -n "${AZURE_RG:-}" ]       && echo "   Azure: resource group '$AZURE_RG' (ALL resources in it)"
    [ -n "${GCP_LINUX_NAME:-}" ] && echo "   GCP:   $GCP_LINUX_NAME, $GCP_WINDOWS_NAME (zone: ${GCP_ZONE:-us-central1-a})"
else
    echo -e "${YELLOW}⚠️  No state file found. destroy-vms.sh will run but may find nothing to delete.${NC}"
fi

if [ "$INCLUDE_TERRAFORM" = "true" ]; then
    echo ""
    echo -e "${RED}⚠️  --include-terraform: Will also destroy ALL Terraform-managed patching infrastructure${NC}"
    echo "   (SSM baselines, maintenance windows, Log Analytics workspaces, GCS buckets, etc.)"
fi

echo ""
if [ "$FORCE" != "true" ]; then
    read -r -p "Are you sure you want to destroy these resources? (yes/no): " CONFIRM
    if [ "${CONFIRM,,}" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi
fi

# Destroy test VMs
echo ""
echo "🔥 Destroying test VMs..."
# shellcheck disable=SC2086
"$SCRIPT_DIR/destroy-vms.sh" --force $CLOUD_FLAG
echo -e "${GREEN}✅ VM cleanup complete${NC}"

# Optional: Terraform infrastructure cleanup
if [ "$INCLUDE_TERRAFORM" = "true" ]; then
    echo ""
    if [ "$FORCE" != "true" ]; then
        read -r -p "Proceed with Terraform destroy? This removes all patching infrastructure. (yes/no): " TF_CONFIRM
        if [ "${TF_CONFIRM,,}" != "yes" ]; then
            echo "Terraform destroy skipped."
            exit 0
        fi
    fi

    TF_DIRS=()
    if [ -z "$CLOUD_FLAG" ] || [ "$CLOUD_FLAG" = "--aws-only" ]; then
        TF_DIRS+=("$PROJECT_ROOT/terraform/aws")
    fi
    if [ -z "$CLOUD_FLAG" ] || [ "$CLOUD_FLAG" = "--azure-only" ]; then
        TF_DIRS+=("$PROJECT_ROOT/terraform/azure")
    fi
    if [ -z "$CLOUD_FLAG" ] || [ "$CLOUD_FLAG" = "--gcp-only" ]; then
        TF_DIRS+=("$PROJECT_ROOT/terraform/gcp")
    fi

    for dir in "${TF_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            echo ""
            echo "🏗️  Destroying Terraform resources in $dir..."
            terraform -chdir="$dir" destroy -auto-approve
            echo -e "${GREEN}✅ Terraform destroy complete: $dir${NC}"
        else
            echo -e "${YELLOW}⚠️  Terraform directory not found: $dir${NC}"
        fi
    done
fi

echo ""
echo -e "${GREEN}✅ Cleanup complete${NC}"
