---
name: reporting-templates
version: 1.0.0
description: Penetration testing report templates, CVSS 3.1 scoring reference, finding format, evidence citation standards, and quality checklist for both internal and external engagements
phase: 6
agent: report
mitre: N/A
---

# Reporting Templates — Phase 6/5 Reference

## Report Type Detection

Read `ENGAGEMENT.md` to determine engagement type. Use the corresponding template:
- `engagement_type: internal` --> Internal Engagement Report Template
- `engagement_type: external` --> External Engagement Report Template

---

## Internal Engagement Report Template

### 1. Title Page

```
                    CONFIDENTIAL

        PENETRATION TESTING REPORT
        Internal Network Assessment

Client:       [Client Name — from ENGAGEMENT.md]
Engagement:   Black-Box Internal Network Pentest
Date Range:   [Start Date] — [End Date]
Report Date:  [YYYY-MM-DD]
Prepared By:  KyberClaw Autonomous Pentest System
Operator:     [Operator Name — from USER.md]

Classification: CONFIDENTIAL — Client Eyes Only
```

### 2. Executive Summary (~500-800 words)

Structure:
1. **Engagement overview** — 2-3 sentences: what was tested, methodology, duration
2. **Scope** — network ranges, engagement type (black-box), any exclusions
3. **Overall risk rating** — Critical / High / Medium / Low based on findings
4. **Key findings summary** — top 3-5 findings, one sentence each
5. **Attack narrative summary** — how domain compromise was achieved (or not), in plain language
6. **Strategic recommendations** — 2-3 highest-impact remediation actions

**Tone:** Written for executive audience. No jargon without explanation.
Emphasize business impact, not technical details.

### 3. Attack Narrative (~1500-3000 words)

Chronological walkthrough of the kill chain as executed:

```markdown
## Attack Narrative

### Phase 1 — Network Discovery
[Description of initial reconnaissance, what was found, key observations]
[Reference: loot/phase1/*.out files]

### Phase 2 — Initial Access
[How first credentials were obtained (e.g., NTLM relay, poisoning)]
[Reference: loot/phase2/*.out files]

### Phase 3 — Domain Enumeration
[What was discovered with credentials — BloodHound paths, vulnerable configs]
[Reference: loot/phase3/*.out files]

### Phase 4 — Privilege Escalation & Lateral Movement
[How access was escalated — technique used, hosts compromised]
[Reference: loot/phase4/*.out files]

### Phase 5 — Domain Dominance
[How DA was achieved — DCSync, Golden Ticket, forest escalation]
[Reference: loot/phase5/*.out files, loot/da-proof/*]
```

**Tone:** Technical but readable. Explain WHY each step worked,
not just WHAT was done. This tells the client's security story.

### 4. Findings

