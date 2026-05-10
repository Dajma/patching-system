#!/usr/bin/env python3
"""compliance-report.py - Aggregate patch compliance data across AWS, Azure, and GCP."""

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone

RED    = '\033[0;31m'
GREEN  = '\033[0;32m'
YELLOW = '\033[1;33m'
NC     = '\033[0m'

AWS_REGION  = 'us-east-1'
AZURE_SUB   = '2f791c46-1726-4a0c-94e8-48314ac8f1b4'
AZURE_RG    = 'patching-system-rg'
GCP_PROJECT = 'learn-image-project'
GCP_ZONE    = 'us-central1-a'


def run(cmd):
    """Run a shell command and return parsed JSON, or None on failure."""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
        if result.returncode != 0 or not result.stdout.strip():
            return None
        return json.loads(result.stdout)
    except Exception:
        return None


def color_status(status):
    s = str(status).upper()
    if any(x in s for x in ('COMPLIANT', 'SUCCEEDED', 'INSTALLED')):
        return GREEN + status + NC
    if any(x in s for x in ('NON_COMPLIANT', 'FAILED', 'ERROR')):
        return RED + status + NC
    return YELLOW + status + NC


def gather_aws(region):
    rows = []
    instances = run(
        f'aws ec2 describe-instances'
        f' --filters "Name=tag:Environment,Values=testing" "Name=tag:Project,Values=patching-system"'
        f' --query "Reservations[].Instances[].[InstanceId,Tags[?Key==\'OS\'].Value|[0]]"'
        f' --output json --region {region}'
    )
    if not instances:
        return rows
    for iid, os_tag in instances:
        state = run(
            f'aws ssm describe-instance-patch-states'
            f' --instance-ids {iid}'
            f' --query "InstancePatchStates[0]"'
            f' --output json --region {region}'
        )
        if state:
            missing = state.get('MissingCount', '?')
            status  = state.get('OperationStatus', 'UNKNOWN')
            checked = str(state.get('OperationEndTime', 'N/A'))[:16]
        else:
            missing, status, checked = '?', 'NOT_SCANNED', 'N/A'
        rows.append({
            'cloud':   'AWS',
            'vm':      f"{iid} ({os_tag or '?'})",
            'os':      (os_tag or '?').capitalize(),
            'status':  status,
            'missing': str(missing),
            'checked': checked,
        })
    return rows


def gather_azure(subscription, rg):
    rows = []
    vms = run(
        f'az vm list --resource-group {rg} --subscription {subscription}'
        f' --query "[?tags.Environment==\'testing\'].[name,storageProfile.osDisk.osType]"'
        f' --output json'
    )
    if not vms:
        return rows
    for name, os_type in vms:
        summary = run(
            f'az vm show --resource-group {rg} --name {name} --subscription {subscription}'
            f' --query "patchStatus.availablePatchSummary" --output json'
        )
        if summary and isinstance(summary, dict):
            critical = summary.get('criticalAndSecurityPatchCount') or 0
            other    = summary.get('otherPatchCount') or 0
            missing  = critical + other
            status   = summary.get('status', 'Unknown')
            checked  = str(summary.get('lastModifiedTime', 'N/A'))[:16]
        else:
            missing, status, checked = '?', 'Unknown', 'N/A'
        rows.append({
            'cloud':   'Azure',
            'vm':      name,
            'os':      os_type or '?',
            'status':  status,
            'missing': str(missing),
            'checked': checked,
        })
    return rows


def gather_gcp(project, zone):
    rows = []
    instances = run(
        f'gcloud compute instances list --project {project}'
        f' --filter "labels.environment=testing AND labels.project=patching-system"'
        f' --format "json(name,labels)" --limit=10'
    )
    if not instances:
        return rows
    last_job = run(
        f'gcloud compute os-config patch-jobs list --project {project}'
        f' --limit=1 --format "json(name,state,createTime)"'
    )
    job_state = last_job[0].get('state', 'NONE') if last_job else 'NONE'
    job_time  = str(last_job[0].get('createTime', 'N/A'))[:16] if last_job else 'N/A'
    for inst in instances:
        name   = inst.get('name', '?')
        labels = inst.get('labels', {})
        os_tag = labels.get('os', '?').capitalize()
        rows.append({
            'cloud':   'GCP',
            'vm':      name,
            'os':      os_tag,
            'status':  job_state,
            'missing': '?',
            'checked': job_time,
        })
    return rows


def print_table(rows):
    if not rows:
        print(f"{YELLOW}No compliance data found. Ensure VMs are running and scanned.{NC}")
        return
    headers = ['Cloud', 'VM', 'OS', 'Status', 'Missing', 'Last Checked']
    cols    = ['cloud', 'vm', 'os', 'status', 'missing', 'checked']
    widths  = [len(h) for h in headers]
    for r in rows:
        for i, c in enumerate(cols):
            widths[i] = max(widths[i], len(str(r[c])))

    print('  '.join(f'{h:<{w}}' for h, w in zip(headers, widths)))
    print('  '.join('-' * w for w in widths))
    for r in rows:
        parts = []
        for c, w in zip(cols, widths):
            val = str(r[c])
            if c == 'status':
                parts.append(color_status(val) + ' ' * (w - len(val)))
            else:
                parts.append(f'{val:<{w}}')
        print('  '.join(parts))


def main():
    parser = argparse.ArgumentParser(description='Multi-cloud patch compliance report')
    parser.add_argument('--aws',            action='store_true')
    parser.add_argument('--azure',          action='store_true')
    parser.add_argument('--gcp',            action='store_true')
    parser.add_argument('--json',           action='store_true', help='Output raw JSON')
    parser.add_argument('--region',         default=AWS_REGION,  help='AWS region')
    parser.add_argument('--resource-group', default=AZURE_RG,    help='Azure resource group')
    parser.add_argument('--project',        default=GCP_PROJECT, help='GCP project ID')
    parser.add_argument('--zone',           default=GCP_ZONE,    help='GCP zone')
    args = parser.parse_args()

    run_all   = not (args.aws or args.azure or args.gcp)
    run_aws   = run_all or args.aws
    run_azure = run_all or args.azure
    run_gcp   = run_all or args.gcp

    print("☁️  Multi-Cloud Patch Compliance Report")
    print('=' * 40)
    print(f"Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC")
    print()

    rows = []
    if run_aws:
        print(f"🔍 Gathering AWS data ({args.region})...")
        rows += gather_aws(args.region)
    if run_azure:
        print(f"🔍 Gathering Azure data ({args.resource_group})...")
        rows += gather_azure(AZURE_SUB, args.resource_group)
    if run_gcp:
        print(f"🔍 Gathering GCP data ({args.project})...")
        rows += gather_gcp(args.project, args.zone)

    print()

    if args.json:
        print(json.dumps(rows, indent=2))
    else:
        print_table(rows)

    non_compliant = sum(
        1 for r in rows
        if any(x in r['status'].upper() for x in ('NON_COMPLIANT', 'FAILED', 'ERROR'))
    )
    print()
    if non_compliant:
        print(f"{RED}⚠️  {non_compliant} non-compliant/failed VM(s) found{NC}")
        sys.exit(1)
    else:
        print(f"{GREEN}✅ All scanned VMs are compliant{NC}")


if __name__ == '__main__':
    main()
