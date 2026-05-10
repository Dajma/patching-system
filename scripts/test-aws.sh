#!/bin/bash
# test-aws.sh - Manual test of AWS SSM Patch Manager
# Usage: ./test-aws.sh [instance-id]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

AWS_REGION="${AWS_REGION:-us-east-1}"

echo "🔧 AWS Systems Manager Patch Compliance Test"
echo "============================================="

# Get instance ID if not provided
if [ -z "${1:-}" ]; then
    echo "📋 Fetching EC2 instances with SSM agent..."
    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:Environment,Values=testing" "Name=tag:Project,Values=patching-system" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text \
        --region "$AWS_REGION")

    if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then
        echo -e "${RED}❌ No test instances found. Run ./scripts/create-vms.sh first${NC}"
        exit 1
    fi
else
    INSTANCE_ID="$1"
fi

echo -e "${GREEN}✅ Testing instance: $INSTANCE_ID${NC}"

# Check if instance has SSM agent registered
echo ""
echo "📡 Checking SSM agent registration..."
SSM_STATUS=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query "InstanceInformationList[0].PingStatus" \
    --output text \
    --region "$AWS_REGION")

if [ "$SSM_STATUS" != "Online" ]; then
    echo -e "${RED}❌ SSM agent not online. Status: $SSM_STATUS${NC}"
    echo "   Ensure instance has IAM role with AmazonSSMManagedInstanceCore"
    exit 1
fi
echo -e "${GREEN}✅ SSM agent is online${NC}"

# Run patch compliance scan (no installation)
echo ""
echo "🔍 Running patch compliance scan (dry-run)..."
SCAN_ID=$(aws ssm send-command \
    --document-name "AWS-RunPatchBaseline" \
    --instance-ids "$INSTANCE_ID" \
    --parameters '{"Operation":["Scan"]}' \
    --comment "Manual compliance test" \
    --query "Command.CommandId" \
    --output text \
    --region "$AWS_REGION")

echo "   Scan command ID: $SCAN_ID"
echo "   Waiting for scan to complete (30 seconds)..."
sleep 30

# Get scan results
echo ""
echo "📊 Patch compliance results:"
aws ssm get-command-invocation \
    --command-id "$SCAN_ID" \
    --instance-id "$INSTANCE_ID" \
    --query "StandardOutputContent" \
    --output text \
    --region "$AWS_REGION" | grep -E "(Missing|Installed|Failed|Compliance)" || true

# Get missing patches count
MISSING_COUNT=$(aws ssm describe-instance-patch-states \
    --instance-ids "$INSTANCE_ID" \
    --query "InstancePatchStates[0].MissingCount" \
    --output text \
    --region "$AWS_REGION")

CRITICAL_COUNT=$(aws ssm describe-instance-patches \
    --instance-id "$INSTANCE_ID" \
    --filters "Key=Classification,Values=Security" \
    --query "length(Patches[?Severity=='Critical'])" \
    --output text \
    --region "$AWS_REGION")

echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "   Missing patches: $MISSING_COUNT"
echo "   Critical security patches: $CRITICAL_COUNT"

if [ "${CRITICAL_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    echo -e "${RED}⚠️  WARNING: $CRITICAL_COUNT critical patches pending${NC}"
else
    echo -e "${GREEN}✅ No critical patches pending${NC}"
fi

# Optional: Run actual patching
echo ""
read -p "Do you want to apply patches now? (yes/no): " APPLY_PATCHES
if [ "$APPLY_PATCHES" = "yes" ]; then
    echo "🔄 Applying patches (this will reboot if required)..."
    aws ssm send-command \
        --document-name "AWS-RunPatchBaseline" \
        --instance-ids "$INSTANCE_ID" \
        --parameters '{"Operation":["Install"]}' \
        --comment "Manual patch installation" \
        --region "$AWS_REGION" \
        --output none
    echo -e "${GREEN}✅ Patch installation initiated${NC}"
fi

echo ""
echo -e "${GREEN}✅ Test complete${NC}"
