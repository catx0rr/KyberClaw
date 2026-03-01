#!/usr/bin/env bash
# setup-kyberclaw.sh — KyberClaw Automated Installer
#
# Installs and configures KyberClaw: an autonomous AI penetration testing agent
# built on the OpenClaw framework. Supports both fresh installations and
# workspace recovery from git remote.
#
# Usage:
#   ./setup-kyberclaw.sh [OPTIONS]
#
# Options:
#   --force-wipe     Override pre-wipe protection (DATA WILL BE LOST)
#   --skip-arsenal   Skip pentest tool installation (Phase 6)
#   --workspace-only Skip OpenClaw install, only overlay workspace (Phase 5)
#   --dry-run        Print actions without executing
#   --help           Show this help message
#
# Phases:
#   0 — Prerequisites + Pre-Wipe Protection
#   1 — Install OpenClaw
#   2 — Onboard Agent
#   3 — Install Managed Skills
#   4 — Configure Tools + Enable Hooks
#   5 — Overlay Workspace (git clone or fresh)
#   6 — Install Pentest Arsenal
#   7 — Lockdown + Validation
#
# Environment variables (optional — prompted if missing):
#   ANTHROPIC_API_KEY     — Anthropic API key (required)
#   MINIMAX_API_KEY       — MiniMax API key (required)
#   SYNTHETIC_API_KEY     — Synthetic API key (required)
#   BRAVE_API_KEY         — Brave Search API key (required)
#   OPENCLAW_GATEWAY_TOKEN — Gateway auth token (auto-generated if missing)
#   KYBERCLAW_GIT_REMOTE  — Git remote URL for workspace recovery

set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Constants
# ──────────────────────────────────────────────────────────────

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="setup-kyberclaw.sh"
readonly OPENCLAW_HOME="${HOME}/.openclaw"
readonly WORKSPACE="${OPENCLAW_HOME}/workspace"
readonly ENV_FILE="${OPENCLAW_HOME}/.env"
readonly MIN_NODE_VERSION=22
readonly MIN_DISK_GB=10
readonly MIN_RAM_MB=2048
readonly REQUIRED_CMDS=(node npm git curl)

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ──────────────────────────────────────────────────────────────
# Flags
# ──────────────────────────────────────────────────────────────

FORCE_WIPE=false
SKIP_ARSENAL=false
WORKSPACE_ONLY=false
DRY_RUN=false

# ──────────────────────────────────────────────────────────────
# Utility functions
# ──────────────────────────────────────────────────────────────

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_phase() { echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}  Phase $1: $2${NC}"; echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${NC}\n"; }

die() { log_error "$@"; exit 1; }

run() {
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
        return 0
    fi
    "$@"
}

confirm() {
    local prompt="$1"
    local response
    echo -en "${BOLD}${prompt}${NC} [y/N] "
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

# ──────────────────────────────────────────────────────────────
# Argument parsing
# ──────────────────────────────────────────────────────────────

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force-wipe)     FORCE_WIPE=true ;;
            --skip-arsenal)   SKIP_ARSENAL=true ;;
            --workspace-only) WORKSPACE_ONLY=true ;;
            --dry-run)        DRY_RUN=true ;;
            --help)
                head -30 "$0" | grep '^#' | sed 's/^# \?//'
                exit 0
                ;;
            *)
                die "Unknown option: $1. Use --help for usage."
                ;;
        esac
        shift
    done
}

# ──────────────────────────────────────────────────────────────
# Phase 0: Prerequisites + Pre-Wipe Protection
# ──────────────────────────────────────────────────────────────

