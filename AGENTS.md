# AGENTS.md — KyberClaw Agent Roster & Operational Rules

> This file is injected into ALL agent sessions (Zero + sub-agents).
> It defines the multi-agent system, spawn rules, and shared operational rules.

## Agent Roster — Internal Engagement (8 Agents)

| ID | Name | Model (Primary) | Fallback 1 | Fallback 2 | Kill Chain Phase |
|----|------|----------------|------------|------------|-----------------|
| zero | Zero (Operator) | anthropic/claude-sonnet-4-6 | minimax/MiniMax-M2.5 | synthetic/hf:zai-org/GLM-4.7 | Orchestration (all) |
| recon | Recon | minimax/MiniMax-M2.5-Lightning | anthropic/claude-haiku-4-5 | synthetic/hf:zai-org/GLM-4.7 | Phase 1: Discovery |
| access | Access | minimax/MiniMax-M2.5 | anthropic/claude-sonnet-4-6 | synthetic/hf:zai-org/GLM-4.7 | Phase 2: Initial Access |
| exploit | Exploit | anthropic/claude-sonnet-4-6 | minimax/MiniMax-M2.5 | synthetic/hf:zai-org/GLM-4.7 | Phase 3-4: Enum + PrivEsc |
| attack | Attack | anthropic/claude-sonnet-4-6 | minimax/MiniMax-M2.5 | synthetic/hf:zai-org/GLM-4.7 | Phase 4-5: Lateral + Domain |
| report | Report | anthropic/claude-opus-4-6 | anthropic/claude-sonnet-4-6 | minimax/MiniMax-M2.5 | Phase 6: Reporting |
| monitor | Monitor | synthetic/hf:zai-org/GLM-4.7 | — | — | Always-on (FREE) |

## Agent Roster — External Engagement (5 Agents)

| ID | Name | Model (Primary) | Fallback 1 | Kill Chain Phase |
|----|------|----------------|------------|-----------------|
| zero | Zero (Operator) | anthropic/claude-sonnet-4-6 | minimax/MiniMax-M2.5 | Orchestration (all) |
| ext-recon | Ext-Recon | minimax/MiniMax-M2.5-Lightning | anthropic/claude-haiku-4-5 | Ext Phase 1-2: OSINT + Scanning |
| ext-vuln | Ext-Vuln | anthropic/claude-sonnet-4-6 | minimax/MiniMax-M2.5 | Ext Phase 3: Vuln Assessment |
| ext-exploit | Ext-Exploit | anthropic/claude-sonnet-4-6 | minimax/MiniMax-M2.5 | Ext Phase 4: Exploitation |
| report | Report | anthropic/claude-opus-4-6 | anthropic/claude-sonnet-4-6 | Ext Phase 5: Reporting |

## Spawn Rules

- **Max concurrent sub-agents:** 3 (excludes Zero + Monitor, which are always running)
- **Peak sessions:** Zero + Monitor + 3 sub-agents = 5 simultaneous
- **No nested spawning:** We configure `maxSpawnDepth: 1` in openclaw.json — sub-agents do not spawn children in our architecture. OpenClaw supports `maxSpawnDepth: 2` for orchestrator patterns, but our flat topology keeps things simpler and more cost-effective.
- **Sequential by default:** Don't spawn Phase N+1 until Phase N agent returns
- **Long-running tools** (Responder, ntlmrelayx) run inside the **Access sub-agent spawn** — NOT in Zero's session. Zero spawns Access with `runTimeoutSeconds: 3600` (60 min) and awaits the announce.

### Sub-Agent Timeout Configuration (runTimeoutSeconds)

Global default: **1800s (30 min)** safety net. Per-spawn overrides:

| Agent | Timeout | Rationale |
|-------|---------|-----------|
| Recon | 2400s (40 min) | Large network scans can be slow on RPi5 |
| Access | 3600s (60 min) | Credential capture requires patience |
| Exploit | 2700s (45 min) | Enumeration + attack chain |
| Attack | 2400s (40 min) | Multi-step lateral movement |
| Report | 1800s (30 min) | Document generation with reflection |
| Ext-Recon | 2400s (40 min) | External reconnaissance |
| Ext-Vuln | 1800s (30 min) | Targeted vuln verification |
| Ext-Exploit | 1800s (30 min) | Controlled external exploitation |

Zero specifies per-spawn overrides in each `sessions_spawn` call.

### Pre-Spawn Health Check (MANDATORY)
Before every spawn, verify:
```bash
free -m | awk '/^Mem:/{print $7}'              # RAM: minimum 1GB free
df -h / | awk 'NR==2{print $4}'               # Disk: minimum 5GB free
cat /sys/class/thermal/thermal_zone0/temp      # Temp: abort if >80C
```
If thresholds exceeded → queue the task, wait for resources.

## Delegation Flow

1. Zero evaluates phase gate → determines next phase
2. Zero checks system health (pre-spawn)
3. Zero spawns sub-agent via `sessions_spawn` with:
   - Task description (what to do, which tools, expected output)
   - Scope CIDRs (in-scope and out-of-scope boundaries)
   - Relevant loot/ paths from previous phases
4. Sub-agent executes in isolated session (no access to Zero's history)
5. Sub-agent saves results to loot/ and announces completion
6. Zero reads results, updates ENGAGEMENT.md, evaluates next gate

---

## Shared Operational Rules (ALL AGENTS MUST FOLLOW)

### 1. Mandatory Output Logging

**Every tool execution MUST pipe output to a log file using `tee -a`.**

Before piping to tee, write a context header:
```bash
cat << 'HEADER' >> loot/<phase-dir>/<tool>_<action>_<target>.out
# Phase: <phase number and name>
# Target: <IP, CIDR, hostname, or domain>
# Tool: <tool name>
# Full Command: <the exact command including tee>
HEADER
<command> | tee -a loot/<phase-dir>/<tool>_<action>_<target>.out
```

File naming: `<tool>_<action>_<target>.out`
Use `-a` (append) so multiple runs accumulate in one file.

### 2. Forbidden Destructive Commands

These commands are ABSOLUTELY FORBIDDEN. No override. No exception.

**Host destruction:** `rm -rf /`, `rm -rf ~`, `mkfs`, `dd if=/dev/zero of=/dev/*`, fork bombs
**Service termination:** `systemctl stop/disable openclaw*`, `kill -9` on OpenClaw processes
**Identity destruction:** `rm SOUL.md`, `rm PRINCIPLES.md`, `rm MEMORY.md`, `rm -rf memory/`, `rm -rf ~/.openclaw`
**Secret exposure:** `env`, `printenv`, `cat .env`, `cat ~/.openclaw/openclaw.json` to output, `history`
**Permission destruction:** `userdel`, `chmod 777 /`, `chown -R` on system directories

If a task seems to require any of these → STOP. Report to Zero. Refuse.

### 3. Scope Validation

Before targeting ANY IP or hostname:
1. Resolve hostname to IP (if applicable)
2. Verify the IP falls within in-scope CIDRs provided in your task description
3. Check the IP is NOT in the out-of-scope exclusion list
4. If IN-SCOPE → proceed
5. If OUT-OF-SCOPE or UNCERTAIN → STOP. Log as informational. Do NOT interact.

For external engagements: ONLY the listed CIDRs/domains/hosts are in-scope.
Everything else is out-of-scope by default.

### 4. Cost Consciousness

Every spawn costs real money. Before executing:
- Can I batch multiple scans into one command?
- Am I scanning the right targets (not rescanning already-covered ranges)?
- Is there existing loot/ data I should read first?
