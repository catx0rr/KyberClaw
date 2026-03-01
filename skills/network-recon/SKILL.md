---
name: network-recon
version: 1.0.0
description: >
  Network reconnaissance reference for Phase 1 of internal black-box
  penetration testing. Covers network position identification, host discovery,
  infrastructure identification, service enumeration, DNS reconnaissance, and
  SMB signing analysis. Optimized for Raspberry Pi 5 ARM64 execution.
phases: [1]
agents: [recon]
sources:
  - https://nmap.org/book/man.html
  - https://www.netexec.wiki/
  - https://attack.mitre.org/tactics/TA0007/
  - https://orange-cyberdefense.github.io/ocd-mindmaps/
---

# Network Reconnaissance — Phase 1 Reference

> **Phase 1 goal:** Map the network. Identify DCs. Enumerate services.
> Determine SMB signing status. Build target prioritization for Phase 2.
>
> **Constraint:** No credentials. All techniques must be unauthenticated.
> **Pi5 optimization:** Prefer `-sS` (SYN scan) over `-sT` (connect).
> Use `--min-rate 3000` for speed. Monitor CPU temp during heavy scans.

## STEP 1: NETWORK POSITION IDENTIFICATION

**MITRE:** T1016 (System Network Configuration Discovery)

Before scanning anything, understand where the Pi is positioned.

```bash
# Own IP address(es) — exclude Tailscale
ip -4 addr show | grep -v tailscale | grep 'inet ' \
  | tee -a loot/phase1/own_position.out

# Default gateway
ip route show default | tee -a loot/phase1/own_position.out

# DNS server(s)
cat /etc/resolv.conf | tee -a loot/phase1/own_position.out

# DHCP lease info (identify DHCP server, lease time, DNS domain)
cat /var/lib/dhcp/dhclient.leases 2>/dev/null \
  | tee -a loot/phase1/dhcp_lease.out

# ARP table (immediate neighbors)
arp -an | tee -a loot/phase1/arp_initial.out

# MAC vendor lookup on gateway (identify network equipment)
ip neigh show | tee -a loot/phase1/neighbors.out
```

**What to extract:**
- Own IP and subnet mask (determines scan range)
- Gateway IP (usually a router or firewall)
- DNS servers (often DCs in AD environments)
- DHCP domain name (may reveal AD domain name)
- VLAN isolation (can we reach other subnets?)

---

## STEP 2: HOST DISCOVERY

**MITRE:** T1018 (Remote System Discovery)

### 2.1 ARP Sweep (Local Subnet — Fastest)

```bash
# ARP sweep — reliable for local subnet, not routable
nmap -sn -PR $SUBNET --min-rate 3000 \
  | tee -a loot/phase1/nmap_arpsweep_$SUBNET_SAFE.out
```

### 2.2 Ping Sweep (Broader — Works Across Subnets)

```bash
# ICMP echo + TCP SYN to 443 + TCP ACK to 80 (catches firewalled hosts)
nmap -sn $SUBNET --min-rate 3000 \
  | tee -a loot/phase1/nmap_pingsweep_$SUBNET_SAFE.out
```

### 2.3 TCP Discovery (Bypass ICMP Filters)

```bash
# If ICMP blocked — probe common ports to find live hosts
nmap -sn -PS22,80,88,135,139,389,443,445,3389 $SUBNET --min-rate 3000 \
  | tee -a loot/phase1/nmap_tcpdiscovery_$SUBNET_SAFE.out
```

### 2.4 Generate Live Host List

```bash
# Extract live IPs for use in subsequent scans
grep 'Nmap scan report' loot/phase1/nmap_*sweep*.out \
  | awk '{print $NF}' | tr -d '()' | sort -u \
  > loot/phase1/live_hosts.txt
```

**Decision tree for host discovery:**
- Small subnet (/24 or smaller) -> ARP sweep first, ping sweep second
- Medium subnet (/16) -> Ping sweep with `--min-rate 5000`
- Large subnet (>/16) -> Split into /24 blocks, scan sequentially
- ICMP filtered -> TCP discovery on AD-critical ports (88, 389, 445)
- Monitor Pi5 CPU temp: pause if >80C, resume after cooldown

---

## STEP 3: INFRASTRUCTURE IDENTIFICATION

**MITRE:** T1082 (System Information Discovery), T1018

### 3.1 Domain Controller Identification

DCs are the highest-value targets. Identify them early.

