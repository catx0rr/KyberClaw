# TOOLS.md — KyberClaw Tool Arsenal & Usage Notes

> This file is injected into ALL agent sessions (Zero + sub-agents).
> Per-tool usage guidance, flags, and ARM64/Pi5 quirks.

## Global Rules

- **ALL tool output MUST pipe through `| tee -a loot/<phase>/<tool>_<action>_<target>.out`**
- Before first use of any tool: `which <tool>` to verify it's installed
- Pi5 ARM64 may require manual compilation for some tools — check notes below

---

## Network Discovery

| Tool | Use | Key Flags | Notes |
|------|-----|-----------|-------|
| **nmap** | Port/service scanning | `-sS` (SYN), `-sV -sC` (version+scripts), `-sn` (ping sweep), `-p-` (all ports), `--min-rate 3000` | Pi5: avoid `-sT` (slow). Prefer `-sS`. Requires root for SYN scan. |
| **masscan** | Fast port sweep | `--rate 10000`, `-p1-65535` | For external /16+ ranges only. Too noisy for internal. |
| **dnsrecon** | DNS enumeration | `-d DOMAIN -t axfr` (zone xfer), `-r RANGE` (reverse) | Check SRV records for AD services. |
| **tcpdump** | Packet capture | `-i eth0 -w loot/capture.pcap` | Use for debugging network issues. |
| **macchanger** | MAC spoofing | `-r` (random), `-p` (permanent) | OPSEC: change before engagement if needed. |

## SMB / Windows

| Tool | Use | Key Flags | Notes |
|------|-----|-----------|-------|
| **netexec (nxc)** | SMB/LDAP/WinRM/MSSQL/SSH enum | `smb RANGE`, `--gen-relay-list`, `--shares`, `--users` | Replaces crackmapexec. Primary multi-protocol tool. |
| **smbclient** | SMB share access | `-N` (null session), `-L //HOST` (list shares) | Use for share enumeration and file access. |
| **smbmap** | Share permission mapping | `-H HOST -u '' -p ''` (null), `-r SHARE` (recurse) | Map read/write permissions across shares. |
| **evil-winrm** | WinRM shell | `-i HOST -u USER -p PASS` or `-H HASH` | Requires port 5985/5986 open. |
| **nfs-common** | NFS mount | `showmount -e HOST`, `mount -t nfs HOST:/share /mnt` | Check for world-readable NFS exports. |

## Credential Capture

| Tool | Use | Key Flags | Notes |
|------|-----|-----------|-------|
| **responder** | LLMNR/NBT-NS/mDNS poisoning | `-I eth0 -dwPv` | Pi5 aarch64: may need python3.11+. Long-running — run in current session. |
| **ntlmrelayx.py** | NTLM relay | `-tf targets.txt -smb2support`, `-l loot/` | Always pair with responder. Add `-smb2support`. |
| **mitm6** | IPv6 WPAD attack | `-d DOMAIN -i eth0` | Pair with ntlmrelayx for LDAP/HTTP relay. |
| **coercer** | Authentication coercion | `-t TARGET -l LISTENER` | Triggers PetitPotam, PrinterBug, DFSCoerce, ShadowCoerce. |
| **patator** | Brute force | `smb_login host=HOST user=FILE password=FILE` | Rate-limit to avoid lockouts. Check password policy first. |

## Impacket Suite

