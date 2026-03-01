---
name: external-vuln-assessment
version: 1.0.0
description: >
  Vulnerability assessment reference for Phase 3 of black-box external
  penetration testing. Covers automated scanning, manual validation,
  CVE cross-referencing, default credential checks, and vulnerability
  prioritization. Focus on eliminating false positives and building
  a validated, exploitable vulnerability list for Phase 4.
phases: [3]
agents: [ext-vuln]
sources:
  - https://csrc.nist.gov/pubs/sp/800/115/final
  - https://attack.mitre.org/tactics/TA0001/
  - https://github.com/projectdiscovery/nuclei-templates
  - https://www.exploit-db.com/
  - https://nvd.nist.gov/
---

# External Vulnerability Assessment — Phase 3 Reference

> **Phase 3 goal:** Validate every Medium+ vulnerability. Eliminate false
> positives. Build a prioritized, exploitable target list for Phase 4.
>
> **Constraint:** Validation only — no exploitation yet. Controlled probes
> to confirm vulnerability existence without triggering impact.
> All targets MUST be in-scope.

---

## STEP 1: AUTOMATED VULNERABILITY SCANNING

### 1.1 Nuclei — CVE & Misconfiguration Templates

```bash
# Update templates first
nuclei -update-templates

# CVE + misconfiguration scan on all live hosts
nuclei -l loot/ext-phase2/live_hosts.txt \
  -t cves/ -t misconfigurations/ -t default-logins/ \
  -severity critical,high,medium \
  -c 25 -rate-limit 100 \
  | tee -a loot/ext-phase3/nuclei_cve_scan.out

# Technology-specific templates (if tech stack known from Phase 2)
nuclei -l loot/ext-phase2/live_hosts.txt \
  -t technologies/ -t exposures/ \
  -severity critical,high \
  | tee -a loot/ext-phase3/nuclei_tech_scan.out

# SSL/TLS vulnerability templates
nuclei -l loot/ext-phase2/live_hosts.txt \
  -t ssl/ \
  | tee -a loot/ext-phase3/nuclei_ssl_scan.out
```

### 1.2 Nmap Vulnerability Scripts

```bash
# NSE vuln scripts on high-value targets
nmap --script vuln -p $OPEN_PORTS -iL loot/ext-phase2/live_hosts.txt \
  | tee -a loot/ext-phase3/nmap_vuln_scan.out

# Specific CVE checks (based on service versions from Phase 2)
nmap --script smb-vuln-* -p 445 -iL loot/ext-phase2/live_hosts.txt \
  | tee -a loot/ext-phase3/nmap_smb_vuln.out

# SSL/TLS vulnerability check
nmap --script ssl-heartbleed,ssl-poodle,ssl-ccs-injection \
  -p 443,8443 -iL loot/ext-phase2/live_hosts.txt \
  | tee -a loot/ext-phase3/nmap_ssl_vuln.out
```

---

## STEP 2: VERSION-BASED CVE CROSS-REFERENCE

For every service version identified in Phase 2:

```bash
# Search Exploit-DB for known exploits
searchsploit "$SERVICE_NAME $VERSION" \
  | tee -a loot/ext-phase3/searchsploit_$SERVICE_SAFE.out

# Check NVD for CVEs (manual or via API)
# Prioritize: CVSS >= 7.0, remote exploitable, public PoC available
```

**Version cross-reference checklist:**

| Service | Check For |
|---------|-----------|
| Apache / Nginx / IIS | Known RCE CVEs, directory traversal, header injection |
| OpenSSH | Auth bypass, key negotiation vulns |
| Microsoft RDP | BlueKeep (CVE-2019-0708), DejaBlue |
| Exchange / OWA | ProxyLogon, ProxyShell, ProxyNotShell |
| VPN (Fortinet/Pulse/Cisco) | Pre-auth RCE, credential leaks, config download |
| Citrix ADC/Gateway | Path traversal, RCE chains |
| VMware (vCenter/ESXi) | Log4Shell, SSRF, auth bypass |
| Database (MSSQL/MySQL/Postgres) | Default creds, remote code execution |
| IPMI | Cipher 0 bypass, hash disclosure |

---

## STEP 3: SERVICE-SPECIFIC VULNERABILITY CHECKS

### 3.1 Web Services

