#!/bin/bash
# test-azure.sh - Manual test of Azure Update Manager
# Usage: ./test-azure.sh [vm-name]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-2f791c46-1726-4a0c-94e8-48314ac8f1b4}"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-patching-system-rg}"

echo "🔧 Azure Update Manager Patch Compliance Test"
echo "==============================================="

# Get VM name if not provided
if [ -z "${1:-}" ]; then
    echo "📋 Fetching Azure VMs with patching tags..."
    VM_NAME=$(az vm list \
        --resource-group "$RESOURCE_GROUP" \
        --subscription "$AZURE_SUBSCRIPTION_ID" \
        --query "[?tags.Environment=='testing'].name | [0]" \
        --output tsv 2>/dev/null)

    if [ -z "$VM_NAME" ] || [ "$VM_NAME" = "None" ]; then
        echo -e "${RED}❌ No test VMs found in $RESOURCE_GROUP. Run ./scripts/create-vms.sh first${NC}"
        exit 1
    fi
else
    VM_NAME="$1"
fi

echo -e "${GREEN}✅ Testing VM: $VM_NAME${NC}"

# Check VM power state
echo ""
echo "⚡ Checking VM power state..."
POWER_STATE=$(az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --subscription "$AZURE_SUBSCRIPTION_ID" \
    --show-details \
    --query "powerState" \
    --output tsv)

if [ "$POWER_STATE" != "VM running" ]; then
    echo -e "${RED}❌ VM is not running. State: $POWER_STATE${NC}"
    exit 1
fi
echo -e "${GREEN}✅ VM is running${NC}"

# Get OS type for later use during install
OS_TYPE=$(az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --subscription "$AZURE_SUBSCRIPTION_ID" \
    --query "storageProfile.osDisk.osType" \
    --output tsv)
echo "   OS type: $OS_TYPE"

# Run patch assessment
echo ""
echo "🔍 Running patch assessment..."
ASSESSMENT=$(az vm assess-patches \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --subscription "$AZURE_SUBSCRIPTION_ID" \
    --output json)

echo ""
echo "📊 Patch assessment results:"
CRITICAL_COUNT=$(echo "$ASSESSMENT" | python3 -c \
    "import json,sys; d=json.load(sys.stdin); print(d.get('availablePatchSummary', {}).get('criticalAndSecurityPatchCount', 0))" \
    2>/dev/null || echo "0")
OTHER_COUNT=$(echo "$ASSESSMENT" | python3 -c \
    "import json,sys; d=json.load(sys.stdin); print(d.get('availablePatchSummary', {}).get('otherPatchCount', 0))" \
    2>/dev/null || echo "0")
REBOOT=$(echo "$ASSESSMENT" | python3 -c \
    "import json,sys; d=json.load(sys.stdin); print(d.get('availablePatchSummary', {}).get('rebootPending', False))" \
    2>/dev/null || echo "False")
STATUS=$(echo "$ASSESSMENT" | python3 -c \
    "import json,sys; d=json.load(sys.stdin); print(d.get('availablePatchSummary', {}).get('status', 'Unknown'))" \
    2>/dev/null || echo "Unknown")

echo "   Assessment status: $STATUS"
echo "   Critical/Security patches: $CRITICAL_COUNT"
echo "   Other patches: $OTHER_COUNT"
echo "   Reboot pending: $REBOOT"

echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "   Total patches available: $((CRITICAL_COUNT + OTHER_COUNT))"
echo "   Critical/Security: $CRITICAL_COUNT"

if [ "${CRITICAL_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    echo -e "${RED}⚠️  WARNING: $CRITICAL_COUNT critical/security patches pending${NC}"
else
    echo -e "${GREEN}✅ No critical patches pending${NC}"
fi

# Optional: Apply patches
echo ""
read -p "Do you want to apply Critical/Security patches now? (yes/no): " APPLY_PATCHES
if [ "$APPLY_PATCHES" = "yes" ]; then
    echo "🔄 Applying patches (this may reboot if required)..."
    if [ "$OS_TYPE" = "Linux" ]; then
        az vm install-patches \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VM_NAME" \
            --subscription "$AZURE_SUBSCRIPTION_ID" \
            --maximum-duration PT2H \
            --reboot-setting IfRequired \
            --classifications-to-include-linux Critical Security \
            --output none
    else
        az vm install-patches \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VM_NAME" \
            --subscription "$AZURE_SUBSCRIPTION_ID" \
            --maximum-duration PT2H \
            --reboot-setting IfRequired \
            --classifications-to-include-windows Critical Security \
            --output none
    fi
    echo -e "${GREEN}✅ Patch installation complete${NC}"
fi

echo ""
echo -e "${GREEN}✅ Test complete${NC}"
