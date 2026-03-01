---
name: external-recon
version: 1.0.0
description: >
  External reconnaissance reference for Phases 1-2 of black-box external
  penetration testing. Covers passive OSINT (Phase 1) and active scanning
  (Phase 2). Techniques for IP range reconnaissance, service enumeration,
  TLS/SSL analysis, and target prioritization from the internet.
phases: [1, 2]
agents: [ext-recon]
sources:
  - http://www.pentest-standard.org/
  - https://csrc.nist.gov/pubs/sp/800/115/final
  - https://attack.mitre.org/tactics/TA0043/
  - https://attack.mitre.org/tactics/TA0001/
  - https://orange-cyberdefense.github.io/ocd-mindmaps/
---

# External Reconnaissance — Phase 1-2 Reference

> **Phase 1 goal:** Passive intelligence gathering. Zero packets to target.
> Build OSINT dossier, discover subdomains, fingerprint technology stack.
>
> **Phase 2 goal:** Active scanning. Full port/service enumeration.
> TLS/SSL analysis. Build complete service inventory for Phase 3.
>
> **Constraint:** Only in-scope CIDRs. Verify every target IP against scope
> before interaction. Out-of-scope = DO NOT TOUCH.

---

## PHASE 1: PASSIVE RECONNAISSANCE (OSINT)

### STEP 1: WHOIS & ASN ANALYSIS

**MITRE:** T1590 (Gather Victim Network Info)

```bash
# WHOIS on each IP range
whois $TARGET_IP | tee -a loot/ext-phase1/whois_$TARGET_IP_SAFE.out

# ASN lookup
whois -h whois.radb.net -- "-i origin $(whois $TARGET_IP | grep -i origin | awk '{print $NF}')" \
  | tee -a loot/ext-phase1/asn_$TARGET_IP_SAFE.out

# BGP prefix analysis (adjacent ranges owned by same org)
whois -h whois.radb.net $TARGET_CIDR \
  | tee -a loot/ext-phase1/bgp_$TARGET_CIDR_SAFE.out
```

**What to extract:**
- Organization name, registrant details
- ASN (Autonomous System Number)
- Adjacent IP ranges under same ASN
- Registrar, registration/expiry dates
- Abuse contact (may reveal hosting provider)

### STEP 2: CERTIFICATE TRANSPARENCY

**MITRE:** T1596 (Search Open Technical Databases)

```bash
# crt.sh — discover subdomains from certificate transparency logs
curl -s "https://crt.sh/?q=%25.$DOMAIN&output=json" | jq -r '.[].name_value' \
  | sort -u | tee -a loot/ext-phase1/crtsh_$DOMAIN.out

# Resolve discovered subdomains to IPs — check if in scope
cat loot/ext-phase1/crtsh_$DOMAIN.out | while read sub; do
  host "$sub" 2>/dev/null | grep "has address"
done | tee -a loot/ext-phase1/subdomain_resolve_$DOMAIN.out
```

### STEP 3: SHODAN / CENSYS QUERIES

**MITRE:** T1596.005 (Scan Databases)

```bash
# Shodan CLI (if API key available)
shodan host $TARGET_IP | tee -a loot/ext-phase1/shodan_$TARGET_IP_SAFE.out

# Shodan search by org/net
shodan search "net:$TARGET_CIDR" --fields ip_str,port,org,product \
  | tee -a loot/ext-phase1/shodan_net_$TARGET_CIDR_SAFE.out
```

**What to extract:**
- Exposed services, banners, product versions
- Historical scan data (services that may have been recently closed)
- CVE associations flagged by Shodan
- SSL certificate details

### STEP 4: DNS ENUMERATION

**MITRE:** T1590.002 (DNS)

```bash
# Reverse DNS on all IPs in scope
nmap -sL $TARGET_CIDR 2>/dev/null | grep 'Nmap scan report' \
  | tee -a loot/ext-phase1/reverse_dns_$TARGET_CIDR_SAFE.out

# Zone transfer attempt (rare on external, always try)
dnsrecon -d $DOMAIN -t axfr \
  | tee -a loot/ext-phase1/dnsrecon_axfr_$DOMAIN.out

# SRV records
dnsrecon -d $DOMAIN -t srv \
  | tee -a loot/ext-phase1/dnsrecon_srv_$DOMAIN.out

# Subdomain brute-force
dnsrecon -d $DOMAIN -t brt -D /usr/share/wordlists/dnsrecon/subdomains-top1mil-5000.txt \
  | tee -a loot/ext-phase1/dnsrecon_brute_$DOMAIN.out

# theHarvester — email addresses, subdomains, virtual hosts
theHarvester -d $DOMAIN -b all -l 500 \
  | tee -a loot/ext-phase1/theharvester_$DOMAIN.out
```

