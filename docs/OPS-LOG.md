# Ops log — live changes made via SSH (non-destructive phase)

## 2026-07-14
**Security (x220)**
- Moved exposed secrets OUT of the NFS-exported `nas/` share into
  `/home/x220-edge/secrets/` (mode 700, files 600):
  `hacker1-recovery-kit.txt`, `proton-recovery-kit.pdf`, `.env` (copied as
  `x220-nas.env`). Deleted stale `nohup.out`. NFS share confirmed clean of these.
- OUTSTANDING: `/etc/exports` still `rw,no_root_squash` to whole `10.0.0.0/24`.
  Recommend restricting to msi's IP (set a DHCP reservation first) + drop
  `no_root_squash`. Not auto-applied (risk to live container writes).

**kiwix (msi)** — was Exited(255). `docker start kiwix` → Up. Serving
`wikipedia_en_all_maxi_2026-02.zim`. restart policy already `unless-stopped`.

**kavita (msi)** — was unhealthy (373 failing healthchecks). Root cause: live
`kavita.db` was 24 KB (empty/corrupt, dated 2026-06-28) under an unpinned
`:latest` image. Fix:
- Stopped kavita, preserved broken db as `kavita.db.broken.<ts>`.
- Restored newest backup `kavita_backup_v0.8.9.1_05_12_2026...zip` → `kavita.db`
  (1.1 MB). Restarted → **healthy**, "Now listening on :5000".
- Known-good image digest to pin going forward:
  `jvmilazz0/kavita@sha256:1f2acae7466d022f037ea09f7989eb7c487f916b881174c7a6de33dbfa8acb39`
- NOTE: non-fatal LibraryWatcher warning — one Kavita library path is missing;
  re-point it in the Kavita UI (Settings → Libraries).

**Findings (not changed)**
- ollama container has NO `/dev/dri` → LLM is CPU-only. Only `dolphin3`,
  `dolphin-llama3` present (no Chinese model). Plan: llama.cpp Vulkan + Qwen3.5-9B.
- spotdl Exited(1): "blocked by YouTube Music". Fix = route through the `vpn`
  (wireguard) container or switch audio provider (`--audio piped`). Not applied
  (compose drift, see below).
- **COMPOSE DRIFT**: `/home/znav/nas/docker-compose.yml` no longer defines several
  running services (e.g. kavita). Running stack ≠ file on disk. Do NOT hand-edit
  the live file; the NixOS migration makes the declared state authoritative.

## 2026-07-14 (later) — books.gnomenav.com 502 fixed
Second, separate fault (beyond the corrupt DB): `kavita` container was on **no
Docker network**, so `cloudflared-tunnel` (dashboard/token-managed) got
`lookup kavita ... no such host` → HTTP 502 externally.
- Fix: `docker network connect nas_nas_media-lan kavita` (the net jellyfin/
  navidrome/cloudflared share). External `books.gnomenav.com` → **200**.
- Durability: survives restart/reboot, but a `docker rm`+recreate would re-orphan
  it (compose drift — kavita isn't in the compose). NixOS `media.nix` already
  pins kavita on the `proxy` network declaratively, which prevents recurrence.

## 2026-07-14 (evening) — gnomenav.com site deployed; dash.gnomenav.com fixed
- **gnomenav.com**: replaced the "renovating" placeholder with the real static
  site (repo `gnomenav`, `gnomenav-site/`, commit 31a0566). Placeholder backed
  up to msi `~/nas/gnomenav-site.bak-20260714`. Deploy method (banked): dir is
  root-owned → `rsync -a --rsync-path="sudo rsync" gnomenav-site/ msi-wifi:nas/gnomenav-site/`;
  nginx picks up instantly. Landing + writeups all 200.
- **dash.gnomenav.com** (glance): dashboard rendered empty-looking to curl —
  glance lazy-loads content; the real render is at
  `/api/pages/<slug>/content/` (banked: probe THAT, not the shell page).
  Actual faults fixed in `~/nas/glance/config/glance.yml` (backup:
  `glance.yml.bak-20260714`):
  1. Monitor/bookmark URLs pointed at `http://10.0.0.170:<port>`. The *arr
     ports route through the wireguard `vpn` container whose policy routing
     replies to LAN clients out the tunnel → connections from LAN hang
     (localhost works, LAN IP doesn't). Swapped all widget URLs to the public
     `https://*.gnomenav.com` hostnames — works on and off LAN. (Did NOT
     touch vpn routing: box gets rebuilt; NixOS config will own it.)
  2. Weather widget: `Sarasota, Florida` fails geocoding → `Sarasota,
     Florida, United States`.
  3. Sonarr shows 401 (auth wall) as error → `alt-status-codes: [401]`.
  All 9 monitors green after `docker restart glance`.

## 2026-07-14 (late evening) — Cloudflare ingress fixes + prune (via API)

- Token (account-owned, audit scopes + Tunnel:Edit added mid-session) at
  `~/.config/cloudflare/api-token` on the Mac. Working method: account tokens
  verify at `/accounts/{id}/tokens/verify`; full `cfat_...` string as Bearer.
- Ingress v76 → v77 (backup: `~/.config/cloudflare/tunnel-ingress-backup-2026-07-14.json`):
  - adguard.gnomenav.com: `adguardhome:3000` (setup-wizard port, 502) → `adguardhome:80` — now 200.
  - crucix.gnomenav.com: stale `10.0.0.176:3117` → `crucix:3117` (docker alias on nas_nas_media-lan) — now 200.
  - worldmonitor.gnomenav.com: stale `10.0.0.176:3005` → `worldmonitor:8080` — now 200.
  - Removed dead entries: readarr, navidrome-test, kavita-test, spotdl, netdata → all 404 (catch-all).
- Verified post-change: blog/wiki (hands-off) + apex/dash/jellyfin all 200.
- Residue: the 5 pruned CNAMEs still exist in DNS (token lacks DNS:Edit — they
  resolve to the tunnel and 404; inert). Delete when scope is added.
- NOT done (Zander deferred): Cloudflare Access on admin apps — sonarr/radarr/
  lidarr/prowlarr/qbittorrent/portainer/adguard/cockpits remain publicly
  reachable; only app-native auth where enabled.