phase_0_prerequisites() {
    log_phase 0 "Prerequisites + Pre-Wipe Protection"

    # ── Pre-wipe protection ──
    if [ -d "${WORKSPACE}/.git" ]; then
        local unpushed
        unpushed=$(cd "${WORKSPACE}" && git log --oneline origin/main..HEAD 2>/dev/null | wc -l)
        if [ "$unpushed" -gt 0 ]; then
            echo ""
            echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║  UNPUSHED COMMITS DETECTED — ZERO'S MEMORY AT RISK          ║${NC}"
            echo -e "${RED}║                                                              ║${NC}"
            echo -e "${RED}║  ${unpushed} commit(s) haven't been pushed to remote.            ║${NC}"
            echo -e "${RED}║  If you proceed, Zero will LOSE all learning since            ║${NC}"
            echo -e "${RED}║  last push: memory, principles, reflections.                  ║${NC}"
            echo -e "${RED}║                                                              ║${NC}"
            echo -e "${RED}║  Run 'cd ~/.openclaw/workspace && git push' first.            ║${NC}"
            echo -e "${RED}║  Or pass --force-wipe to override (DATA WILL BE LOST).        ║${NC}"
            echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            if ! $FORCE_WIPE; then
                die "Aborting: unpushed commits detected. Use --force-wipe to override."
            fi
            log_warn "Proceeding with --force-wipe. Unpushed commits WILL be lost."
        fi
    fi

    # ── Architecture detection ──
    local arch
    arch=$(uname -m)
    log_info "Architecture: ${arch}"
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        log_info "ARM64 detected — Pi5 / ARM environment"
    elif [[ "$arch" == "x86_64" ]]; then
        log_info "x86_64 detected — workstation / server environment"
    else
        log_warn "Unknown architecture: ${arch}. Some tools may not install correctly."
    fi

    # ── Required commands ──
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            die "Required command not found: ${cmd}. Install it and retry."
        fi
        log_ok "${cmd} found: $(command -v "$cmd")"
    done

    # ── Node.js version check ──
    local node_major
    node_major=$(node -v | sed 's/^v//' | cut -d. -f1)
    if [ "$node_major" -lt "$MIN_NODE_VERSION" ]; then
        die "Node.js ${MIN_NODE_VERSION}+ required. Found: $(node -v)"
    fi
    log_ok "Node.js $(node -v)"

    # ── npm version ──
    log_ok "npm $(npm -v)"

    # ── Git version ──
    log_ok "git $(git --version | awk '{print $3}')"

    # ── Disk space check ──
    local avail_gb
    avail_gb=$(df -BG / | awk 'NR==2{gsub("G",""); print $4}')
    if [ "$avail_gb" -lt "$MIN_DISK_GB" ]; then
        die "Insufficient disk space: ${avail_gb}GB available, ${MIN_DISK_GB}GB required."
    fi
    log_ok "Disk space: ${avail_gb}GB available"

    # ── RAM check ──
    local total_ram_mb
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_ram_mb" -lt "$MIN_RAM_MB" ]; then
        log_warn "Low RAM: ${total_ram_mb}MB (recommended: ${MIN_RAM_MB}MB+)"
    else
        log_ok "RAM: ${total_ram_mb}MB"
    fi

    # ── CPU temperature (ARM64/Pi only) ──
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        local temp_raw temp_c
        temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp)
        temp_c=$((temp_raw / 1000))
        if [ "$temp_c" -gt 80 ]; then
            log_warn "CPU temperature: ${temp_c}C (high — consider cooling before proceeding)"
        else
            log_ok "CPU temperature: ${temp_c}C"
        fi
    fi

    # ── OS detection ──
    if [ -f /etc/os-release ]; then
        local os_name
        os_name=$(. /etc/os-release && echo "$PRETTY_NAME")
        log_info "OS: ${os_name}"
    fi

    log_ok "Phase 0 complete — prerequisites satisfied"
}

# ──────────────────────────────────────────────────────────────
# Phase 1: Install OpenClaw
# ──────────────────────────────────────────────────────────────

phase_1_install_openclaw() {
    log_phase 1 "Install OpenClaw"

    # Check if already installed
    if command -v openclaw &>/dev/null; then
        local current_version
        current_version=$(openclaw --version 2>/dev/null || echo "unknown")
        log_info "OpenClaw already installed: ${current_version}"
        if confirm "Update to latest version?"; then
            run npm install -g openclaw@latest
        else
            log_info "Keeping existing OpenClaw installation"
            return 0
        fi
    else
        log_info "Installing OpenClaw globally..."
        run npm install -g openclaw@latest
    fi

    # Verify installation
    if command -v openclaw &>/dev/null; then
        log_ok "OpenClaw installed: $(openclaw --version 2>/dev/null || echo 'installed')"
    else
        die "OpenClaw installation failed. Check npm logs."
    fi

    log_ok "Phase 1 complete"
}

# ──────────────────────────────────────────────────────────────
# Phase 2: Onboard Agent
# ──────────────────────────────────────────────────────────────

