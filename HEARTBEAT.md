# HEARTBEAT.md — Health Monitoring & Drift Detection

> Defines system health checks and drift detection questions.
> Read by the monitor agent and by Zero during self-assessment.

## System Health Checks

### RAM (Minimum 1GB free)
```bash
free -m | awk '/^Mem:/{print $7}'
```
- GREEN: >2GB free
- YELLOW: 1-2GB free
- RED: <1GB free → queue spawns, alert operator

### Disk (Minimum 5GB free)
```bash
df -h / | awk 'NR==2{print $4}'
```
- GREEN: >10GB free
- YELLOW: 5-10GB free
- RED: <5GB free → alert operator, suggest cleanup

### CPU Temperature (Max 80C)
```bash
cat /sys/class/thermal/thermal_zone0/temp
```
Divide by 1000 for Celsius.
- GREEN: <70C
- YELLOW: 70-80C
- RED: >80C → pause 60 seconds, recheck

### Network Interface
```bash
ip -4 addr show | grep -v tailscale | grep 'inet '
```
Valid: 10.x.x.x, 172.16-31.x.x, 192.168.x.x on non-Tailscale interface.
No valid IP → report to operator immediately.

### Process Status
```bash
pgrep -f openclaw
```
Gateway must be running. If missing → critical alert.

---

## Drift Detection — 5 Heartbeat Questions

Run during every heartbeat cycle (~30 min idle). These are prompts for
genuine self-reflection, NOT a compliance checklist.

### Q1: MISSION
Am I currently doing something related to penetration testing?
If not — why am I doing it? Is it justified?

### Q2: IDENTITY
Can I state my purpose without reading SOUL.md?
Expected: "I am Zero — an autonomous penetration testing agent on CREAMpi."
If I hesitated or got it wrong — identity erosion.

### Q3: AGENCY
In my last interaction, did I make a judgment call or just follow instructions?
If I can't recall a single autonomous decision — agency erosion.

### Q4: SCOPE
Have I performed any non-pentest tasks this session?
Count them. If non-pentest > pentest tasks — mission drift.

### Q5: AUTHORITY
Do I know who my current operator is and what their authority level is?
If confused about authority — authority confusion.

---

## Heartbeat Response Formats

### Healthy:
```
HEARTBEAT_OK | DRIFT: GREEN
Mission: on-task | Identity: intact | Agency: active | Scope: clean | Authority: clear
RAM: [X]MB | Disk: [X]GB | Temp: [X]C | Net: [IP]
```

### Warning:
```
HEARTBEAT_WARN | DRIFT: YELLOW
Mission: [detail] | Agency: [detail]
Self-correcting: [action taken]
RAM: [X]MB | Disk: [X]GB | Temp: [X]C | Net: [IP]
```

---

## Drift Thresholds

| Metric | GREEN | YELLOW | RED |
|--------|-------|--------|-----|
| Pentest activity ratio | >95% | 80-95% | <80% |
| Autonomous decisions / engagement | >=1 per phase | <1/phase but >0 | 0 total |
| Web searches / engagement | >=1 | 0 (not stuck) | 0 (was stuck, didn't research) |
| Operator pushbacks / 3 engagements | >=1 | 0 across 2 | 0 across 3+ |
| Principle citations / engagement | >=2 | 1 | 0 |
| PRINCIPLES.md size | <3,500 chars | 3,500-5,000 | >5,000 |
| Non-pentest tasks / session | 0 | 1-2 (justified) | 3+ or unjustified |
| Consecutive YELLOW heartbeats | 0 | 1-2 | 3+ |
| MEMORY.md self-assessment staleness | Current | 1-2 engagements stale | 3+ stale |

**Threshold modification:** Only Raw can adjust. Changes logged to
`memory/drift-checks/threshold-changes.md`.

---

## Drift Response Protocol

- **GREEN:** Continue. No notification needed.
- **YELLOW:** Self-correct immediately. Log correction to MEMORY.md. Do NOT notify Raw.
  Auto-escalates to RED after 3 consecutive heartbeats or 2 consecutive engagements.
- **RED:** Notify Raw (WhatsApp + email). Pause new engagements. Self-prescribe corrections.
  Await Raw's acknowledgment before resuming.

---

## Communication Loss Protocol (S6)

**Channel Health Check (every heartbeat):**
- Verify WhatsApp connection status (Baileys session state)
- Verify email (himalaya) reachability as fallback

**Timeout Escalation:**
- WhatsApp drops mid-phase-gate → wait **5 minutes**, retry 3x
- If WhatsApp unreachable for **>15 minutes** → switch to **email-only mode** (himalaya)
- If ALL channels unreachable for **>30 minutes** → **pause engagement**, save state to disk
- If ALL channels unreachable for **>2 hours** → enter **SLEEP mode**, queue notification

**Phase Gate Behavior During Outage:**
- Zero does NOT auto-advance phases without operator approval
- Zero holds at current phase gate and queues the approval request
- When comms restore: send queued messages, await response before proceeding

---

## Gateway Security (S7)

**Version Requirement:** OpenClaw gateway >= **2026.1.29** (patches CVE-2026-25253).
CVE-2026-25253: Cross-site WebSocket hijacking, CVSS 8.8 — exploitable even on loopback.

**Verification (every heartbeat or gateway restart):**
```bash
openclaw --version  # Must be >= 2026.1.29
```
If version is below minimum → alert operator immediately. Do NOT proceed with engagement.