```bash
# Directory brute-force (common admin/config paths)
ffuf -u "https://$TARGET_IP/FUZZ" \
  -w /usr/share/wordlists/dirb/common.txt \
  -mc 200,301,302,403 \
  | tee -a loot/ext-phase3/ffuf_dirs_$TARGET_IP_SAFE.out

# Technology detection
whatweb https://$TARGET_IP \
  | tee -a loot/ext-phase3/whatweb_$TARGET_IP_SAFE.out

# Screenshot for evidence
gowitness single https://$TARGET_IP \
  --screenshot-path loot/screenshots/
```

### 3.2 VPN Services

```bash
# IKE aggressive mode (PSK hash extraction)
ike-scan -M --aggressive --id GroupVPN $TARGET_IP \
  | tee -a loot/ext-phase3/ike_aggressive_$TARGET_IP_SAFE.out

# VPN vendor-specific checks
# Fortinet: CVE-2018-13379, CVE-2023-27997
# Pulse Secure: CVE-2019-11510
# Cisco ASA: CVE-2020-3452
# Check via nuclei vendor-specific templates
nuclei -u $TARGET_IP -t cves/2023/ -t cves/2024/ -t cves/2025/ \
  | tee -a loot/ext-phase3/nuclei_vpn_cves_$TARGET_IP_SAFE.out
```

### 3.3 SNMP

```bash
# Community string brute-force
onesixtyone -c /usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt $TARGET_IP \
  | tee -a loot/ext-phase3/snmp_brute_$TARGET_IP_SAFE.out

# If community string found — full SNMP walk
snmpwalk -v 2c -c $COMMUNITY $TARGET_IP 1.3.6.1 \
  | tee -a loot/ext-phase3/snmpwalk_full_$TARGET_IP_SAFE.out

# Extract useful info from SNMP walk
# - System description: .1.3.6.1.2.1.1.1.0
# - Interfaces: .1.3.6.1.2.1.2.2.1
# - ARP table: .1.3.6.1.2.1.4.22
# - Running processes: .1.3.6.1.2.1.25.4.2.1.2
# - Installed software: .1.3.6.1.2.1.25.6.3.1.2
```

### 3.4 IPMI

```bash
# Cipher 0 check (null authentication bypass)
ipmitool -I lanplus -H $TARGET_IP -U "" -P "" -C 0 chassis status \
  | tee -a loot/ext-phase3/ipmi_cipher0_$TARGET_IP_SAFE.out

# IPMI hash extraction (RAKP)
nmap --script ipmi-brute -p 623 $TARGET_IP \
  | tee -a loot/ext-phase3/ipmi_hash_$TARGET_IP_SAFE.out
```

### 3.5 Email Services

```bash
# SMTP open relay test
nmap --script smtp-open-relay -p 25,587 $TARGET_IP \
  | tee -a loot/ext-phase3/smtp_relay_$TARGET_IP_SAFE.out

# SMTP user enumeration (VRFY/EXPN/RCPT)
nmap --script smtp-enum-users -p 25 $TARGET_IP \
  | tee -a loot/ext-phase3/smtp_users_$TARGET_IP_SAFE.out
```

### 3.6 Database Services

```bash
# MSSQL default credentials
nmap --script ms-sql-brute -p 1433 $TARGET_IP \
  | tee -a loot/ext-phase3/mssql_brute_$TARGET_IP_SAFE.out

# MySQL default credentials
nmap --script mysql-brute -p 3306 $TARGET_IP \
  | tee -a loot/ext-phase3/mysql_brute_$TARGET_IP_SAFE.out

# PostgreSQL default credentials
nmap --script pgsql-brute -p 5432 $TARGET_IP \
  | tee -a loot/ext-phase3/pgsql_brute_$TARGET_IP_SAFE.out
```

---

## STEP 4: DEFAULT CREDENTIAL CHECKS

```bash
# netexec for Windows services
netexec smb $TARGET_IP -u "administrator" -p "administrator" \
  | tee -a loot/ext-phase3/default_creds_smb_$TARGET_IP_SAFE.out

netexec ssh $TARGET_IP -u "root" -p "root" \
  | tee -a loot/ext-phase3/default_creds_ssh_$TARGET_IP_SAFE.out

# Nuclei default login templates
nuclei -u $TARGET_URL -t default-logins/ \
  | tee -a loot/ext-phase3/nuclei_default_logins_$TARGET_IP_SAFE.out
```

**Common default credentials to test:**

| Service | Username | Password |
|---------|----------|----------|
| SSH | root, admin | root, admin, password, toor |
| Web admin panels | admin | admin, password, 1234 |
| SNMP | — | public, private |
| IPMI | ADMIN, admin | ADMIN, admin, password |
| Database | sa, root, postgres | sa, root, postgres, (blank) |
| VPN | admin | admin, password |

