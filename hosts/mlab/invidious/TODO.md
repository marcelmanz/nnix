# Invidious — YouTube blocker mitigation

Setup: Invidious backend (native NixOS service, port 9800) + invidious-companion
(podman, `--network=host`, port 8282). Both egress via the host network, so
host-level rotation / proxying covers both.

## Already in place

- IPv6 connectivity + `/64` subnet
- Source-address rotation: handled natively by networkd
  `IPv6PrivacyExtensions = "yes"` (`use_tempaddr=2`, new temporary address every
  24h). See "Rejected" below — no extra rotator needed.
- `channel_threads = 1` — re-enabled, needed to actually refresh subscriptions
- `feed_threads = 1` — RSS feeds for subscriptions (reliable)
- invidious-companion running, generates PO tokens
- Companion image kept current: `pull = "newer"` + weekly restart timer
  (`invidious-companion-update`). Previously stuck 5 months on the default
  `pull = "missing"` policy.
- Backend on 2026.08.04 (latest release as of 2026-09-20)

## Rejected: smart-ipv6-rotator

Was implemented in `ipv6-rotator.nix`, removed 2026-09-20. Three reasons:

1. Redundant. It rotates the source address within the host's `/64`, which is
   exactly what `IPv6PrivacyExtensions` already does, natively and with correct
   address lifetimes.
2. It did not work. `RemainAfterExit = true` + `OnUnitActiveSec` means the unit
   never leaves `active`, so the timer could never re-trigger it — it fired once
   and never again. networkd also flushed the address and routes it added.
3. No upside available anyway. The ISP hands out a single `/64` via RA, no prefix
   delegation, so nothing can rotate wider than that. Escaping a `/64`-level ban
   needs a bigger prefix from the ISP or a different egress path, not a rotator.

## TODO (priority order)

### 1. Ban / PO token monitoring

Catch blocks before users report them.

- Systemd timer running a journalctl grep for:
  `429|po.?token|playability|sign in to confirm|bot`
- Emit to the existing monitoring (homepage widget / gotify / matrix) on hit

### 2. Fallbacks (only if bans actually recur)

Do not pre-build these. Current logs show no 429 / PO token / ban signatures.

- **Residential proxy**: companion supports `HTTP_PROXY`/`HTTPS_PROXY` env.
  Split-tunnel so only YouTube egresses via the proxy.
- **WARP via wgcf**: coin flip, Cloudflare egress is increasingly flagged too.
- Do **not** route via a commercial VPN (PIA etc). Those exits are datacenter
  ASNs on every blocklist and get flagged on sight — strictly worse than the
  house IP.