### STEP 5: GOOGLE DORKING & OSINT

**MITRE:** T1593 (Search Open Websites/Domains)

Search for exposed configs, credentials, admin panels:
- `site:$DOMAIN filetype:conf OR filetype:env OR filetype:bak`
- `site:$DOMAIN inurl:admin OR inurl:login OR inurl:portal`
- `"$ORG_NAME" filetype:pdf OR filetype:xlsx "password" OR "credentials"`
- `site:pastebin.com "$DOMAIN"`
- `site:github.com "$DOMAIN" password OR secret OR key`

```bash
# Automated with theHarvester sources
theHarvester -d $DOMAIN -b google,bing,linkedin -l 200 \
  | tee -a loot/ext-phase1/osint_$DOMAIN.out
```

### STEP 6: TECHNOLOGY FINGERPRINTING

**MITRE:** T1592 (Gather Victim Host Information)

```bash
# Job posting analysis (infer tech stack from job listings)
# Manual: search LinkedIn, Indeed for "$ORG_NAME" IT positions
# Look for: specific OS versions, web frameworks, security tools, VPN products

# Social media OSINT
# LinkedIn: employee roles, IT team size, tech stack mentions
# GitHub: org repos, leaked configs, commit history
```

---

## PHASE 2: ACTIVE RECONNAISSANCE & SERVICE ENUMERATION

### STEP 7: TCP PORT SWEEP

**MITRE:** T1595.001 (Active Scanning: Scanning IP Blocks)

```bash
# Full TCP port sweep (SYN scan, fast)
nmap -sS -p- --min-rate 3000 --open $TARGET_CIDR \
  | tee -a loot/ext-phase2/nmap_tcp_full_$TARGET_CIDR_SAFE.out

# If time-constrained: top 1000 ports first
nmap -sS --top-ports 1000 --min-rate 3000 --open $TARGET_CIDR \
  | tee -a loot/ext-phase2/nmap_top1000_$TARGET_CIDR_SAFE.out

# For large ranges (/16+): use masscan for speed, then nmap for detail
masscan $TARGET_CIDR -p0-65535 --rate 10000 -oJ loot/ext-phase2/masscan_$TARGET_CIDR_SAFE.json \
  | tee -a loot/ext-phase2/masscan_$TARGET_CIDR_SAFE.out
```

### STEP 8: UDP PORT SWEEP

```bash
# Top 200 UDP ports (slow, but catches SNMP, IPMI, IKE, NTP, DNS)
nmap -sU --top-ports 200 --min-rate 1000 --open $TARGET_CIDR \
  | tee -a loot/ext-phase2/nmap_udp_$TARGET_CIDR_SAFE.out

# High-priority UDP: SNMP (161), IPMI (623), IKE (500/4500), NTP (123), DNS (53)
nmap -sU -p 53,123,161,500,623,4500 --min-rate 1000 --open $TARGET_CIDR \
  | tee -a loot/ext-phase2/nmap_udp_priority_$TARGET_CIDR_SAFE.out
```

### STEP 9: SERVICE VERSION & OS FINGERPRINTING

**MITRE:** T1046 (Network Service Discovery)

```bash
# Service version + default scripts on discovered open ports
nmap -sS -sV -sC -O -p $OPEN_PORTS -iL loot/ext-phase2/live_hosts.txt \
  | tee -a loot/ext-phase2/nmap_version_$TARGET_CIDR_SAFE.out

# Web service discovery (httpx)
cat loot/ext-phase2/live_hosts.txt \
  | httpx -ports 80,443,8080,8443,8000,8888,9090 -title -tech-detect -status-code -follow-redirects \
  | tee -a loot/ext-phase2/httpx_web_services.out
```

### STEP 10: TLS/SSL ANALYSIS

```bash
# testssl.sh — comprehensive TLS analysis per host
testssl.sh --ip one --csvfile loot/ext-phase2/testssl_$TARGET_IP_SAFE.csv \
  $TARGET_IP:443 | tee -a loot/ext-phase2/testssl_$TARGET_IP_SAFE.out

# sslyze — alternative, good for mass scanning
sslyze --regular $TARGET_IP:443 \
  | tee -a loot/ext-phase2/sslyze_$TARGET_IP_SAFE.out

# Check for: SSLv2/3, TLS 1.0/1.1, weak ciphers, expired certs,
# self-signed certs, missing HSTS, certificate mismatch
```

### STEP 11: HIGH-PRIORITY SERVICE ENUMERATION

