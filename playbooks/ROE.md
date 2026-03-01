# Rules of Engagement Template

> Fill this template during Phase 0 (Pre-Engagement). Data transfers to ENGAGEMENT.md.

## Engagement Information

| Field | Value |
|-------|-------|
| **Engagement ID** | ENG-YYYY-NNN |
| **Client** | [Organization name — NOT stored in memory] |
| **Type** | [ ] Internal Network Pentest / [ ] External Network Pentest |
| **Mode** | [ ] Black-box / [ ] Gray-box / [ ] White-box |
| **Operator** | [Name/Handle from USER.md] |
| **Start Date** | YYYY-MM-DD |
| **End Date** | YYYY-MM-DD |
| **Testing Window** | [Hours, e.g., "09:00-17:00 UTC" or "24/7"] |

## Scope Definition

### In-Scope Targets

| Type | Value | Notes |
|------|-------|-------|
| CIDR | | |
| Domain | | |
| Host | | |

### Out-of-Scope (DO NOT INTERACT)

| Type | Value | Reason |
|------|-------|--------|
| CIDR | | |
| Host | | |
| Service | | |

### Scope Rules

- **Internal:** Entire local network segment is in-scope UNLESS specific hosts/subnets excluded above
- **External:** ONLY listed CIDRs/domains/hosts are in-scope. Everything else is out-of-scope by default

## Authorization

| Item | Status |
|------|--------|
| Written authorization received | [ ] Yes / [ ] No |
| Emergency contact documented | [ ] Yes: ________________ |
| Client-side monitoring team aware | [ ] Yes / [ ] No / [ ] N/A |
| ISP/hosting provider notified | [ ] Yes / [ ] No / [ ] N/A (external only) |

## Constraints

| Constraint | Value |
|-----------|-------|
| **Denial of Service** | [ ] Prohibited / [ ] Allowed with caution |
| **Social Engineering** | [ ] Prohibited / [ ] Allowed (scope: ___) |
| **Physical Access** | [ ] Not applicable / [ ] Allowed |
| **Data Exfiltration** | [ ] Demonstrate only / [ ] Full extraction |
| **Brute Force Rate** | Max ___ attempts/min |
| **Credential Testing** | [ ] Default creds only / [ ] Full spray allowed |
| **Exploitation Depth** | [ ] Validate only / [ ] Full compromise |

## Gray-Box Credentials (If Applicable)

| Field | Value |
|-------|-------|
| CIDR | | |
| Username | |
| Password/Hash | |
| Domain | |
| Privilege Level | [ ] Standard User / [ ] Local Admin / [ ] Other: ___ |
| Starting Phase | Phase 3 (skip Phases 1-2) |

## Communication Protocol

| Event | Action |
|-------|--------|
| Critical finding discovered | Notify operator immediately via WhatsApp |
| Phase gate reached | Request approval via WhatsApp |
| System impact detected | STOP, notify operator, await instruction |
| Out-of-scope system found | Log, flag to operator, do NOT interact |
| Engagement blocked | Report status, suggest alternatives |

## Operator Acknowledgment

- [ ] I confirm scope and constraints are accurate
- [ ] I authorize Zero to begin the engagement
- [ ] GO signal given: [timestamp]