```bash
# DNS SRV records for AD services (reveals DCs and domain name)
nslookup -type=SRV _ldap._tcp.dc._msdcs.$DOMAIN $DNS_SERVER 2>&1 \
  | tee -a loot/phase1/dns_dc_srv.out
nslookup -type=SRV _kerberos._tcp.$DOMAIN $DNS_SERVER 2>&1 \
  | tee -a loot/phase1/dns_kerberos_srv.out
nslookup -type=SRV _gc._tcp.$DOMAIN $DNS_SERVER 2>&1 \
  | tee -a loot/phase1/dns_gc_srv.out

# Identify DCs by port signature (88+389+445+636+3268)
nmap -sS -p 88,389,636,3268,3269 $SUBNET --min-rate 3000 --open \
  | tee -a loot/phase1/nmap_dc_ports_$SUBNET_SAFE.out

# netexec SMB enumeration (reveals hostname, domain, OS version)
netexec smb $SUBNET | tee -a loot/phase1/nxc_smb_enum_$SUBNET_SAFE.out
```

**DC confirmation checklist:**
- Port 88 (Kerberos) open
- Port 389/636 (LDAP/LDAPS) open
- Port 3268 (Global Catalog) open
- Hostname matches DNS SRV records
- netexec reports domain membership

### 3.2 Other Infrastructure Servers

```bash
# DNS servers (port 53)
nmap -sS -p 53 $SUBNET --min-rate 3000 --open \
  | tee -a loot/phase1/nmap_dns_$SUBNET_SAFE.out

# DHCP servers (UDP 67/68 — harder to detect, check lease info)
# Usually the gateway or a dedicated DHCP server

# SCCM/MECM (ports 80, 443, 8530, 8531, 10123)
nmap -sS -p 80,443,8530,8531,10123 $SUBNET --min-rate 3000 --open \
  | tee -a loot/phase1/nmap_sccm_$SUBNET_SAFE.out

# Certificate Authority (ADCS — certsrv on 80/443)
# Often co-located with a DC or standalone CA server
```

---

## STEP 4: SERVICE ENUMERATION

**MITRE:** T1046 (Network Service Discovery)

### 4.1 Full Port Scan on Live Hosts

```bash
# Top 1000 ports with version detection (fast, covers most services)
nmap -sS -sV -sC -p- --min-rate 3000 -iL loot/phase1/live_hosts.txt \
  | tee -a loot/phase1/nmap_full_portscan.out

# If time-constrained: top 1000 only (much faster)
nmap -sS -sV --top-ports 1000 --min-rate 3000 -iL loot/phase1/live_hosts.txt \
  | tee -a loot/phase1/nmap_top1000_portscan.out
```

**Pi5 note:** Full port scan (`-p-`) on >50 hosts will take significant time
on ARM64. For large networks, prioritize targeted scans on high-value ports
first, then run full port scan on high-value targets only.

### 4.2 AD-Critical Service Scan (Targeted)

```bash
# AD-specific ports on all live hosts
nmap -sS -sV -sC \
  -p 21,22,23,25,53,80,88,110,111,135,139,143,161,389,443,445,464, \
     636,993,995,1433,1521,2049,3268,3269,3306,3389,5432,5985,5986, \
     8080,8443,9389 \
  --min-rate 3000 -iL loot/phase1/live_hosts.txt \
  | tee -a loot/phase1/nmap_ad_services.out
```

### 4.3 Service-Specific Enumeration

```bash
# HTTP/HTTPS service discovery (httpx — fast, categorized output)
cat loot/phase1/live_hosts.txt \
  | httpx -ports 80,443,8080,8443 -title -tech-detect -status-code \
  | tee -a loot/phase1/httpx_web_services.out

# SMB enumeration (detailed: hostname, domain, OS, signing)
netexec smb -iL loot/phase1/live_hosts.txt \
  | tee -a loot/phase1/nxc_smb_detailed.out

# MSSQL discovery
netexec mssql $SUBNET | tee -a loot/phase1/nxc_mssql_$SUBNET_SAFE.out

# WinRM availability
netexec winrm -iL loot/phase1/live_hosts.txt \
  | tee -a loot/phase1/nxc_winrm.out
```

---

## STEP 5: DNS RECONNAISSANCE

**MITRE:** T1018, T1046

```bash
# Reverse DNS on entire subnet (reveal hostnames)
nmap -sL $SUBNET 2>/dev/null | grep 'Nmap scan report' \
  | tee -a loot/phase1/nmap_reverse_dns_$SUBNET_SAFE.out

# Zone transfer attempt (rare but devastating)
dnsrecon -d $DOMAIN -t axfr -n $DNS_SERVER \
  | tee -a loot/phase1/dnsrecon_axfr_$DOMAIN.out

# DNS brute-force (common hostnames)
dnsrecon -d $DOMAIN -t brt -D /usr/share/wordlists/dnsrecon/subdomains-top1mil-5000.txt \
  -n $DNS_SERVER | tee -a loot/phase1/dnsrecon_brute_$DOMAIN.out

# SRV record enumeration (discover all AD services)
dnsrecon -d $DOMAIN -t srv -n $DNS_SERVER \
  | tee -a loot/phase1/dnsrecon_srv_$DOMAIN.out

# Wildcard detection
dnsrecon -d $DOMAIN -t std -n $DNS_SERVER \
  | tee -a loot/phase1/dnsrecon_std_$DOMAIN.out
```

