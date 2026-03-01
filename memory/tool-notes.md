# Tool Notes — Quirks, Gotchas & Pi5 ARM64 Specifics

> Practical tool knowledge from real usage. Updated after engagements.
> Supplements TOOLS.md with experiential findings.

## Known Pi5 ARM64 Issues

- **certipy-ad:** Crashes on aarch64 when domain has >500 certificate templates.
  Workaround: use `--timeout 120` flag. If still crashes, use `certipy find` with
  limited scope instead of full enumeration.

- **responder:** On aarch64, may require python3.11+ explicitly. If responder fails
  to start, check Python version and install from source if needed.

- **nmap:** Avoid `-sT` (TCP connect scan) on Pi5 — significantly slower than `-sS`
  (SYN scan). Always prefer `-sS` with root privileges.

- **bloodhound-python:** Use `--timeout 120` for large domains (>1000 objects).
  Memory-intensive on 8GB Pi5 — monitor RAM during collection.
  For very large environments, use `-c DCOnly` first, then targeted collection.

- **masscan:** Acceptable on Pi5 for external scans. For internal, prefer nmap
  with `--min-rate 3000` — less noisy, more accurate service detection.

## Tool Version Notes

<!-- Track which versions work reliably on aarch64 -->

| Tool | Working Version | Notes |
|------|----------------|-------|
| — | — | No field data yet |

## Undocumented Flags & Tricks

<!-- Useful flag combinations discovered through practice -->
