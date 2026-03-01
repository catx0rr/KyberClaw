#!/usr/bin/env bash
# pre-commit-sanitize.sh — M8: Pre-commit regex scan for sensitive data
#
# Scans all staged files for patterns that MUST NOT be committed to git.
# Returns 0 if clean, 1 if sensitive data found.
#
# Install as git hook:
#   cp scripts/pre-commit-sanitize.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit

set -euo pipefail

FAIL=0

# Get list of staged files (exclude deleted files)
STAGED_FILES=$(git diff --cached --name-only --diff-filter=d 2>/dev/null)

if [ -z "$STAGED_FILES" ]; then
    exit 0
fi

# Load client org name from ENGAGEMENT.md if it exists (for client name check)
CLIENT_NAME=""
if [ -f "ENGAGEMENT.md" ]; then
    CLIENT_NAME=$(grep -i "^client:" ENGAGEMENT.md 2>/dev/null | head -1 | cut -d: -f2- | xargs || true)
fi

check_pattern() {
    local pattern="$1"
    local description="$2"
    local exclude_pattern="${3:-}"

    for file in $STAGED_FILES; do
        if [ ! -f "$file" ]; then
            continue
        fi

        local matches
        if [ -n "$exclude_pattern" ]; then
            matches=$(grep -nPo "$pattern" "$file" 2>/dev/null | grep -vP "$exclude_pattern" || true)
        else
            matches=$(grep -nPo "$pattern" "$file" 2>/dev/null || true)
        fi

        if [ -n "$matches" ]; then
            echo "SANITIZATION FAILED: $file contains $description"
            echo "$matches" | head -5
            FAIL=1
        fi
    done
}

echo "Running pre-commit sanitization scan..."

# 1. IPv4 addresses (exclude localhost, 0.0.0.0, and documented examples 10.0.0.x)
check_pattern '\b(?!127\.0\.0\.1|0\.0\.0\.0|10\.0\.0\.\d{1,3}|203\.0\.113\.\d{1,3}|198\.51\.100\.\d{1,3}|192\.0\.2\.\d{1,3})\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b' \
    "real IPv4 addresses" \
    '(#|//|<!--|example|template|placeholder|\.0\.0\.|CIDR|format)'

# 2. Anthropic API keys
check_pattern 'sk-ant-[a-zA-Z0-9_-]{20,}' "Anthropic API key"

# 3. Generic API key patterns
check_pattern '(sk-[a-zA-Z0-9]{20,})' "generic API key pattern" '(sk-ant-|example|placeholder|template)'

# 4. NTLM hashes (LM:NT format — 32 hex chars : 32 hex chars)
check_pattern '[a-fA-F0-9]{32}:[a-fA-F0-9]{32}' "NTLM hash pattern" '(example|template|placeholder|pseudo)'

# 5. Kerberos ticket patterns (base64 encoded tickets starting with doIE)
check_pattern 'doIE[a-zA-Z0-9+/=]{50,}' "Kerberos ticket data"

# 6. Cleartext password patterns (password=, passwd:, pwd= followed by non-whitespace)
check_pattern '(password|passwd|pwd)\s*[:=]\s*\S{4,}' "cleartext password pattern" \
    '(example|template|placeholder|pseudo|\$PASS|\$PASSWORD|<password>|\[password\]|REDACTED)'

# 7. Client organization name (if known from ENGAGEMENT.md)
if [ -n "$CLIENT_NAME" ] && [ ${#CLIENT_NAME} -gt 2 ]; then
    for file in $STAGED_FILES; do
        if [ -f "$file" ] && [ "$file" != "ENGAGEMENT.md" ]; then
            if grep -qi "$CLIENT_NAME" "$file" 2>/dev/null; then
                echo "SANITIZATION FAILED: $file contains client organization name '$CLIENT_NAME'"
                FAIL=1
            fi
        fi
    done
fi

if [ $FAIL -eq 1 ]; then
    echo ""
    echo "Commit BLOCKED. Remove sensitive data before committing."
    echo "Files in loot/, reports/, and ENGAGEMENT.md should be gitignored."
    exit 1
else
    echo "Sanitization scan PASSED."
    exit 0
fi