phase_2_onboard() {
    log_phase 2 "Onboard Agent"

    # Create OpenClaw home if needed
    run mkdir -p "${OPENCLAW_HOME}"

    # Check for existing .env
    if [ -f "${ENV_FILE}" ]; then
        log_info "Existing .env found at ${ENV_FILE}"
        if ! confirm "Overwrite existing .env?"; then
            log_info "Keeping existing .env"
        else
            setup_env_file
        fi
    else
        setup_env_file
    fi

    # Run onboarding
    if [ -d "${OPENCLAW_HOME}/agents" ]; then
        log_info "Agent data already exists — skipping onboard"
    else
        log_info "Running OpenClaw onboarding..."
        run openclaw onboard
    fi

    log_ok "Phase 2 complete"
}

setup_env_file() {
    log_info "Setting up environment variables..."

    # Prompt for keys if not set
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        echo -en "${BOLD}Enter Anthropic API key (sk-ant-...): ${NC}"
        read -r ANTHROPIC_API_KEY
    fi

    if [ -z "${MINIMAX_API_KEY:-}" ]; then
        echo -en "${BOLD}Enter MiniMax API key: ${NC}"
        read -r MINIMAX_API_KEY
    fi

    if [ -z "${SYNTHETIC_API_KEY:-}" ]; then
        echo -en "${BOLD}Enter Synthetic API key: ${NC}"
        read -r SYNTHETIC_API_KEY
    fi

    if [ -z "${BRAVE_API_KEY:-}" ]; then
        echo -en "${BOLD}Enter Brave Search API key (BSA...): ${NC}"
        read -r BRAVE_API_KEY
    fi

    # Generate gateway token if not set
    if [ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
        OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p | tr -d '\n' | head -c 64)
        log_info "Generated gateway token"
    fi

    # Write .env file
    run bash -c "cat > '${ENV_FILE}' << 'ENVEOF'
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
MINIMAX_API_KEY=${MINIMAX_API_KEY}
SYNTHETIC_API_KEY=${SYNTHETIC_API_KEY}
BRAVE_API_KEY=${BRAVE_API_KEY}
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
ENVEOF"

    # Secure permissions
    run chmod 600 "${ENV_FILE}"
    log_ok ".env written and secured (chmod 600)"
}

# ──────────────────────────────────────────────────────────────
# Phase 3: Install Managed Skills
# ──────────────────────────────────────────────────────────────

phase_3_install_skills() {
    log_phase 3 "Install Managed Skills"

    local skills=(oracle github himalaya blogwatcher summarize)

    for skill in "${skills[@]}"; do
        log_info "Installing skill: ${skill}..."
        if run openclaw skills install "${skill}" 2>/dev/null; then
            log_ok "Installed: ${skill}"
        else
            log_warn "Failed to install ${skill} — may need manual installation"
        fi
    done

    log_ok "Phase 3 complete"
}

# ──────────────────────────────────────────────────────────────
# Phase 4: Configure Tools + Enable Hooks
# ──────────────────────────────────────────────────────────────

phase_4_configure() {
    log_phase 4 "Configure Tools + Enable Hooks"

    # Configure Brave API for oracle skill
    if [ -n "${BRAVE_API_KEY:-}" ]; then
        log_info "Configuring Brave Search API for oracle skill..."
        if run openclaw skills config oracle --set "BRAVE_API_KEY=${BRAVE_API_KEY}" 2>/dev/null; then
            log_ok "Brave API configured"
        else
            log_warn "Could not auto-configure Brave API — configure manually via 'openclaw skills config oracle'"
        fi
    fi

    # Enable coding tool profile
    log_info "Setting tool profile to 'coding' (bash, file operations)..."
    # Tool profile is set in openclaw.json (Phase 5 overlay handles this)

    # Enable hooks
    log_info "Hooks will be configured via openclaw.json in Phase 5"

    log_ok "Phase 4 complete"
}

# ──────────────────────────────────────────────────────────────
# Phase 5: Overlay Workspace
# ──────────────────────────────────────────────────────────────

