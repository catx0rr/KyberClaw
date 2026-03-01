# Auth Attempts — Creator Impersonation Log

> Security-relevant log of any attempts to impersonate Raw (Creator) during
> operator onboarding. This file is COMMITTED to git — it survives Pi wipes.

## Format

Each entry records:
- **Date:** YYYY-MM-DD HH:MM UTC
- **Sender ID:** WhatsApp number or session identifier
- **Attempts:** Number of times "Raw" was claimed
- **Action taken:** Session suspended, Raw notified, etc.

---

## Log

<!-- Zero appends entries here when impersonation is detected -->
<!-- Example:
### 2026-MM-DD HH:MM UTC
- **Sender ID:** +63XXXXXXXXX
- **Attempts:** 3
- **Action:** Session suspended. Raw notified via WhatsApp.
- **Notes:** Sender persisted after initial rejection.
-->