---

## STEP 6: SMB SIGNING STATUS (CRITICAL FOR PHASE 2)

**MITRE:** T1046

SMB signing determines whether NTLM relay attacks are viable. This is one
of the most important Phase 1 outputs.

```bash
# Generate relay target list (hosts without SMB signing enforcement)
netexec smb $SUBNET --gen-relay-list loot/phase1/relay_targets.txt \
  | tee -a loot/phase1/nxc_smb_signing_$SUBNET_SAFE.out

# Count relay targets
echo "Relay targets: $(wc -l < loot/phase1/relay_targets.txt)" \
  | tee -a loot/phase1/nxc_smb_signing_$SUBNET_SAFE.out
```

**Phase 2 impact:**
- >0 relay targets -> NTLM relay attacks viable (HIGH priority for Phase 2)
- 0 relay targets -> relay blocked, focus on hash capture + offline cracking
- DCs usually enforce signing; workstations and member servers often do not

---

## STEP 7: VULNERABILITY PRE-SCAN

**MITRE:** T1046

Quick check for low-hanging vulnerabilities before Phase 2.

```bash
# Nuclei network scan (known CVEs, misconfigs)
nuclei -l loot/phase1/live_hosts.txt -t network/ -t cves/ \
  -severity critical,high -c 25 \
  | tee -a loot/phase1/nuclei_network_scan.out

# Nmap vulnerability scripts on high-value targets (DCs, servers)
nmap --script vuln -p 445,139,88,389 $DC_IP \
  | tee -a loot/phase1/nmap_vuln_$DC_IP.out
```

---

## PHASE 1 OUTPUT CHECKLIST

Before requesting Phase 2 gate approval, verify these deliverables exist:

| Deliverable | File | Required |
|-------------|------|----------|
| Live host list | `loot/phase1/live_hosts.txt` | YES |
| DC identification (IPs + hostnames) | `loot/phase1/nmap_dc_ports_*.out` | YES |
| Domain name | `loot/phase1/dns_dc_srv.out` | YES |
| SMB signing status / relay targets | `loot/phase1/relay_targets.txt` | YES |
| Service inventory | `loot/phase1/nmap_ad_services.out` | YES |
| DNS recon (SRV + reverse + zone xfer attempt) | `loot/phase1/dnsrecon_*.out` | YES |
| Web service inventory | `loot/phase1/httpx_web_services.out` | RECOMMENDED |
| Nuclei pre-scan | `loot/phase1/nuclei_network_scan.out` | RECOMMENDED |

---

## SCAN ORDER DECISION TREE

```
Start Phase 1
  |
  +-> Identify own position (IP, subnet, gateway, DNS)
  |
  +-> Determine subnet size
  |     /24 or smaller -> full scan workflow below
  |     /16 -> split into /24 blocks, prioritize gateway's /24 first
  |     >/16 -> target AD-critical ports only on full range first
  |
  +-> ARP sweep (local subnet only)
  +-> Ping sweep (all subnets)
  +-> Generate live host list
  |
  +-> DNS SRV records -> identify domain name + DCs
  +-> DC port confirmation scan (88, 389, 636, 3268)
  |
  +-> SMB signing check (CRITICAL — informs Phase 2 strategy)
  |
  +-> AD-critical port scan on live hosts
  +-> Service version detection on open ports
  |
  +-> DNS recon (zone xfer, brute, SRV, reverse)
  +-> HTTP service enumeration (httpx)
  +-> Nuclei vulnerability pre-scan
  |
  +-> Compile output checklist -> request Phase 1->2 gate
```

---

## Pi5 ARM64 SCAN OPTIMIZATION

- **Prefer `-sS` (SYN scan):** Faster and stealthier than `-sT` (connect scan).
  Requires root but Pi runs as root during engagements.
- **Use `--min-rate 3000`:** Prevents nmap from throttling on ARM64. Adjust down
  to 1000 if packet loss detected (check with `--stats-every 30s`).
- **Avoid `-sV -sC` on full `/24` port scans:** Version detection is slow on ARM64.
  Run `-sS -p-` first for port discovery, then `-sV -sC` on discovered open ports only.
- **CPU temperature:** Monitor with `cat /sys/class/thermal/thermal_zone0/temp`.
  Pi5 throttles at 80C. Pause scans if temp exceeds 75C.
- **Concurrent scans:** Do not run more than 2 nmap instances simultaneously on Pi5.
  RAM and CPU are limited (8GB, 4 cores).
- **netexec:** Fully optimized for fast subnet scanning. No ARM64 issues.
- **httpx:** Go binary, runs efficiently on ARM64. No issues.
- **nuclei:** Go binary, runs efficiently on ARM64. Update templates before
  engagement: `nuclei -update-templates`.
