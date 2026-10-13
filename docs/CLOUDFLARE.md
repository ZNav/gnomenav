# Maximize your Cloudflare — and prune/secure the hostnames

## API access (state as of 2026-07-14)

- Token on the Mac at `~/.config/cloudflare/api-token` (account id in
  `account-id` next to it). It is an **account-owned token** (`cfat_` prefix):
  verify it at `/accounts/{account_id}/tokens/verify` — the usual
  `/user/tokens/verify` returns "Invalid API Token" for these. Send the FULL
  string including the `cfat_` prefix as the Bearer.
- Plan: **Free Website** (zone `ee49cc0d40bbbb501b93a9221bb13f3d`).
  Tunnel `gnomenav` = `6068af9b-634c-428b-8cb9-8bced3aa7adf` (dashboard/token-managed;
  ingress lives in the tunnel *configurations* API, not DNS).
- Current scopes (probed empirically): Cloudflare Tunnel:Read + Zone:Read only.
  **Too weak to change anything** — DNS reads/writes and tunnel-config PUT both 401.
  To execute the approved fixes/prune, edit the token in the dash and add:
  Account → Cloudflare Tunnel → **Edit**, Zone → DNS → **Edit** (gnomenav.com),
  and (for the Access gate, when wanted) Account → Access: Apps & Policies → **Edit**.
- Live-ingress snapshot (version 76): `~/.config/cloudflare/tunnel-ingress-backup-2026-07-14.json`.
  Approved-but-unapplied new config: `~/.config/cloudflare/planned-ingress-2026-07-14.json`
  (adguard→`adguardhome:80`, crucix→`crucix:3117`, worldmonitor→`worldmonitor:8080`;
  removes readarr/navidrome-test/kavita-test/spotdl/netdata).

## First: what plan are you on? (you said "check for me")
Run these two, paste output back:
```bash
# Zone plan (Free/Pro/Business/Ent) — needs an API token with Zone:Read:
curl -s -H "Authorization: Bearer $CF_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones?name=gnomenav.com" \
  | jq '.result[] | {name, plan: .plan.name, status}'
# Zero Trust seats/plan:
#   Dash -> Zero Trust -> Settings -> Plans  (screenshot is fine)
```
Free tier already includes the things that matter for a homelab, so most of this
is *enabling*, not buying.

## Features to turn on (Free plan)
1. **Tunnel (cloudflared)** — every `*.gnomenav.com` reachable with **zero open
   ports**. Configured declaratively in `modules/cloudflared.nix`. Kills the need
   to port-forward and hides your home IP.
2. **Zero Trust Access** (free, 50 users) — SSO gate in front of admin apps.
   Policy: allow only your email(s) via **one-time PIN** (no IdP needed). Apply to:
   sonarr, radarr, lidarr, readarr, prowlarr, qbittorrent, portainer, adguard.
   Public (no gate): gnomenav.com, jellyfin, music, books, memories, nextcloud,
   llm, kiwix, wiki, blog.
3. **Access for SSH** — `ssh.gnomenav.com` becomes an Access-protected SSH app
   through the tunnel (browser or `cloudflared access ssh`). Combined with
   Tailscale SSH, delete the old self-hosted web-SSH entirely.
4. **WAF managed rules + rate limiting** — turn on the free managed ruleset; add a
   rate-limit rule on `/wp-login`, `/api`, login paths.
5. **Always Use HTTPS + HSTS + Full(strict) TLS** — SSL/TLS mode = Full (strict)
   since Caddy holds a real cert. Enable Automatic HTTPS Rewrites.
6. **DNS-01 wildcard** — one Cloudflare API token (Zone:DNS:Edit) issues the
   `*.gnomenav.com` cert in Caddy. No per-host certs.
7. **Bot Fight Mode, Email Obfuscation, Browser Integrity Check** — all free, on.
8. **Analytics + Logpush** — Free keeps 24h logs; fine for a homelab.

## If you're on Pro/Business (found by the check above)
- Pro: enable the **WAF managed rulesets** (OWASP), **image resizing/Polish** for
  the blog, more Page Rules, better bot analytics.
- Business: **custom WAF rules**, longer log retention, **Cloudflare Access with
  device posture**. I'll wire whichever the check reveals.

## Hostname prune (remove dead/dupe records — don't leave defaults)
DELETE these DNS records + tunnel routes + containers:
- `dash.gnomenav.com`         (replaced by Homepage on root)
- `navidrome-test.gnomenav.com`, `kavita-test.gnomenav.com`  (test dupes)
- `spotdl.gnomenav.com`       (now a cron job, no web UI)
- `crucix.gnomenav.com`, `worldmonitor.gnomenav.com`  (unless discovery finds a keeper)
- `ssh.gnomenav.com`          (replaced by Tailscale SSH + Access)
Command to list every record so nothing's missed:
```bash
curl -s -H "Authorization: Bearer $CF_API_TOKEN" \
 "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?per_page=200" \
 | jq -r '.result[] | "\(.type)\t\(.name)\t\(.content)\t\(.proxied)"' | sort
```
KEEP untouched: `blog.gnomenav.com` (wife's), `wiki.gnomenav.com`.

## "Don't leave defaults" checklist
- [ ] Every admin app behind Access (no anonymous admin surface)
- [ ] Every container app has auth enabled + password changed from default
- [ ] SSL/TLS = Full (strict), Always Use HTTPS on
- [ ] Old/test/dupe DNS records deleted
- [ ] Home IP not in any DNS record (all proxied/tunneled)
- [ ] API tokens scoped (DNS:Edit only; not Global API Key)
