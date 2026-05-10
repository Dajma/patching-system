#!/usr/bin/env bash
# azure-service-account.sh — Create a scoped Azure service principal for the
# patching-system automation. Scoped ONLY to the Visual Studio subscription
# to prevent accidental resource creation in other subscriptions.
#
# What this creates:
#   - Service principal: "patching-system-sp"
#   - Custom role: "Patching System Operator" (least-privilege)
#   - Scope: Visual Studio Enterprise Subscription only
#   - Output: credentials saved to .azure-sp-credentials.env (gitignored)

set -euo pipefail

SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-2f791c46-1726-4a0c-94e8-48314ac8f1b4}"
SP_NAME="patching-system-sp"
ROLE_NAME="Patching System Operator"
CREDS_FILE="$(dirname "$0")/.azure-sp-credentials.env"
ROLE_DEF_FILE="$(dirname "$0")/../iam/azure-patching-role.json"

log()  { echo "[$(date -u '+%H:%M:%S')] $*"; }
ok()   { echo "[$(date -u '+%H:%M:%S')] ✓ $*"; }
die()  { echo "[$(date -u '+%H:%M:%S')] ✗ $*" >&2; exit 1; }

# ── Pre-flight ────────────────────────────────────────────────────────────────
az account show --subscription "$SUBSCRIPTION_ID" > /dev/null 2>&1 \
  || die "Not logged in or subscription not accessible. Run 'az login'."

az account set --subscription "$SUBSCRIPTION_ID"
log "Using subscription: $(az account show --query 'name' -o tsv) ($SUBSCRIPTION_ID)"

SCOPE="/subscriptions/$SUBSCRIPTION_ID"

# ── Custom role (least-privilege) ─────────────────────────────────────────────
log "Creating/updating custom RBAC role: '$ROLE_NAME'..."

# Write the role definition with the correct subscription ID substituted in
mkdir -p "$(dirname "$ROLE_DEF_FILE")"
cat > "$ROLE_DEF_FILE" <<ROLEEOF
{
  "Name": "$ROLE_NAME",
  "Description": "Least-privilege role for patching-system automation. Scoped to Visual Studio subscription only.",
  "IsCustom": true,
  "Actions": [
    "Microsoft.Compute/virtualMachines/read",
    "Microsoft.Compute/virtualMachines/write",
    "Microsoft.Compute/virtualMachines/restart/action",
    "Microsoft.Compute/virtualMachines/assessPatches/action",
    "Microsoft.Compute/virtualMachines/installPatches/action",
    "Microsoft.Maintenance/maintenanceConfigurations/read",
    "Microsoft.Maintenance/maintenanceConfigurations/write",
    "Microsoft.Maintenance/maintenanceConfigurations/delete",
    "Microsoft.Maintenance/configurationAssignments/read",
    "Microsoft.Maintenance/configurationAssignments/write",
    "Microsoft.Maintenance/configurationAssignments/delete",
    "Microsoft.Maintenance/applyUpdates/read",
    "Microsoft.Maintenance/applyUpdates/write",
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/subscriptions/resourceGroups/write",
    "Microsoft.Resources/subscriptions/resourceGroups/delete",
    "Microsoft.Network/virtualNetworks/read",
    "Microsoft.Network/publicIPAddresses/read",
    "Microsoft.Network/networkInterfaces/read",
    "Microsoft.Network/networkSecurityGroups/read",
    "Microsoft.OperationalInsights/workspaces/read",
    "Microsoft.OperationalInsights/workspaces/write",
    "Microsoft.OperationalInsights/workspaces/sharedKeys/action",
    "Microsoft.Insights/diagnosticSettings/read",
    "Microsoft.Insights/diagnosticSettings/write"
  ],
  "NotActions": [],
  "DataActions": [],
  "NotDataActions": [],
  "AssignableScopes": [
    "$SCOPE"
  ]
}
ROLEEOF

# Check if role exists
EXISTING_ROLE_ID=$(az role definition list \
  --name "$ROLE_NAME" \
  --scope "$SCOPE" \
  --query '[0].id' -o tsv 2>/dev/null || true)