---

## STEP 5: MANUAL VALIDATION OF AUTOMATED FINDINGS

**Every Medium+ automated finding MUST be manually validated.**

Automated scanners produce false positives. The report must contain only validated findings.

**Validation workflow:**

```
Automated finding from nuclei/nmap/Nessus
  |
  +-> Read the finding: what is the CVE/issue?
  +-> Check: does the detected version actually match?
  +-> Check: is the vulnerable endpoint/config actually present?
  |
  +-> Validate manually:
  |     Web vuln -> curl/browser to confirm response
  |     Version vuln -> verify banner matches CVE-affected versions
  |     Config vuln -> probe specific config (e.g., SNMP community)
  |     Default cred -> attempt login with specific credentials
  |
  +-> Result:
        CONFIRMED -> add to validated findings with evidence
        FALSE POSITIVE -> note as FP, exclude from findings
        UNCERTAIN -> flag for Phase 4 deeper investigation
```

---

## STEP 6: VULNERABILITY PRIORITIZATION

### Severity Classification (CVSS 3.1)

| Severity | CVSS | Exploitation Criteria |
|----------|------|-----------------------|
| Critical | 9.0-10.0 | Unauthenticated RCE, pre-auth bypass, full system compromise |
| High | 7.0-8.9 | Authenticated RCE, credential disclosure, significant data exposure |
| Medium | 4.0-6.9 | Information disclosure, weak crypto, misconfigurations |
| Low | 0.1-3.9 | Minor info leak, verbose errors, deprecated protocols |
| Info | 0.0 | Best practice observations (e.g., missing headers) |

### Prioritization for Phase 4

```
CRITICAL vulns (try first):
  +-> Unauthenticated RCE (Exchange, VPN, web apps)
  +-> Pre-auth credential disclosure
  +-> Default credentials on critical services

HIGH vulns (try second):
  +-> Authenticated RCE (if default creds found)
  +-> SNMP with read-write community string
  +-> IPMI hash extraction -> offline cracking
  +-> IKE aggressive mode -> PSK cracking

MEDIUM vulns (document, limited exploitation):
  +-> Weak TLS/SSL configurations
  +-> Information disclosure
  +-> Missing security headers
  +-> Open SMTP relay
```

---

## PHASE 3 OUTPUT CHECKLIST

Before requesting Phase 3->4 gate approval:

| Deliverable | File | Required |
|-------------|------|----------|
| Nuclei CVE scan results | `loot/ext-phase3/nuclei_cve_scan.out` | YES |
| Nmap vuln scan results | `loot/ext-phase3/nmap_vuln_scan.out` | YES |
| SearchSploit results | `loot/ext-phase3/searchsploit_*.out` | YES |
| Default credential check results | `loot/ext-phase3/default_creds_*.out` | YES |
| Validated vulnerability list | `loot/ext-phase3/validated_findings.md` | YES |
| Service-specific checks | `loot/ext-phase3/*_specific checks` | IF APPLICABLE |
| Screenshots of web vulns | `loot/screenshots/` | RECOMMENDED |

### Validated Findings Format

Create `loot/ext-phase3/validated_findings.md`:

```markdown
# Validated Findings — External Phase 3

## Finding 1: [Title]
- **Severity:** Critical / High / Medium / Low
- **CVSS:** X.X (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H)
- **Affected Host:** $TARGET_IP:$PORT
- **Service:** $SERVICE $VERSION
- **CVE:** CVE-YYYY-NNNNN (if applicable)
- **Validation:** [How confirmed — tool output, manual test]
- **Evidence:** loot/ext-phase3/[evidence file]
- **Exploitable:** Yes / No / Needs Phase 4 verification
- **Phase 4 Action:** [What to attempt in exploitation phase]
```

---

## FALSE POSITIVE INDICATORS

Watch for these common scanner false positives:

- **Version-only matches:** Scanner flags a CVE based on banner version, but the
  service may be patched (backported fix). Validate with exploit behavior, not just version.
- **WAF/proxy interference:** Web scanners may flag the WAF response, not the backend.
- **Template mismatch:** Nuclei template may trigger on similar-but-not-matching response.
- **Honeypot services:** Intentionally vulnerable services deployed as decoys.
- **Rate limiting:** Partial responses due to rate limiting can trigger false detections.

When uncertain, note as "Needs Validation" and flag for Phase 4.