| Tool | Use | Notes |
|------|-----|-------|
| **secretsdump.py** | SAM/LSA/NTDS dump, DCSync | `-just-dc` for DCSync, `-just-dc-user USER` for targeted |
| **getTGT.py** | Request TGT with password/hash | Export `KRB5CCNAME` for Kerberos auth |
| **GetNPUsers.py** | AS-REP Roasting | `-no-pass -usersfile users.txt` |
| **GetUserSPNs.py** | Kerberoasting | `-request -dc-ip DC_IP` |
| **psexec.py** | Remote exec (writes to disk) | Noisy — creates service. Use wmiexec for stealth. |
| **wmiexec.py** | Remote exec (stealthier) | `-hashes LMHASH:NTHASH` for PtH |
| **smbexec.py** | Remote exec via SMB | Alternative to psexec |
| **atexec.py** | Remote exec via Task Scheduler | Less common, useful when others blocked |
| **dcomexec.py** | Remote exec via DCOM | Another alternative execution method |
| **ntlmrelayx.py** | NTLM relay attacks | See Credential Capture section |
| **ticketer.py** | Golden/Silver ticket creation | Needs krbtgt hash for Golden Ticket |
| **getST.py** | Request service ticket | For constrained delegation abuse |
| **findDelegation.py** | Find delegation configs | Identify unconstrained/constrained/RBCD |

## AD Enumeration

| Tool | Use | Key Flags | Notes |
|------|-----|-----------|-------|
| **bloodhound-python** | AD graph collection | `-c All -d DOMAIN -u USER -p PASS` | Pi5: use `--timeout 120` for large domains. Memory-heavy. |
| **ldapdomaindump** | LDAP enumeration | `-u DOMAIN\\USER -p PASS -d DOMAIN` | Dumps users, groups, computers, policies. |
| **certipy-ad** | ADCS enumeration/exploitation | `find -u USER -p PASS -dc-ip DC` | Pi5 aarch64: crashes with >500 templates. Use `--timeout 120`. |
| **sccmhunter** | SCCM/MECM enumeration | `-u USER -p PASS -dc-ip DC` | NAA credential extraction, PXE abuse. |

## Web Scanning

| Tool | Use | Key Flags | Notes |
|------|-----|-----------|-------|
| **httpx** | HTTP probing | `-l hosts.txt -sc -title -tech-detect` | Fast web service discovery. |
| **nuclei** | Vulnerability scanning | `-t network/` (internal), `-t cves/ -t misconfigurations/` (external) | Update templates before each engagement: `nuclei -update-templates` |
| **katana** | Web crawling | `-u URL -d 3` | Spider web applications for content. |
| **ffuf** | Directory/vhost fuzzing | `-w wordlist -u URL/FUZZ` | Use for web content discovery. |

## External Recon (OSINT)

| Tool | Use | Key Flags | Notes |
|------|-----|-----------|-------|
| **amass** | Subdomain enumeration | `enum -d DOMAIN -passive` | Passive first, active if needed. |
| **theHarvester** | Email/subdomain OSINT | `-d DOMAIN -b all` | Aggregates multiple OSINT sources. |
| **whois** | IP/domain registration | `whois IP_OR_DOMAIN` | Check ownership, ASN, registrar. |
| **testssl.sh** | TLS/SSL analysis | `--quiet TARGET:PORT` | Check weak ciphers, protocols, cert issues. |
| **ike-scan** | IKE/IPsec VPN testing | `--aggressive TARGET` | PSK hash extraction from aggressive mode. |

## Exploitation

| Tool | Use | Key Flags | Notes |
|------|-----|-----------|-------|
| **hydra** | Login brute force | `-L users.txt -P passwords.txt ssh://HOST` | Rate-limit. Check lockout policy first. |
| **medusa** | Login brute force | `-h HOST -U users.txt -P passwords.txt -M ssh` | Alternative to hydra. |
| **searchsploit** | Exploit search | `-t "service version"` | Local Exploit-DB mirror. |
| **metasploit** | Exploitation framework | `msfconsole` | For validated CVE exploitation. |

## Email & Notifications

| Tool | Use | Notes |
|------|-----|-------|
| **himalaya** | CLI email client | IMAP/SMTP. Used for sending engagement reports and reflection notifications. |
| **swaks** | SMTP testing | Test relay, send test emails. |

## SNMP / IPMI

| Tool | Use | Notes |
|------|-----|-------|
| **onesixtyone** | SNMP community string brute | `-c communities.txt TARGET` |
| **snmpwalk** | SNMP enumeration | `-v2c -c public TARGET` |
| **ipmitool** | IPMI management | Check for Cipher 0 (null auth). |