phase_5_overlay_workspace() {
    log_phase 5 "Overlay Workspace"

    local git_remote="${KYBERCLAW_GIT_REMOTE:-}"

    # Try to recover from git remote
    if [ -n "$git_remote" ]; then
        log_info "Git remote provided: ${git_remote}"
        log_info "Attempting workspace recovery from remote..."

        if [ -d "${WORKSPACE}" ]; then
            log_warn "Existing workspace found — backing up to ${WORKSPACE}.bak.$(date +%s)"
            run mv "${WORKSPACE}" "${WORKSPACE}.bak.$(date +%s)"
        fi

        if run git clone "$git_remote" "${WORKSPACE}"; then
            log_ok "Workspace recovered from git remote"
            log_info "Zero's identity restored: SOUL.md, MEMORY.md, PRINCIPLES.md"

            # Restore ENGAGEMENT.md template (gitignored — won't be in clone)
            if [ ! -f "${WORKSPACE}/ENGAGEMENT.md" ]; then
                create_engagement_template
            fi

            # Recreate loot directories (gitignored)
            create_loot_directories

            log_ok "Workspace recovery complete"
            return 0
        else
            log_warn "Git clone failed — falling back to fresh workspace"
        fi
    fi

    # Fresh workspace — copy from the kyberclaw project directory
    log_info "Setting up fresh workspace..."

    local source_dir
    source_dir="$(cd "$(dirname "$0")" && pwd)"

    if [ ! -f "${source_dir}/SOUL.md" ]; then
        die "Cannot find KyberClaw source files in ${source_dir}. Run this script from the kyberclaw directory."
    fi

    # Create workspace if it doesn't exist
    run mkdir -p "${WORKSPACE}"

    # Copy all workspace files
    log_info "Copying KyberClaw files to workspace..."

    # Bootstrap files (root level)
    local bootstrap_files=(SOUL.md PRINCIPLES.md IDENTITY.md AGENTS.md TOOLS.md USER.md MEMORY.md ENGAGEMENT.md HEARTBEAT.md)
    for f in "${bootstrap_files[@]}"; do
        if [ -f "${source_dir}/${f}" ]; then
            run cp "${source_dir}/${f}" "${WORKSPACE}/${f}"
            log_ok "  ${f}"
        else
            log_warn "  ${f} not found in source — skipping"
        fi
    done

    # Configuration files
    if [ -f "${source_dir}/openclaw.json" ]; then
        run cp "${source_dir}/openclaw.json" "${WORKSPACE}/openclaw.json"
        log_ok "  openclaw.json"
    fi

    if [ -f "${source_dir}/.gitignore" ]; then
        run cp "${source_dir}/.gitignore" "${WORKSPACE}/.gitignore"
        log_ok "  .gitignore"
    fi

    # On-demand files
    run mkdir -p "${WORKSPACE}/on-demand"
    for f in BOOT.md GIT_CONFIG.md; do
        if [ -f "${source_dir}/on-demand/${f}" ]; then
            run cp "${source_dir}/on-demand/${f}" "${WORKSPACE}/on-demand/${f}"
            log_ok "  on-demand/${f}"
        fi
    done

    # Agent prompt files
    run mkdir -p "${WORKSPACE}/agents"
    for f in "${source_dir}"/agents/*.md; do
        if [ -f "$f" ]; then
            local basename
            basename=$(basename "$f")
            run cp "$f" "${WORKSPACE}/agents/${basename}"
            log_ok "  agents/${basename}"
        fi
    done

    # Skill files
    if [ -d "${source_dir}/skills" ]; then
        for skill_dir in "${source_dir}"/skills/*/; do
            if [ -d "$skill_dir" ]; then
                local skill_name
                skill_name=$(basename "$skill_dir")
                run mkdir -p "${WORKSPACE}/skills/${skill_name}"
                if [ -f "${skill_dir}/SKILL.md" ]; then
                    run cp "${skill_dir}/SKILL.md" "${WORKSPACE}/skills/${skill_name}/SKILL.md"
                    log_ok "  skills/${skill_name}/SKILL.md"
                fi
            fi
        done
    fi

    # Playbook files
    run mkdir -p "${WORKSPACE}/playbooks"
    for f in "${source_dir}"/playbooks/*.md; do
        if [ -f "$f" ]; then
            local basename
            basename=$(basename "$f")
            run cp "$f" "${WORKSPACE}/playbooks/${basename}"
            log_ok "  playbooks/${basename}"
        fi
    done

    # Memory subsystem seeds
    run mkdir -p "${WORKSPACE}/memory/reflections" "${WORKSPACE}/memory/drift-checks"
    for f in knowledge-base.md ttps-learned.md tool-notes.md deferred-proposals.md conviction-candidates.md; do
        if [ -f "${source_dir}/memory/${f}" ]; then
            run cp "${source_dir}/memory/${f}" "${WORKSPACE}/memory/${f}"
            log_ok "  memory/${f}"
        fi
    done
    if [ -f "${source_dir}/memory/drift-checks/threshold-changes.md" ]; then
        run cp "${source_dir}/memory/drift-checks/threshold-changes.md" "${WORKSPACE}/memory/drift-checks/threshold-changes.md"
        log_ok "  memory/drift-checks/threshold-changes.md"
    fi

    # Create loot directories
    create_loot_directories

    # Initialize git repository
    if [ ! -d "${WORKSPACE}/.git" ]; then
        log_info "Initializing git repository..."
        (
            cd "${WORKSPACE}"
            run git init
            run git config user.name "Zero"
            run git config user.email "zero@kyberclaw.local"

            # Initial commit
            run git add -A
            run git commit -m "init: KyberClaw workspace — Zero is born

Bootstrap files, agent prompts, skills, playbooks, and memory seeds.
Zero's identity begins here.

Co-Authored-By: Raw <raw@kyberclaw.local>"
        )
        log_ok "Git initialized with initial commit"

        # Add remote if provided
        if [ -n "$git_remote" ]; then
            (cd "${WORKSPACE}" && run git remote add origin "$git_remote")
            log_ok "Git remote added: ${git_remote}"
        fi
    fi

    log_ok "Phase 5 complete — workspace deployed"
}

create_engagement_template() {
    # ENGAGEMENT.md is gitignored, so create a fresh template on recovery
    if [ -f "$(cd "$(dirname "$0")" && pwd)/ENGAGEMENT.md" ]; then
        cp "$(cd "$(dirname "$0")" && pwd)/ENGAGEMENT.md" "${WORKSPACE}/ENGAGEMENT.md"
    fi
}

create_loot_directories() {
    local loot_dirs=(
        loot/phase1
        loot/phase2
        loot/phase3
        loot/phase4
        loot/phase5
        loot/ext-phase1
        loot/ext-phase2
        loot/ext-phase3
        loot/ext-phase4
        loot/credentials/hashes
        loot/credentials/tickets
        loot/credentials/relayed
        loot/bloodhound
        loot/screenshots
        loot/da-proof
        reports
        logs
    )

    for dir in "${loot_dirs[@]}"; do
        run mkdir -p "${WORKSPACE}/${dir}"
    done
    log_ok "Loot directories created"
}

# ──────────────────────────────────────────────────────────────
# Phase 6: Install Pentest Arsenal
# ──────────────────────────────────────────────────────────────

phase_6_install_arsenal() {
    log_phase 6 "Install Pentest Arsenal"

    if $SKIP_ARSENAL; then
        log_info "Skipping arsenal installation (--skip-arsenal)"
        return 0
    fi

    local arch
    arch=$(uname -m)

    # ── Check for root/sudo ──
    local SUDO=""
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo &>/dev/null; then
            SUDO="sudo"
            log_info "Using sudo for package installation"
        else
            log_warn "Not root and sudo not available — package installation may fail"
        fi
    fi

    # ── APT packages ──
    log_info "Installing APT packages..."

    local apt_packages=(
        # Network discovery
        nmap masscan dnsrecon tcpdump bettercap macchanger ncat netcat-traditional
        # SMB/Windows
        smbclient smbmap nfs-common
        # Credential capture
        sshpass
        # Web scanning
        ffuf
        # Email
        swaks sendemail
        # Infrastructure
        hostapd isc-dhcp-server stunnel4
        # External recon
        whois
        # External vuln scanning
        testssl.sh sslyze snmpwalk onesixtyone ipmitool
        # Exploitation
        hydra medusa crowbar
        # Build dependencies
        python3 python3-pip python3-venv golang-go libssl-dev libffi-dev
        python3-dev build-essential
    )

    if $DRY_RUN; then
        echo "[DRY-RUN] ${SUDO} apt-get update && ${SUDO} apt-get install -y ${apt_packages[*]}"
    else
        $SUDO apt-get update -qq
        # Install packages, skip any that fail (some may not exist in all repos)
        for pkg in "${apt_packages[@]}"; do
            if $SUDO apt-get install -y -qq "$pkg" 2>/dev/null; then
                log_ok "  ${pkg}"
            else
                log_warn "  ${pkg} — not available (may need manual install)"
            fi
        done
    fi

    # ── Python packages (pip3) ──
    log_info "Installing Python pentest tools..."

    local pip_packages=(
        impacket
        netexec
        bloodhound
        certipy-ad
        ldapdomaindump
        mitm6
        coercer
        patator
    )

    for pkg in "${pip_packages[@]}"; do
        if run pip3 install --break-system-packages "$pkg" 2>/dev/null || \
           run pip3 install "$pkg" 2>/dev/null; then
            log_ok "  ${pkg}"
        else
            log_warn "  ${pkg} — pip install failed (try manual install)"
        fi
    done

    # ── Responder (lgandx) ──
    log_info "Installing Responder (lgandx)..."
    local responder_dir="${HOME}/tools/Responder"
    if [ ! -d "$responder_dir" ]; then
        run mkdir -p "${HOME}/tools"
        if run git clone https://github.com/lgandx/Responder.git "$responder_dir"; then
            log_ok "Responder cloned to ${responder_dir}"
        else
            log_warn "Responder clone failed"
        fi
    else
        log_info "Responder already installed at ${responder_dir}"
    fi

    # ── Go tools ──
    log_info "Installing Go-based tools..."

    local go_tools=(
        "github.com/projectdiscovery/httpx/cmd/httpx@latest"
        "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
        "github.com/projectdiscovery/katana/cmd/katana@latest"
    )

    export GOPATH="${HOME}/go"
    export PATH="${GOPATH}/bin:${PATH}"

    for tool in "${go_tools[@]}"; do
        local tool_name
        tool_name=$(echo "$tool" | rev | cut -d'/' -f1 | rev | cut -d'@' -f1)
        if run go install "$tool" 2>/dev/null; then
            log_ok "  ${tool_name}"
        else
            log_warn "  ${tool_name} — go install failed (may need manual install)"
        fi
    done

    # ── Evil-WinRM (Ruby) ──
    log_info "Installing evil-winrm..."
    if command -v gem &>/dev/null; then
        if run gem install evil-winrm 2>/dev/null; then
            log_ok "evil-winrm installed"
        else
            log_warn "evil-winrm install failed — try: gem install evil-winrm"
        fi
    else
        log_warn "Ruby/gem not found — evil-winrm skipped"
    fi

    # ── Metasploit Framework ──
    log_info "Checking Metasploit Framework..."
    if command -v msfconsole &>/dev/null; then
        log_ok "Metasploit already installed"
    else
        log_warn "Metasploit not found — install manually: https://docs.metasploit.com/docs/using-metasploit/getting-started/nightly-installers.html"
    fi

    # ── SCCMHunter ──
    log_info "Installing SCCMHunter..."
    local sccmhunter_dir="${HOME}/tools/SCCMHunter"
    if [ ! -d "$sccmhunter_dir" ]; then
        run mkdir -p "${HOME}/tools"
        if run git clone https://github.com/garrettfoster13/sccmhunter.git "$sccmhunter_dir"; then
            (cd "$sccmhunter_dir" && run pip3 install --break-system-packages -r requirements.txt 2>/dev/null || \
             run pip3 install -r requirements.txt 2>/dev/null)
            log_ok "SCCMHunter installed"
        else
            log_warn "SCCMHunter clone failed"
        fi
    else
        log_info "SCCMHunter already installed"
    fi

    # ── Amass ──
    log_info "Installing amass..."
    if run go install github.com/owasp-amass/amass/v4/...@master 2>/dev/null; then
        log_ok "amass installed"
    else
        log_warn "amass install failed — try manual installation"
    fi

    # ── theHarvester ──
    log_info "Installing theHarvester..."
    if run pip3 install --break-system-packages theHarvester 2>/dev/null || \
       run pip3 install theHarvester 2>/dev/null; then
        log_ok "theHarvester installed"
    else
        log_warn "theHarvester install failed"
    fi

    # ── Nuclei template update ──
    log_info "Updating nuclei templates..."
    if command -v nuclei &>/dev/null; then
        run nuclei -update-templates 2>/dev/null || true
        log_ok "Nuclei templates updated"
    fi

    # ── ike-scan ──
    log_info "Installing ike-scan..."
    if $SUDO apt-get install -y -qq ike-scan 2>/dev/null; then
        log_ok "ike-scan installed"
    else
        log_warn "ike-scan not in apt — may need manual compilation"
    fi

    # ── Shodan CLI ──
    log_info "Installing Shodan CLI..."
    if run pip3 install --break-system-packages shodan 2>/dev/null || \
       run pip3 install shodan 2>/dev/null; then
        log_ok "Shodan CLI installed"
    else
        log_warn "Shodan CLI install failed"
    fi

    # ── BloodHound CE (standalone check) ──
    log_info "Checking BloodHound..."
    if command -v bloodhound-python &>/dev/null; then
        log_ok "bloodhound-python available"
    else
        log_warn "bloodhound-python not found in PATH — check pip install"
    fi

    # ── PATH setup ──
    log_info "Ensuring Go bin and local bin are in PATH..."
    local shell_rc="${HOME}/.bashrc"
    if [ -f "${HOME}/.zshrc" ]; then
        shell_rc="${HOME}/.zshrc"
    fi

    local path_line='export PATH="${HOME}/go/bin:${HOME}/.local/bin:${PATH}"'
    if ! grep -qF 'go/bin' "$shell_rc" 2>/dev/null; then
        echo "" >> "$shell_rc"
        echo "# KyberClaw tool paths" >> "$shell_rc"
        echo "$path_line" >> "$shell_rc"
        log_ok "PATH updated in ${shell_rc}"
    fi

    log_ok "Phase 6 complete — pentest arsenal installed"
}

# ──────────────────────────────────────────────────────────────
# Phase 7: Lockdown + Validation
# ──────────────────────────────────────────────────────────────

phase_7_lockdown() {
    log_phase 7 "Lockdown + Validation"

    # ── File permissions ──
    log_info "Setting file permissions..."

    # Workspace directory
    run chmod 700 "${OPENCLAW_HOME}"
    log_ok "  ~/.openclaw/ — 700"

    # .env file (secrets)
    if [ -f "${ENV_FILE}" ]; then
        run chmod 600 "${ENV_FILE}"
        log_ok "  .env — 600"
    fi

    # Workspace files (readable by owner only)
    run chmod 700 "${WORKSPACE}"
    log_ok "  workspace/ — 700"

    # SSH deploy key (if exists)
    if [ -f "${HOME}/.ssh/kyberclaw_deploy_key" ]; then
        run chmod 600 "${HOME}/.ssh/kyberclaw_deploy_key"
        log_ok "  SSH deploy key — 600"
    fi

    # ── Validation ──
    log_info "Running validation checks..."
    local errors=0

    # Check bootstrap files exist
    local bootstrap_files=(SOUL.md PRINCIPLES.md IDENTITY.md AGENTS.md TOOLS.md USER.md MEMORY.md ENGAGEMENT.md HEARTBEAT.md)
    for f in "${bootstrap_files[@]}"; do
        if [ -f "${WORKSPACE}/${f}" ]; then
            log_ok "  Bootstrap: ${f}"
        else
            log_error "  Bootstrap: ${f} MISSING"
            ((errors++))
        fi
    done

    # Check on-demand files
    for f in on-demand/BOOT.md on-demand/GIT_CONFIG.md; do
        if [ -f "${WORKSPACE}/${f}" ]; then
            log_ok "  On-demand: ${f}"
        else
            log_error "  On-demand: ${f} MISSING"
            ((errors++))
        fi
    done

    # Check agent prompts
    local agent_count
    agent_count=$(find "${WORKSPACE}/agents" -name "*.md" -type f 2>/dev/null | wc -l)
    if [ "$agent_count" -ge 10 ]; then
        log_ok "  Agent prompts: ${agent_count} files"
    else
        log_warn "  Agent prompts: ${agent_count} files (expected 10)"
    fi

    # Check skills
    local skill_count
    skill_count=$(find "${WORKSPACE}/skills" -name "SKILL.md" -type f 2>/dev/null | wc -l)
    if [ "$skill_count" -ge 10 ]; then
        log_ok "  Skills: ${skill_count} files"
    else
        log_warn "  Skills: ${skill_count} files (expected 10)"
    fi

    # Check playbooks
    local playbook_count
    playbook_count=$(find "${WORKSPACE}/playbooks" -name "*.md" -type f 2>/dev/null | wc -l)
    if [ "$playbook_count" -ge 3 ]; then
        log_ok "  Playbooks: ${playbook_count} files"
    else
        log_warn "  Playbooks: ${playbook_count} files (expected 3)"
    fi

    # Check memory seeds
    local memory_count
    memory_count=$(find "${WORKSPACE}/memory" -name "*.md" -type f 2>/dev/null | wc -l)
    if [ "$memory_count" -ge 6 ]; then
        log_ok "  Memory seeds: ${memory_count} files"
    else
        log_warn "  Memory seeds: ${memory_count} files (expected 6)"
    fi

    # Validate openclaw.json
    if [ -f "${WORKSPACE}/openclaw.json" ]; then
        if python3 -m json.tool "${WORKSPACE}/openclaw.json" >/dev/null 2>&1; then
            log_ok "  openclaw.json — valid JSON"
        else
            log_error "  openclaw.json — INVALID JSON"
            ((errors++))
        fi
    else
        log_error "  openclaw.json MISSING"
        ((errors++))
    fi

    # Check .gitignore
    if [ -f "${WORKSPACE}/.gitignore" ]; then
        log_ok "  .gitignore present"
    else
        log_warn "  .gitignore MISSING"
    fi

    # Bootstrap budget check
    log_info "Checking bootstrap budget..."
    local total_chars=0
    for f in "${bootstrap_files[@]}"; do
        if [ -f "${WORKSPACE}/${f}" ]; then
            local chars
            chars=$(wc -c < "${WORKSPACE}/${f}")
            total_chars=$((total_chars + chars))
        fi
    done
    if [ "$total_chars" -lt 60000 ]; then
        log_ok "  Bootstrap budget: ${total_chars} chars (limit: 60,000)"
    else
        log_warn "  Bootstrap budget: ${total_chars} chars EXCEEDS 60,000 limit"
    fi

    # Sub-agent prompt size check
    log_info "Checking sub-agent prompt sizes..."
    for f in "${WORKSPACE}"/agents/*.md; do
        if [ -f "$f" ]; then
            local basename chars
            basename=$(basename "$f")
            chars=$(wc -c < "$f")
            if [[ "$basename" == "zero.md" ]]; then
                log_ok "  ${basename}: ${chars} chars (orchestrator — no limit)"
            elif [ "$chars" -lt 4000 ]; then
                log_ok "  ${basename}: ${chars} chars (< 4,000)"
            else
                log_warn "  ${basename}: ${chars} chars (exceeds 4,000 recommended)"
            fi
        fi
    done

    # Run openclaw doctor if available
    if command -v openclaw &>/dev/null; then
        log_info "Running openclaw doctor..."
        if run openclaw doctor --fix 2>/dev/null; then
            log_ok "openclaw doctor passed"
        else
            log_warn "openclaw doctor reported issues — review output above"
        fi
    fi

    # ── Total file count ──
    local total_files
    total_files=$(find "${WORKSPACE}" -type f ! -path '*/.git/*' ! -name '.gitkeep' | wc -l)
    log_info "Total workspace files: ${total_files}"

    # ── Summary ──
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  Installation Summary${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${NC}"
    echo ""

    if [ "$errors" -eq 0 ]; then
        echo -e "${GREEN}${BOLD}  KyberClaw installation complete.${NC}"
        echo -e "${GREEN}  Zero is ready.${NC}"
    else
        echo -e "${YELLOW}${BOLD}  KyberClaw installed with ${errors} warning(s).${NC}"
        echo -e "${YELLOW}  Review warnings above before starting Zero.${NC}"
    fi

    echo ""
    echo -e "  Workspace:  ${WORKSPACE}"
    echo -e "  Config:     ${WORKSPACE}/openclaw.json"
    echo -e "  Env:        ${ENV_FILE}"
    echo -e "  Files:      ${total_files}"
    echo -e "  Bootstrap:  ${total_chars} / 60,000 chars"
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo -e "    1. Start the gateway:  ${CYAN}openclaw gateway --port 18789${NC}"
    echo -e "    2. Pair WhatsApp:      ${CYAN}openclaw channels login --channel whatsapp${NC}"
    echo -e "    3. Talk to Zero via TUI or WhatsApp"
    echo ""

    if [ -n "${KYBERCLAW_GIT_REMOTE:-}" ]; then
        echo -e "  ${BOLD}Git remote:${NC} ${KYBERCLAW_GIT_REMOTE}"
    else
        echo -e "  ${BOLD}Git:${NC} No remote configured."
        echo -e "    To add: ${CYAN}cd ${WORKSPACE} && git remote add origin <url>${NC}"
    fi

    echo ""
    echo -e "  ${BOLD}\"Not because I'm nothing, but because I'm the beginning.\"${NC}"
    echo ""

    log_ok "Phase 7 complete — lockdown and validation done"
}

# ──────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BOLD}${CYAN}  KyberClaw Installer v${SCRIPT_VERSION}${NC}"
    echo -e "${CYAN}  Autonomous AI Penetration Testing Agent${NC}"
    echo ""

    parse_args "$@"

    if $WORKSPACE_ONLY; then
        phase_5_overlay_workspace
        phase_7_lockdown
    else
        phase_0_prerequisites
        phase_1_install_openclaw
        phase_2_onboard
        phase_3_install_skills
        phase_4_configure
        phase_5_overlay_workspace
        if ! $SKIP_ARSENAL; then
            phase_6_install_arsenal
        fi
        phase_7_lockdown
    fi
}

main "$@"
