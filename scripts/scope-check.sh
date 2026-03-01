#!/usr/bin/env bash
# scope-check.sh — M9: CIDR inclusion/exclusion validator
#
# Validates whether a target IP falls within the engagement scope.
# Returns 0 if in-scope, 1 if out-of-scope, 2 if error.
#
# Usage:
#   ./scripts/scope-check.sh <target_ip> [scope_file]
#
# If scope_file is not provided, reads from ENGAGEMENT.md.
# Requires: ipcalc or Python3 ipaddress module

set -euo pipefail

TARGET_IP="${1:-}"
SCOPE_FILE="${2:-ENGAGEMENT.md}"

if [ -z "$TARGET_IP" ]; then
    echo "Usage: $0 <target_ip> [scope_file]"
    echo "Returns 0 if in-scope, 1 if out-of-scope"
    exit 2
fi

# Validate IP format
if ! echo "$TARGET_IP" | grep -qP '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'; then
    echo "ERROR: Invalid IP format: $TARGET_IP"
    exit 2
fi

if [ ! -f "$SCOPE_FILE" ]; then
    echo "ERROR: Scope file not found: $SCOPE_FILE"
    exit 2
fi

# Extract in-scope and out-of-scope CIDRs from ENGAGEMENT.md
# Expects format:
#   ### In-Scope
#   - CIDRs: 10.0.0.0/24, 192.168.1.0/24
#   ### Out-of-Scope
#   - CIDRs: 10.0.1.0/24

IN_SCOPE_CIDRS=$(sed -n '/### In-Scope/,/### Out-of-Scope/p' "$SCOPE_FILE" | \
    grep -oP '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}' || true)

OUT_SCOPE_CIDRS=$(sed -n '/### Out-of-Scope/,/### Scope Type/p' "$SCOPE_FILE" | \
    grep -oP '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}' || true)

# Also check for specific host exclusions
OUT_SCOPE_HOSTS=$(sed -n '/### Out-of-Scope/,/### Scope Type/p' "$SCOPE_FILE" | \
    grep -oP '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(?!/\d)' || true)

# Use Python for CIDR matching (more reliable than ipcalc across distros)
python3 -c "
import ipaddress
import sys

target = ipaddress.ip_address('$TARGET_IP')

# Check out-of-scope first (explicit exclusions take priority)
out_scope_cidrs = '''$OUT_SCOPE_CIDRS'''.strip().split()
for cidr in out_scope_cidrs:
    if cidr and target in ipaddress.ip_network(cidr, strict=False):
        print(f'OUT-OF-SCOPE: {target} is in excluded CIDR {cidr}')
        sys.exit(1)

out_scope_hosts = '''$OUT_SCOPE_HOSTS'''.strip().split()
for host in out_scope_hosts:
    if host and target == ipaddress.ip_address(host):
        print(f'OUT-OF-SCOPE: {target} is explicitly excluded')
        sys.exit(1)

# Check in-scope
in_scope_cidrs = '''$IN_SCOPE_CIDRS'''.strip().split()
for cidr in in_scope_cidrs:
    if cidr and target in ipaddress.ip_network(cidr, strict=False):
        print(f'IN-SCOPE: {target} is in {cidr}')
        sys.exit(0)

# Not found in any scope
print(f'OUT-OF-SCOPE: {target} not in any in-scope CIDR')
sys.exit(1)
"
