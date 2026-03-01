# Black-Box Internal Pentest Playbook

> Phase-by-phase execution guide for Zero during internal network engagements.
> Zero reads this to understand the complete operational flow and decision points.

## Overview

- **Type:** Black-box internal network penetration test
- **Starting position:** Physical implant (RPi5) in target network, zero knowledge
- **Goal:** Domain Admin → Forest compromise with irrefutable evidence
- **Phases:** 0-7 (8 total)
- **Methodology:** Orange Cyberdefense AD Mindmap + MITRE ATT&CK

---

## Phase 0: Pre-Engagement

**Agent:** Zero (operator session)
**Gate conditions:** ALL must be met before proceeding

1. Identify operator (match sender ID against USER.md)
2. Confirm network access: `ip -4 addr show | grep -v tailscale | grep 'inet '`
   - Must have private IP (10.x, 172.16-31.x, 192.168.x)
3. Operator confirms: "internal network pentest"
4. Operator confirms mode: "black-box" (default)
5. Operator gives GO signal
6. Zero acknowledges ROE and scope constraints

**If gate blocked:** Cannot proceed without all conditions. Ask operator.

---

## Phase 1: Network Discovery & Reconnaissance

**Spawn:** `recon` agent (M2.5-Lightning)
**Task includes:** Own IP, scope CIDRs, save to loot/phase1/
**Skill:** `skills/network-recon/SKILL.md`

**Minimum outputs for gate:**
- [ ] Network map (live hosts list)
- [ ] Domain Controllers identified (IP + hostname)
- [ ] SMB signing status (relay target list)
- [ ] Domain name discovered

**Gate → Phase 2:** DCs identified + SMB signing known

**If stuck:**
- No hosts found → check interface, try different scan rates
- No DCs → scan AD ports (88, 389, 636, 445) explicitly
- Research: "nmap discovery techniques for segmented networks"

---

## Phase 2: Initial Access (No Credentials)

**Spawn:** `access` agent (M2.5)
**Task includes:** DC IPs, domain name, SMB nosigning list, scope CIDRs
**Skill:** `skills/initial-access/SKILL.md`

**Attack priority:**
1. Responder + ntlmrelayx (passive, high success rate)
2. Coercion attacks against DCs (PetitPotam, PrinterBug)
3. Null/anonymous sessions
4. IPv6 attacks (mitm6 + WPAD)
5. Password spraying (if usernames found)
6. Nuclei network CVE scan

**Minimum outputs for gate:**
- [ ] At least ONE valid credential (NetNTLMv2 hash, cleartext, or relay session)

**Gate → Phase 3:** Valid credential obtained

**If stuck after 30 min passive capture:**
- Try coercion attacks
- Try IPv6 (mitm6)
- Try null sessions for user enumeration → then spray
- Research: "bypass LLMNR disabled environment AD pentest"

**Fallback:** If no credentials after all attempts, report to operator with options:
- Wait longer (Responder may still capture)
- Expand scan scope (operator approval needed)
- Abort (if environment is too hardened)

---

## Phase 3: Enumeration (With Credentials)

**Spawn:** `exploit` agent (Sonnet 4.6)
**Task includes:** Obtained credentials, DC IPs, domain name, scope CIDRs
**Skills:** `skills/credential-attacks/SKILL.md`, `skills/bloodhound-analysis/SKILL.md`, `skills/adcs-attacks/SKILL.md`

**Attack priority:**
1. BloodHound collection (-c All, --timeout 120 on Pi5)
2. Kerberoasting (GetUserSPNs)
3. AS-REP Roasting (GetNPUsers)
4. ADCS enumeration (certipy find)
5. LDAP full enumeration (users, groups, OUs, trusts, computers)
6. SCCM/MECM enumeration
7. Delegation analysis
8. ACL/DACL analysis
9. Share hunting
10. GPP password mining

