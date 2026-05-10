#!/bin/bash
# test-gcp.sh - Manual test of GCP OS Patch
# Usage: ./test-gcp.sh [instance-name]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

GCP_PROJECT="${GCP_PROJECT:-learn-image-project}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"

echo "🔧 GCP OS Patch Compliance Test"
echo "================================"

# Get instance name if not provided
if [ -z "${1:-}" ]; then
    echo "📋 Fetching GCP instances with patching labels..."
    INSTANCE_NAME=$(gcloud compute instances list \
        --project "$GCP_PROJECT" \
        --filter "labels.environment=testing AND labels.project=patching-system AND status=RUNNING" \
        --format "value(name)" \
        --limit=1 2>/dev/null)

    if [ -z "$INSTANCE_NAME" ]; then
        echo -e "${RED}❌ No running test instances found. Run ./scripts/create-vms.sh first${NC}"
        exit 1
    fi
else
    INSTANCE_NAME="$1"
fi

echo -e "${GREEN}✅ Testing instance: $INSTANCE_NAME${NC}"

# Check instance status
echo ""
echo "⚡ Checking instance status..."
STATUS=$(gcloud compute instances describe "$INSTANCE_NAME" \
    --project "$GCP_PROJECT" \
    --zone "$GCP_ZONE" \
    --format "value(status)" 2>/dev/null)

if [ "$STATUS" != "RUNNING" ]; then
    echo -e "${RED}❌ Instance is not running. Status: $STATUS${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Instance is running${NC}"

# Check OS Config agent via inventory
echo ""
echo "📡 Checking OS Config agent (inventory)..."
INVENTORY=$(gcloud compute os-config inventories describe "$INSTANCE_NAME" \
    --project "$GCP_PROJECT" \
    --zone "$GCP_ZONE" \
    --format json 2>/dev/null || echo "{}")

if [ "$INVENTORY" = "{}" ] || [ -z "$INVENTORY" ]; then
    echo -e "${YELLOW}⚠️  No OS Config inventory found. The agent may still be initializing.${NC}"
    echo "   Ensure the VM has metadata 'enable-osconfig=true' and the OS Config API is enabled."
    echo "   Enable with: gcloud compute project-info add-metadata --metadata enable-osconfig=true --project $GCP_PROJECT"
else
    echo -e "${GREEN}✅ OS Config agent is reporting${NC}"
    OS_NAME=$(echo "$INVENTORY" | python3 -c \
        "import json,sys; d=json.load(sys.stdin); print(d.get('osInfo', {}).get('longName', 'Unknown'))" \
        2>/dev/null || echo "Unknown")
    KERNEL=$(echo "$INVENTORY" | python3 -c \
        "import json,sys; d=json.load(sys.stdin); print(d.get('osInfo', {}).get('kernelVersion', 'Unknown'))" \
        2>/dev/null || echo "Unknown")
    echo "   OS: $OS_NAME"
    echo "   Kernel: $KERNEL"
fi

# List recent patch jobs
echo ""
echo "📊 Recent patch jobs (last 5):"
gcloud compute os-config patch-jobs list \
    --project "$GCP_PROJECT" \
    --limit=5 \
    --format="table(name.basename():label=JOB_ID,state,instanceDetailsSummary.instancesSucceeded:label=SUCCEEDED,instanceDetailsSummary.instancesFailed:label=FAILED,createTime)" \
    2>/dev/null || echo "   No patch jobs found."

# Get latest job state for summary
LATEST_STATE=$(gcloud compute os-config patch-jobs list \
    --project "$GCP_PROJECT" \
    --limit=1 \
    --format "value(state)" 2>/dev/null || echo "")

echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "   Instance: $INSTANCE_NAME ($GCP_ZONE)"
echo "   Latest patch job state: ${LATEST_STATE:-NONE}"

if [ "$LATEST_STATE" = "FAILED" ]; then
    echo -e "${RED}⚠️  WARNING: Last patch job failed${NC}"
elif [ "$LATEST_STATE" = "SUCCEEDED" ]; then
    echo -e "${GREEN}✅ Last patch job succeeded${NC}"
else
    echo -e "${YELLOW}ℹ️  No recent patch jobs or job still in progress${NC}"
fi

# Optional: Execute a patch job
echo ""
read -p "Do you want to execute a patch job on this instance now? (yes/no): " RUN_JOB
if [ "$RUN_JOB" = "yes" ]; then
    echo "🔄 Executing patch job (this may take several minutes)..."
    JOB_OUTPUT=$(gcloud compute os-config patch-jobs execute \
        --project "$GCP_PROJECT" \
        --instance-filter-names="zones/$GCP_ZONE/instances/$INSTANCE_NAME" \
        --duration=1h \
        --description="Manual test patch" \
        --format json 2>/dev/null)
    JOB_ID=$(echo "$JOB_OUTPUT" | python3 -c \
        "import json,sys; d=json.load(sys.stdin); print(d.get('name', '').split('/')[-1])" \
        2>/dev/null || echo "unknown")
    echo -e "${GREEN}✅ Patch job initiated: $JOB_ID${NC}"
    echo "   Monitor with: gcloud compute os-config patch-jobs describe $JOB_ID --project $GCP_PROJECT"
fi

echo ""
echo -e "${GREEN}✅ Test complete${NC}"