```bash
# VPN (IKE aggressive mode — PSK hash extraction)
ike-scan -M --aggressive $TARGET_IP \
  | tee -a loot/ext-phase2/ikescan_$TARGET_IP_SAFE.out

# SNMP (community string brute)
onesixtyone -c /usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt $TARGET_IP \
  | tee -a loot/ext-phase2/snmp_brute_$TARGET_IP_SAFE.out

# SNMP walk (if community string found)
snmpwalk -v 2c -c $COMMUNITY $TARGET_IP \
  | tee -a loot/ext-phase2/snmpwalk_$TARGET_IP_SAFE.out

# IPMI (Cipher 0 / hash extraction)
ipmitool -I lanplus -H $TARGET_IP -U "" -P "" chassis status \
  | tee -a loot/ext-phase2/ipmi_$TARGET_IP_SAFE.out

# FTP anonymous login
nmap --script ftp-anon -p 21 $TARGET_IP \
  | tee -a loot/ext-phase2/ftp_anon_$TARGET_IP_SAFE.out

# SMTP relay test
nmap --script smtp-open-relay -p 25,587 $TARGET_IP \
  | tee -a loot/ext-phase2/smtp_relay_$TARGET_IP_SAFE.out
```

### STEP 12: GENERATE LIVE HOST LIST & SERVICE INVENTORY

```bash
# Extract live IPs
grep 'Nmap scan report' loot/ext-phase2/nmap_tcp_full_*.out \
  | awk '{print $NF}' | tr -d '()' | sort -u \
  > loot/ext-phase2/live_hosts.txt

# Service summary (for Phase 3 targeting)
grep -h '^[0-9]' loot/ext-phase2/nmap_version_*.out \
  | sort -u > loot/ext-phase2/service_inventory.txt
```

---

## PHASE 1-2 OUTPUT CHECKLIST

Before requesting Phase 2->3 gate approval, verify:

| Deliverable | File | Required |
|-------------|------|----------|
| WHOIS / ASN data | `loot/ext-phase1/whois_*.out` | YES |
| Certificate transparency results | `loot/ext-phase1/crtsh_*.out` | YES |
| DNS enumeration (reverse, SRV, brute) | `loot/ext-phase1/dnsrecon_*.out` | YES |
| Shodan/Censys data | `loot/ext-phase1/shodan_*.out` | RECOMMENDED |
| OSINT dossier | `loot/ext-phase1/osint_*.out` | RECOMMENDED |
| TCP full port scan | `loot/ext-phase2/nmap_tcp_full_*.out` | YES |
| UDP priority scan | `loot/ext-phase2/nmap_udp_priority_*.out` | YES |
| Service version inventory | `loot/ext-phase2/nmap_version_*.out` | YES |
| TLS/SSL analysis | `loot/ext-phase2/testssl_*.out` | YES |
| Web service inventory | `loot/ext-phase2/httpx_web_services.out` | YES |
| Live host list | `loot/ext-phase2/live_hosts.txt` | YES |
| VPN/IKE scan | `loot/ext-phase2/ikescan_*.out` | IF VPN PORTS FOUND |
| SNMP enumeration | `loot/ext-phase2/snmp_brute_*.out` | IF UDP 161 OPEN |

---

## SCAN ORDER DECISION TREE

```
Start Phase 1 (Passive)
  |
  +-> WHOIS + ASN on all scope CIDRs
  +-> Certificate transparency (crt.sh)
  +-> DNS enumeration (reverse, SRV, zone xfer, brute)
  +-> Shodan/Censys queries
  +-> theHarvester + Google dorking
  +-> Technology fingerprinting (job posts, social media)
  |
  +-> Compile OSINT dossier -> report to Zero
  |
Start Phase 2 (Active)
  |
  +-> TCP full port sweep (all scope CIDRs)
  +-> UDP priority ports (53, 123, 161, 500, 623, 4500)
  +-> Generate live host list
  |
  +-> Service version detection on open ports
  +-> TLS/SSL analysis on HTTPS services
  +-> Web service enumeration (httpx)
  |
  +-> High-priority service checks:
  |     VPN found? -> IKE aggressive mode
  |     SNMP found? -> community string brute
  |     FTP found? -> anonymous login check
  |     SMTP found? -> relay test
  |     IPMI found? -> Cipher 0 check
  |
  +-> Compile service inventory -> request Phase 2->3 gate
```

---

## SCOPE VALIDATION (CRITICAL)

Before ANY active scan in Phase 2:

1. Verify target IP/CIDR is in ENGAGEMENT.md in-scope list
2. If a discovered subdomain resolves to an IP outside scope -> DO NOT SCAN
3. Log out-of-scope discoveries as informational only
4. Use `scripts/scope-check.sh` for CIDR validation when uncertain
5. When in doubt, report to Zero and await confirmation