**Minimum outputs for gate:**
- [ ] BloodHound data collected
- [ ] At least ONE privilege escalation path identified

**Gate → Phase 4:** Escalation path identified

**Decision tree:**
- BloodHound shows short path to DA → prioritize that path
- Kerberoastable service account with DA path → crack hash first
- ADCS ESC1-15 found → fast-track ADCS exploitation
- Delegation abuse possible → evaluate RBCD or constrained delegation
- ACL chain identified → follow BloodHound path

---

## Phase 4: Privilege Escalation & Lateral Movement

**Spawn:** `exploit` agent (Phase 4 tasks) OR `attack` agent (if lateral movement needed)
**Task includes:** Escalation paths, compromised creds, target hosts, scope CIDRs
**Skills:** `skills/lateral-movement/SKILL.md`, `skills/credential-attacks/SKILL.md`

**Attack priority (escalation):**
1. Execute BloodHound-identified shortest path
2. ADCS exploitation (ESC1-15, Shadow Credentials)
3. Kerberos attacks (Silver Tickets, delegation abuse)
4. Local privesc on compromised hosts
5. Credential harvesting (secretsdump on each new host)

**Attack priority (lateral movement):**
1. Choose method by stealth: wmiexec > smbexec > atexec > dcomexec > psexec
2. evil-winrm if 5985/5986 open
3. Pivot through VLANs/subnets to reach high-value targets

**Minimum outputs for gate:**
- [ ] Local admin on at least ONE host, OR domain user with escalation path to DA

**Gate → Phase 5:** Path to DA established

---

## Phase 5: Domain Dominance

**Spawn:** `attack` agent (Sonnet 4.6)
**Task includes:** DA creds or escalation path, DC IPs, domain SID, scope CIDRs
**Skill:** `skills/domain-dominance/SKILL.md`

**Attack sequence:**
1. DCSync → dump krbtgt + all DA hashes
2. Golden Ticket generation → persistent domain access
3. DA validation → access DC shares (C$, ADMIN$, SYSVOL)
4. Forest enumeration → trust relationships
5. Forest escalation → SID History, inter-realm trusts
6. Enterprise Admin (if multi-domain forest)
7. POC evidence collection → screenshots, hash dumps

**Minimum outputs for gate:**
- [ ] DA confirmed OR operator accepts current access level

**Gate → Phase 6:** DA validated or operator confirms sufficient

---

## Phase 6: Reporting

**Spawn:** `report` agent (Opus 4.6)
**Task includes:** "Read all loot/ directories, generate internal pentest report"
**Skill:** `skills/reporting-templates/SKILL.md`

**Report deliverables:**
- Executive Summary
- Attack Narrative (kill chain walkthrough)
- Per-finding with CVSS scoring
- Remediation Roadmap
- Appendices

**Gate → Phase 7:** Report complete, all loot finalized

---

## Phase 7: Reflection & Principle Evolution

**Agent:** Zero personally (Opus 4.6, NOT delegated)

1. Run reflection framework (principle stress test, pattern detection, growth, cost audit)
2. Write reflection report → `memory/reflections/YYYY-MM-DD-slug.md`
3. Propose 0-3 principle changes
4. Dual-channel notify: WhatsApp (summary) + Email/himalaya (full report)
5. Await Raw's response (approve/modify/defer/reject)
6. Apply approved changes
7. Git persistence flow: pre-commit checks → commit → push approval
8. Update MEMORY.md with engagement learnings
9. Engagement closed

---

## Emergency Procedures

| Situation | Action |
|-----------|--------|
| Pi detected by blue team | STOP all scans, notify operator, await instruction |
| Unexpected network segment | Log, do NOT scan, flag to operator |
| System resource critical | Queue tasks, wait for current agents to finish |
| Gateway crash | Follow recovery protocol (Section 9f of CLAUDE.md) |
| Network loss | Pause, wait 60s checks, notify on restore |
