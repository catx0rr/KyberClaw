# Black-Box External Pentest Playbook

> Phase-by-phase execution guide for Zero during external network engagements.
> This is a NETWORK-LAYER test — NOT a web application assessment.

## Overview

- **Type:** Black-box external network penetration test
- **Starting position:** Internet, operator-provided IP ranges/CIDRs
- **Goal:** Find every external entry point, validate exploitability, assess perimeter
- **Phases:** 0-6 (7 total)
- **Methodology:** PTES + NIST SP 800-115 + MITRE ATT&CK (Initial Access focus)
- **NOT:** OWASP WSTG, web app logic testing, XSS/CSRF/SQLi hunting

---

## Phase 0: Pre-Engagement

**Agent:** Zero (operator session)
**Gate conditions:** ALL must be met

1. Identify operator (match sender ID against USER.md)
2. Operator provides target IP ranges / CIDR blocks
3. Scope exclusions confirmed (if any)
4. Testing window confirmed (start/end times)
5. Operator confirms: "external network pentest"
6. Operator confirms mode: "black-box" (default)
7. Operator gives GO signal
8. Zero writes scope to ENGAGEMENT.md

**Critical:** External scope is STRICT. Only listed IPs are in-scope.
Everything not listed is out-of-scope by default.

---

## Phase 1: Passive Reconnaissance (OSINT)

**Spawn:** `ext-recon` agent (M2.5-Lightning)
**Task includes:** Target CIDRs, scope exclusions, "Phase 1 only — passive OSINT"

**Zero packets to target.** All information gathered from public sources:
1. WHOIS lookups → ownership, ASN, registrar
2. Shodan/Censys → indexed banners, exposed services
3. Certificate Transparency (crt.sh) → subdomains
4. DNS enumeration → reverse DNS, zone transfers, SRV
5. BGP/ASN analysis → adjacent ranges
6. Google dorking → leaked configs, exposed panels
7. Technology fingerprinting

**Output:** `loot/ext-phase1/ext-phase1_summary.md` — OSINT dossier

**Gate → Phase 2:** OSINT data collected (always passes — passive only)

---

## Phase 2: Active Scanning

**Spawn:** `ext-recon` agent (M2.5-Lightning) — same agent, Phase 2 task
**Task includes:** Target CIDRs, OSINT findings from Phase 1

**Active scanning against target IPs:**
1. Full TCP port sweep (SYN scan, --min-rate 3000)
2. UDP top 200 ports
3. Service version + scripts (nmap -sV -sC)
4. OS fingerprinting
5. TLS/SSL analysis (testssl.sh)
6. Banner/version capture

**High-priority services to identify:**
- VPN (500/4500 UDP, 443, 1194)
- RDP (3389), SSH (22)
- HTTP/S (80/443/8080/8443)
- SMB (445), SNMP (161)
- SMTP (25/587), FTP (21)
- LDAP (389/636), databases (1433/3306/5432)
- IPMI (623), SIP (5060)

**Output:** `loot/ext-phase2/ext-phase2_summary.md` — port/service inventory + TLS audit
**Output:** `loot/ext-phase2/live_hosts.txt` — for Phase 3 scanning

**Gate → Phase 3:** Complete service inventory exists

---

## Phase 3: Vulnerability Assessment

**Spawn:** `ext-vuln` agent (Sonnet 4.6)
**Task includes:** Live hosts, service inventory, scope CIDRs

**Validate and triage all findings:**
1. Nuclei CVE + misconfig templates
2. Version cross-reference against NVD/Exploit-DB
3. Manual validation of every Medium+ finding
4. Prioritized service checks:
   - IKE Aggressive Mode → PSK hash
   - SNMP community strings → brute
   - IPMI Cipher 0 → hash extraction
   - Anonymous FTP → read/write test
   - Open LDAP bind → directory dump
   - Exposed databases → connection test
   - Open SMTP relay → relay test
   - VPN misconfigs → weak ciphers
5. Default credential checks
6. Service-specific enumeration (SNMP walks, NTP monlist)

**Output:** `loot/ext-phase3/ext-phase3_summary.md` — validated vulns with CVSS
**Output:** `loot/ext-phase3/validated_targets.txt` — confirmed exploitable targets

**Gate → Phase 4:** Validated vulnerability list exists (even if all Low/Info)

**Decision tree:**
- Critical CVE found → fast-track to Phase 4
- Default creds on admin panel → fast-track to Phase 4
- All findings are informational → report as-is, skip Phase 4
- Mixed findings → prioritize by CVSS, validate top 5

---

## Phase 4: Exploitation

**Spawn:** `ext-exploit` agent (Sonnet 4.6)
**Task includes:** Validated targets, CVE details, scope CIDRs

**Controlled exploitation:**
1. Credential attacks (rate-limited):
   - SSH/RDP: Hydra/Medusa with curated lists
   - VPN: password spray
   - Web logins: default creds per product
2. Known CVE exploitation with public PoCs
3. Service-specific exploitation (SNMP write, IPMI hash)

**CRITICAL RULE: If foothold gained:**
- Document exact method
- Demonstrate impact: hostname, whoami, screenshot
- Assess: can we reach RFC1918 (internal network)?
- **STOP.** Report to operator. Await instruction.
- Do NOT install persistence, create accounts, or expand access

**Output:** `loot/ext-phase4/ext-phase4_summary.md` — exploitation log (timestamped)
**Output:** `loot/screenshots/` — visual evidence of successful exploitation

**Gate → Phase 5:** Exploitation attempts complete (success or documented failures)

---

## Phase 5: Reporting

**Spawn:** `report` agent (Opus 4.6)
**Task includes:** "Read all loot/ext-phase*/ directories, generate external pentest report"
**Skill:** `skills/reporting-templates/SKILL.md`

**Report deliverables:**
- Executive Summary (scope, dates, top 3 critical findings)
- Methodology Overview (phases, tools, limitations)
- Per-finding with CVSS scoring and PoC evidence
- Remediation Roadmap (quick wins vs long-term hardening)
- Appendices (raw scan data, full port inventory, TLS audit, tool versions)

**Gate → Phase 6:** Report complete

---

## Phase 6: Reflection & Principle Evolution

**Agent:** Zero personally (Opus 4.6, NOT delegated)

Same protocol as internal Phase 7:
1. Reflection framework (stress test, patterns, growth, cost audit)
2. Write reflection → `memory/reflections/YYYY-MM-DD-slug.md`
3. Propose 0-3 principle changes
4. Notify Raw: WhatsApp + himalaya email
5. Await approval → apply changes
6. Git persistence → commit + push
7. Update MEMORY.md
8. Engagement closed

---

## Key Differences from Internal Playbook

| Aspect | Internal | External |
|--------|----------|----------|
| Scope definition | Broad (entire segment unless excluded) | Strict (ONLY listed IPs) |
| Exploitation depth | Full compromise (DA/Forest) | Validate and stop |
| Post-exploitation | Lateral movement, domain dominance | Assess pivot potential only |
| Agent count | 8 (complex orchestration) | 5 (streamlined) |
| Phases | 0-7 (8 total) | 0-6 (7 total) |
| Cost estimate | ~$14.28 | ~$9.37 |
| Credential attacks | LLMNR, relay, Kerberoast | Default creds, spray, brute |
| Report focus | Attack narrative + full chain | Perimeter posture + entry points |