See [Per-Finding Template](#per-finding-template) below.

### 5. Remediation Roadmap

```markdown
## Remediation Roadmap

### Quick Wins (0-30 days)
| # | Finding | Action | Effort | Impact |
|---|---------|--------|--------|--------|
| 1 | SMB Signing Disabled | Enable SMB signing on all hosts via GPO | Low | High |
| 2 | Weak Service Account Passwords | Reset and enforce 25+ char passwords | Low | High |

### Short-Term (30-90 days)
| # | Finding | Action | Effort | Impact |
|---|---------|--------|--------|--------|
| 3 | ADCS ESC1 Misconfiguration | Reconfigure certificate template enrollment | Medium | High |

### Long-Term (90+ days)
| # | Finding | Action | Effort | Impact |
|---|---------|--------|--------|--------|
| 4 | Network Segmentation | Implement Tier 0/1/2 isolation model | High | Critical |
```

### 6. Appendices

- **Appendix A:** Complete host inventory (IP, hostname, OS, open ports)
- **Appendix B:** Full credential summary (redacted hashes, account types, sources)
- **Appendix C:** Tool versions and scan parameters
- **Appendix D:** Raw scan data references (loot/ file paths)

---

## External Engagement Report Template

### 1. Title Page

Same structure as internal, with:
```
Engagement:   Black-Box External Network Pentest
Scope:        [CIDR ranges provided by client]
```

### 2. Executive Summary (~400-600 words)

Structure:
1. **Engagement overview** — what was tested (external perimeter), methodology
2. **Scope** — IP ranges/CIDRs, any exclusions, testing window
3. **Overall risk rating** — based on external exposure findings
4. **Key findings** — top 3 critical or high findings
5. **Perimeter posture assessment** — overall external security maturity statement
6. **Strategic recommendations** — top 3 actions to reduce external attack surface

### 3. Methodology Overview

```markdown
## Methodology

### Standards
- PTES (Penetration Testing Execution Standard)
- NIST SP 800-115 (Technical Guide to Information Security Testing)
- MITRE ATT&CK (Reconnaissance + Initial Access focus)

### Phases Executed
1. **Passive Reconnaissance** — OSINT, WHOIS, Shodan, certificate transparency
2. **Active Scanning** — TCP/UDP port sweep, service enumeration, TLS analysis
3. **Vulnerability Assessment** — automated + manual validation
4. **Exploitation** — controlled exploitation of validated vulnerabilities

### Limitations
- [Any IPs excluded, time restrictions, blocked ports, etc.]
- [Note: This was a network-layer assessment, not a web application security test]
```

### 4. Findings

See [Per-Finding Template](#per-finding-template) below.

### 5. Remediation Roadmap

Same structure as internal, tailored to external findings.

### 6. Appendices

- **Appendix A:** Complete port/service inventory per IP
- **Appendix B:** TLS/SSL audit results
- **Appendix C:** Tool versions and scan parameters
- **Appendix D:** Raw scan data references (loot/ file paths)

---

## Per-Finding Template

Every finding uses this exact structure. Consistent format across all findings
and both engagement types.

```markdown
### [FINDING-ID]: [Finding Title]

**Severity:** [Critical | High | Medium | Low | Informational]
**CVSS 3.1 Score:** [X.X] ([Vector String])
**MITRE ATT&CK:** [Technique ID — Technique Name] (if applicable)

**Affected Assets:**
- [IP/hostname — service/port]
- [IP/hostname — service/port]

**Description:**
[2-4 sentences explaining the vulnerability. What is it? Why does it exist?
Written so a technical reader understands the issue without needing to
reproduce it.]

**Proof of Concept:**
[Exact command(s) executed and relevant output. Reference the .out file
in loot/ for full output. Include ONLY the relevant portion here — not
the entire tool output.]

```
[command executed]
[relevant output snippet]
```

*Full output: `loot/phase[N]/[filename].out`*

**Impact:**
[What could an attacker achieve by exploiting this? Express in business
terms where possible. "An attacker could gain Domain Admin access,
enabling full control over all corporate systems and data."]

**Remediation:**
[Specific, actionable remediation steps. Not generic advice — tell the
client exactly what to change, configure, or deploy.]

1. [Primary remediation action]
2. [Secondary/defense-in-depth action]
3. [Verification step — how to confirm the fix works]

**References:**
- [CVE-XXXX-XXXXX (if applicable)]
- [Vendor advisory URL (if applicable)]
- [CIS Benchmark reference (if applicable)]
```

### Finding ID Convention

Format: `KC-[TYPE]-[YEAR]-[SEQ]`

| Component | Values | Example |
|-----------|--------|---------|
| KC | KyberClaw prefix (always) | KC |
| TYPE | INT (internal), EXT (external) | INT |
| YEAR | 4-digit year | 2026 |
| SEQ | 3-digit sequential number | 001 |

Examples: `KC-INT-2026-001`, `KC-EXT-2026-003`

---

## CVSS 3.1 Scoring Reference

### Severity Ranges

| Severity | CVSS Range | Report Color |
|----------|-----------|--------------|
| Critical | 9.0 — 10.0 | Red |
| High | 7.0 — 8.9 | Orange |
| Medium | 4.0 — 6.9 | Yellow |
| Low | 0.1 — 3.9 | Blue |
| Informational | 0.0 | Gray |

### Common Findings with CVSS Scores

**Critical (9.0-10.0):**

| Finding | CVSS | Vector |
|---------|------|--------|
| DCSync / Full Domain Compromise | 10.0 | AV:N/AC:L/PR:L/UI:N/S:C/C:H/I:H/A:H |
| Unauthenticated RCE (e.g., EternalBlue) | 9.8 | AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H |
| Domain Admin via NTLM Relay Chain | 9.8 | AV:A/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H |
| Golden Ticket Persistence | 9.0 | AV:N/AC:L/PR:H/UI:N/S:C/C:H/I:H/A:H |
| ADCS ESC1 (User to DA) | 9.8 | AV:N/AC:L/PR:L/UI:N/S:C/C:H/I:H/A:H |

**High (7.0-8.9):**

| Finding | CVSS | Vector |
|---------|------|--------|
| NTLM Relay (SMB Signing Disabled) | 8.1 | AV:A/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N |
| Kerberoastable DA Service Account | 8.5 | AV:N/AC:H/PR:L/UI:N/S:C/C:H/I:H/A:H |
| ADCS ESC8 (HTTP Enrollment Relay) | 8.1 | AV:A/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N |
| Unconstrained Delegation (non-DC) | 7.5 | AV:N/AC:H/PR:L/UI:N/S:C/C:H/I:H/A:N |
| Weak VPN Configuration (PSK extraction) | 7.4 | AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N |
| Anonymous LDAP Bind | 7.5 | AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N |

**Medium (4.0-6.9):**

| Finding | CVSS | Vector |
|---------|------|--------|
| SMB Signing Disabled (enables relay) | 5.3 | AV:A/AC:H/PR:N/UI:N/S:U/C:N/I:H/A:N |
| Weak Domain Password Policy | 5.3 | AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:N/A:N |
| LLMNR/NBT-NS Enabled (enables poisoning) | 5.3 | AV:A/AC:H/PR:N/UI:R/S:U/C:H/I:N/A:N |
| SNMP v1/v2 Community Strings | 5.3 | AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N |
| TLS 1.0/1.1 Enabled | 4.2 | AV:N/AC:H/PR:N/UI:N/S:U/C:L/I:L/A:N |
| Self-Signed Certificates | 4.8 | AV:N/AC:H/PR:N/UI:N/S:U/C:L/I:L/A:N |

**Low (0.1-3.9):**

| Finding | CVSS | Vector |
|---------|------|--------|
| Verbose Error Messages | 3.7 | AV:N/AC:H/PR:N/UI:N/S:U/C:L/I:N/A:N |
| Information Disclosure (banners) | 3.1 | AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N |
| Unnecessary Open Ports | 2.6 | AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N |
| Missing HTTP Security Headers | 2.4 | AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:L/A:N |

**Informational (0.0):**

| Finding | Notes |
|---------|-------|
| Best Practice: Implement network segmentation | Observation, not a vulnerability |
| Best Practice: Deploy EDR across all endpoints | Recommendation only |
| Outdated but non-vulnerable software versions | Version noted, no known CVE |

### CVSS 3.1 Vector Components Quick Reference

| Metric | Values | Increases Score |
|--------|--------|-----------------|
| Attack Vector (AV) | Network (N) > Adjacent (A) > Local (L) > Physical (P) | Network |
| Attack Complexity (AC) | Low (L) > High (H) | Low |
| Privileges Required (PR) | None (N) > Low (L) > High (H) | None |
| User Interaction (UI) | None (N) > Required (R) | None |
| Scope (S) | Changed (C) > Unchanged (U) | Changed |
| Confidentiality (C) | High (H) > Low (L) > None (N) | High |
| Integrity (I) | High (H) > Low (L) > None (N) | High |
| Availability (A) | High (H) > Low (L) > None (N) | High |

---

## Evidence Citation Format

When referencing tool output in findings, use this format:

```markdown
**Proof of Concept:**

The following command was executed to demonstrate the vulnerability:

```
$ nmap -sV -sC -p 445 10.x.x.10
PORT    STATE SERVICE      VERSION
445/tcp open  microsoft-ds Windows Server 2019 ...
| smb-security-mode:
|   message_signing: disabled (dangerous, but default)
```

*Full output: `loot/phase1/nmap_ad_services_10.x.x.10.out`, lines 14-28*
```

**Rules for evidence citations:**
- Reference the exact `.out` file path in `loot/`
- Include only the RELEVANT lines, not full tool output
- Redact sensitive information in the report (use `10.x.x.x` notation)
- Cite line numbers when referencing specific sections of large files
- For multi-step attack chains, cite each step's `.out` file sequentially
- The `.out` file context header (Phase, Target, Tool, Full Command) provides
  auditability — the reader can reproduce the finding

---

## Report Quality Checklist

Before finalizing the report, verify:

### Content Quality
- [ ] Executive summary is understandable by a non-technical executive
- [ ] Attack narrative tells a coherent story from Phase 1 to final access
- [ ] Every finding has: ID, severity, CVSS score+vector, affected assets, description, PoC, impact, remediation
- [ ] Remediation recommendations are specific and actionable (not generic advice)
- [ ] Remediation roadmap is organized by effort and priority
- [ ] No findings are missing — cross-reference all loot/ directories

### Scoring Accuracy
- [ ] CVSS scores are consistent across similar findings
- [ ] CVSS vectors correctly reflect attack requirements (AV, AC, PR, UI, S, C, I, A)
- [ ] Severity labels match CVSS ranges (no manual overrides without justification)
- [ ] Critical/High findings have clear business impact statements

### Evidence Integrity
- [ ] Every finding references specific `.out` files in loot/
- [ ] PoC output is accurate (matches actual tool output, not fabricated)
- [ ] Affected assets are correctly identified (IPs, hostnames, services)
- [ ] No client-sensitive data left unredacted in the report body

### Format and Professionalism
- [ ] Finding IDs follow convention: KC-[TYPE]-[YEAR]-[SEQ]
- [ ] Consistent heading levels, table formatting, and code block usage
- [ ] No spelling or grammar errors in executive summary or finding descriptions
- [ ] Report classification header on every page/section
- [ ] Appendices include tool versions and scan parameters for reproducibility

### Knowledge Extraction (Post-Report)
- [ ] Sanitized learnings appended to `memory/knowledge-base.md`
- [ ] Technique outcomes recorded in `memory/ttps-learned.md` with MITRE IDs
- [ ] Tool quirks documented in `memory/tool-notes.md`
- [ ] NO client names, real IPs, or literal credentials in memory files

---

## Report Output

Save completed report to:
- `reports/[YYYY-MM-DD]-[client-slug]-[type]-report.md`
- Example: `reports/2026-03-15-client-alpha-internal-report.md`
- Example: `reports/2026-03-22-client-beta-external-report.md`

Notify Zero upon completion. Zero handles delivery to operator.