if [[ -z "$EXISTING_ROLE_ID" || "$EXISTING_ROLE_ID" == "None" ]]; then
  az role definition create --role-definition "@$ROLE_DEF_FILE" --output none
  ok "Custom role created: '$ROLE_NAME'"
  # Wait for role propagation
  sleep 15
else
  az role definition update --role-definition "@$ROLE_DEF_FILE" --output none
  ok "Custom role updated: '$ROLE_NAME'"
fi

# ── Service principal ─────────────────────────────────────────────────────────
log "Creating service principal: $SP_NAME..."

# Check if SP already exists
SP_APP_ID=$(az ad sp list --display-name "$SP_NAME" --query '[0].appId' -o tsv 2>/dev/null || true)

if [[ -z "$SP_APP_ID" || "$SP_APP_ID" == "None" ]]; then
  SP_JSON=$(az ad sp create-for-rbac \
    --name "$SP_NAME" \
    --role "$ROLE_NAME" \
    --scopes "$SCOPE" \
    --years 1 \
    --output json)
  ok "Service principal created"
else
  log "Service principal already exists (appId: $SP_APP_ID). Resetting credentials..."
  SP_JSON=$(az ad sp credential reset --id "$SP_APP_ID" --output json)
  ok "Credentials reset for existing SP"
fi

# ── Save credentials ──────────────────────────────────────────────────────────
CLIENT_ID=$(echo "$SP_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['appId'])")
CLIENT_SECRET=$(echo "$SP_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
TENANT_ID=$(echo "$SP_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['tenant'])")

cat > "$CREDS_FILE" <<CREDSEOF
# Azure Service Principal — patching-system-sp
# Scoped to: Visual Studio Enterprise Subscription ($SUBSCRIPTION_ID)
# Created:   $(date -u)
# WARNING:   Keep this file secret — add to .gitignore!
AZURE_CLIENT_ID="$CLIENT_ID"
AZURE_CLIENT_SECRET="$CLIENT_SECRET"
AZURE_TENANT_ID="$TENANT_ID"
AZURE_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
CREDSEOF
chmod 600 "$CREDS_FILE"

ok "Credentials saved to $CREDS_FILE (mode 600)"

# ── Add to .gitignore (if inside a git repo) ─────────────────────────────────
GIT_ROOT=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "$GIT_ROOT" && -f "$GIT_ROOT/.gitignore" ]]; then
  grep -q ".azure-sp-credentials.env" "$GIT_ROOT/.gitignore" 2>/dev/null || \
    echo ".azure-sp-credentials.env" >> "$GIT_ROOT/.gitignore"
  grep -q ".vm-state.env" "$GIT_ROOT/.gitignore" 2>/dev/null || \
    echo ".vm-state.env" >> "$GIT_ROOT/.gitignore"
fi

# ── Verify assignment ─────────────────────────────────────────────────────────
log "Verifying role assignment..."
ASSIGNMENTS=$(az role assignment list \
  --assignee "$CLIENT_ID" \
  --scope "$SCOPE" \
  --query '[].{Role:roleDefinitionName,Scope:scope}' \
  --output table 2>/dev/null)
echo "$ASSIGNMENTS"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  SERVICE PRINCIPAL CREATED"
echo "═══════════════════════════════════════════════════════════════"
echo "  Name:            $SP_NAME"
echo "  App ID (Client): $CLIENT_ID"
echo "  Tenant ID:       $TENANT_ID"
echo "  Subscription:    $SUBSCRIPTION_ID"
echo "  Role:            $ROLE_NAME (custom, least-privilege)"
echo "  Scope:           Subscription only (NOT tenant-wide)"
echo ""
echo "  To use in scripts:"
echo "    source scripts/.azure-sp-credentials.env"
echo "    az login --service-principal \\"
echo "      --username \$AZURE_CLIENT_ID \\"
echo "      --password \$AZURE_CLIENT_SECRET \\"
echo "      --tenant \$AZURE_TENANT_ID"
echo ""
echo "  Credentials file: scripts/.azure-sp-credentials.env"
echo "  Custom role def:  iam/azure-patching-role.json"
echo "═══════════════════════════════════════════════════════════════"
