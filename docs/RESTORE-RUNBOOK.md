# msi RESTORE RUNBOOK — post-nixos-anywhere, 2026-07-18

Executed after the wipe/install of msi (NixOS, flake `#msi`), driven from the Mac
(or x220). Source of truth for all data: **SanDisk 2TB, `/mnt/sandisk/backup-msi-20260718/`**.

## ⚠ READ FIRST — three loud flags

1. **BLOG + WIKI (wife's ghost/wikijs) HAVE NO NixOS MODULES.** The repo's
   oci-containers do NOT define ghost or wikijs. Their definitions live only in
   the restored `nas/docker-compose.yml`. They come back ONLY via step 7e
   (compose under podman) or by writing new oci-container modules. Until then
   blog.gnomenav.com and wiki.gnomenav.com are DOWN. Restore their data dirs
   byte-exact (step 5/6); do not "clean up" anything under them.
2. **The SanDisk is the ONLY copy of 702G.** Mount it READ-ONLY, always. No
   writes, no repurposing, no reformat, until msi is verified stable AND a
   second copy exists. The drive also carries an untouchable 2025 snapshot and
   secrets files at its top level — never index, copy to vault, or delete those.
3. **First boot starts containers against EMPTY dirs.** They will initialize
   fresh state (nextcloud installs a fresh html tree, DBs init, etc.). Stop all
   containers (step 1d) BEFORE restoring, and move fresh-init state aside
   (step 6b) — never rsync old data over a fresh init.

---

## 1. First-boot sanity

IP is a DHCP lease — was 10.0.0.170, re-discover if quiet. Host key changed.
User is now `z` (uid 1000, key = Mac's ed25519, passwordless sudo). The Mac's
`msi-wifi` ssh alias still says `User znav` — use `z@IP` explicitly.

```bash
# on the Mac
MSI=10.0.0.170                      # adjust after `nmap -sn 10.0.0.0/24` if needed
ssh-keygen -R $MSI; ssh-keygen -R msi-wifi
ssh z@$MSI hostname                 # expect: msi
```

```bash
# on msi
systemctl --failed
# EXPECTED failures at this point: units consuming sops secrets (cloudflared,
# nextcloud*, immich*, openclaw, spotdl-sync) — the age key isn't installed yet.
# Anything else failing: investigate before proceeding.

# tmpfiles skeletons from modules/users.nix:
ls -la /data /var/lib/appdata
stat -c '%U:%G %a %n' /data /data/media /data/kiwix /data/knowledge   # z:media
stat -c '%U:%G %a %n' /var/lib/appdata/jellyfin /var/lib/appdata/sonarr
# jellyfin=root:root 755, sonarr=z:media 750 per users.nix — if /data or
# /var/lib/appdata are missing, stop: the config that booted isn't this repo's.
```

1d. **Stop every container now** (see flag 3):

```bash
sudo systemctl stop 'podman-*'
podman ps            # must be empty
```

## 2. sops age key install + verify

Private key lives on the Mac at `~/.config/sops/age/msi-host.txt`. Never lands in git.

```bash
# on the Mac — key goes over ssh stdin, no temp copies
ssh z@$MSI 'sudo install -d -m 700 /var/lib/sops-nix &&
            sudo install -m 600 -o root -g root /dev/stdin /var/lib/sops-nix/key.txt' \
  < ~/.config/sops/age/msi-host.txt
```

```bash
# on msi — re-run activation so sops-nix decrypts, then verify
sudo /run/current-system/activate
sudo ls -la /run/secrets/
# expect: anthropic_api_key cloudflared_token immich_db_password
#         nextcloud_db_password spotify_env telegram_bot_token
sudo head -c 13 /run/secrets/cloudflared_token; echo
# expect literally: TUNNEL_TOKEN=   (it's an env-file, not a bare token —
# if it's a bare token the tunnel will NOT start; fix secrets.yaml on the Mac,
# re-encrypt, rebuild)
```

## 3. Replug SanDisk, mount READ-ONLY

Zander physically replugs the drive (use the good 10Gbps cable).

```bash
# on msi
lsblk -f                                    # find the 2TB ext4 partition (was sdc1)
sudo mkdir -p /mnt/sandisk
sudo mount -o ro /dev/sdX1 /mnt/sandisk     # <-- substitute real device. RO. Always RO.
ls /mnt/sandisk/backup-msi-20260718/        # the 702G tree
ls /mnt/sandisk/backup-msi-20260718/msi-system-sweep-20260718/  # dotfiles tar + pkglist
```

## 4. Restore mapping (the whole point)

Old world: everything under `/home/znav/nas/` (= `backup-msi-20260718/` on the
SanDisk), appdata and media mixed. New world: data under `gnomenav.dataRoot=/data`,
container config under `gnomenav.configRoot=/var/lib/appdata/<service>`.
Everything not consumed by a NixOS module parks byte-exact at `/home/znav/nas/`
(the old absolute path — the compose file's volume mounts reference it literally).

`B=/mnt/sandisk/backup-msi-20260718` below. **Run `ls -la $B/` first and
reconcile actual dir names against this table** — names marked (verify) were
not eyeballed on the backup.

| old (`$B/…`) | new path | notes |
|---|---|---|
| `media/` | `/data/media/` | 121G photos live inside; jellyfin/navidrome/kavita/arr all read here |
| `downloads/` | `/data/downloads/` | arr golden rule: `/data` mounted whole in arr+qbit |
| `kiwix/` (verify) | `/data/kiwix/` | data lands on msi; the kiwix *container* is utility-role (x220) in web.nix — serving comes later |
| `files/` (Takeout) | `/data/files/` | no module consumes it yet; keep under dataRoot |
| `nextcloud/` — its `data/` subdir | `/data/nextcloud/` | see split note below |
| `nextcloud/` — html (config.php, apps, themes…) | `/var/lib/appdata/nextcloud/html/` | see split note below |
| nextcloud mariadb dir (verify name: `nextcloud-db/`, `mariadb/`, or inside `nextcloud/`) | `/var/lib/appdata/nextcloud/db/` | `MARIADB_AUTO_UPGRADE=1` handles version jump to mariadb:11 |
| `jellyfin/` | `/var/lib/appdata/jellyfin/` | library paths inside its DB may reference old container paths — remap in UI if libraries show missing |
| `navidrome/` (verify) | `/var/lib/appdata/navidrome/` | container mounts this at `/data` internally |
| `kavita/` (verify) | `/var/lib/appdata/kavita/` | includes the 2026-07-14-repaired DB; same UI-path caveat as jellyfin |
| `qbittorrent/` | `/var/lib/appdata/qbittorrent/` | |
| `sonarr/` `radarr/` `lidarr/` `readarr/` `prowlarr/` `recyclarr/` `spotdl/` (verify each) | `/var/lib/appdata/<same>/` | arr DBs store root-folder paths — if old mounts weren't `/data`, fix root folders in each UI after bring-up |
| `open-webui/` | `/var/lib/appdata/open-webui/` | |
| `ollama/` | **park** `/home/znav/nas/ollama/` | ollama blobs are NOT gguf; llama.cpp needs `Qwen3.5-9B-Q4_K_M.gguf` downloaded fresh into `/var/lib/appdata/llm/models/` |
| — (none) | `/var/lib/appdata/immich/*`, `/data/immich/` | immich is NEW — no old data; keep its fresh init |
| — (none) | `/var/lib/appdata/khoj/`, `/data/vectors/`, `/data/knowledge/` | khoj/qdrant NEW — nothing to restore |
| `ghost/` | `/home/znav/nas/ghost/` | **CRITICAL, wife's blog** — byte-exact, no module exists (flag 1) |
| `wikijs/` (+ its db dir if separate, verify) | `/home/znav/nas/wikijs/` (+ db alongside) | **CRITICAL, wife's wiki** — byte-exact, no module exists (flag 1) |
| `docker-compose.yml`, `.env`, `adguardhome/`, `beets/`, `homepage/`, `glance/`, `wanderer/`, `crucix/`, `gnomenav-backend/`, `worldmonitor/`, `mailserver/`, everything else | `/home/znav/nas/<same>` | catch-all park. `.env` holds secrets — stays on-host, NEVER into git or vault. adguard is destined for x220 later |

**Nextcloud split**: inspect first — `ls $B/nextcloud/`. If it contains
`config.php` (or `config/` + `apps/` + `data/`), it's the html tree: `data/`
goes to `/data/nextcloud/`, the rest to `/var/lib/appdata/nextcloud/html/`.
If it's only user files (no config.php), it's the data dir: all of it to
`/data/nextcloud/`, and the html tree gets a fresh install (nextcloud
reinstalls against the restored DB — check `version` compatibility in that case).

## 5. Ownership — read, don't act

- The entire nas tree is 1000:1000 on the backup; `rsync -a --numeric-ids` run
  as root preserves that, and the registry pins `z`/`media` at 1000:1000
  (users.nix HARD CONSTRAINT). **No chown of media/nas data. Ever. That's the
  whole design.**
- lscr containers (qbit/arrs/recyclarr) self-chown their `/config` to PUID on
  first start — restored config dirs need nothing.
- Official-image services (jellyfin, nextcloud, navidrome, kavita) ran as root
  under Arch docker and still run as root in phase 1 — restored root-owned
  config dirs are correct as-is. Uid split to 3100+ is phase 2, post-stability.

## 6. Rsync — additive, detached, logged

6a. Create the park dir (user z's home is `/home/z`; `/home/znav` is created
manually because the compose file hardcodes it):

```bash
# on msi
sudo install -d -o z -g media -m 755 /home/znav /home/znav/nas
```

6b. Move fresh-init state aside for every restore target a container already
touched (from the pre-stop window at first boot):

```bash
# on msi — flags non-empty appdata dirs that are about to receive restored data
for d in nextcloud/db nextcloud/html jellyfin navidrome kavita qbittorrent \
         sonarr radarr lidarr readarr prowlarr recyclarr spotdl open-webui; do
  t=/var/lib/appdata/$d
  [ -d "$t" ] && [ -n "$(sudo ls -A "$t" 2>/dev/null)" ] && \
    sudo mv "$t" "$t.freshinit" && sudo mkdir -p "$t"
done
# .freshinit dirs are junk from the empty first boot — deleteable once the
# service verifies. Do NOT do this to immich/khoj/qdrant dirs (their init is real).
```

6c. Write the restore script. **Adjust the MAP lines to match `ls $B/` and the
nextcloud split you determined in step 4** — missing sources are skipped and
logged, not fatal.

```bash
# on msi
sudo tee /tmp/restore.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -u
B=/mnt/sandisk/backup-msi-20260718
LOG=/tmp/restore-20260718.log
R="rsync -a --numeric-ids --info=progress2"     # additive. NO --delete, ever.
MAP=(
  "media/                /data/media/"
  "downloads/            /data/downloads/"
  "kiwix/                /data/kiwix/"
  "files/                /data/files/"
  # nextcloud: EDIT per step-4 split — example assumes $B/nextcloud is the html tree:
  "nextcloud/data/       /data/nextcloud/"
  "nextcloud/            /var/lib/appdata/nextcloud/html/ --exclude=data/"
  # "nextcloud-db/       /var/lib/appdata/nextcloud/db/"   # verify real name first
  "jellyfin/             /var/lib/appdata/jellyfin/"
  "navidrome/            /var/lib/appdata/navidrome/"
  "kavita/               /var/lib/appdata/kavita/"
  "qbittorrent/          /var/lib/appdata/qbittorrent/"
  "sonarr/               /var/lib/appdata/sonarr/"
  "radarr/               /var/lib/appdata/radarr/"
  "lidarr/               /var/lib/appdata/lidarr/"
  "readarr/              /var/lib/appdata/readarr/"
  "prowlarr/             /var/lib/appdata/prowlarr/"
  "recyclarr/            /var/lib/appdata/recyclarr/"
  "spotdl/               /var/lib/appdata/spotdl/"
  "open-webui/           /var/lib/appdata/open-webui/"
)
for m in "${MAP[@]}"; do
  set -- $m; src="$B/$1"; dst="$2"; shift 2; extra="$*"
  if [ -e "$src" ]; then
    echo "=== $src -> $dst" >>"$LOG"
    mkdir -p "$dst" && $R $extra "$src" "$dst" >>"$LOG" 2>&1 || { echo "FAILED $src" >>"$LOG"; exit 1; }
  else
    echo "SKIP (missing) $src" >>"$LOG"
  fi
done
# catch-all: everything not mapped above parks at /home/znav/nas (ghost, wikijs,
# compose, .env, adguardhome, beets, wanderer, crucix, worldmonitor, ...)
echo "=== catch-all -> /home/znav/nas/" >>"$LOG"
$R "$B/" /home/znav/nas/ \
  --exclude=media/ --exclude=downloads/ --exclude=kiwix/ --exclude=files/ \
  --exclude=nextcloud/ --exclude=nextcloud-db/ \
  --exclude=jellyfin/ --exclude=navidrome/ --exclude=kavita/ \
  --exclude=qbittorrent/ --exclude=sonarr/ --exclude=radarr/ --exclude=lidarr/ \
  --exclude=readarr/ --exclude=prowlarr/ --exclude=recyclarr/ --exclude=spotdl/ \
  --exclude=open-webui/ --exclude=msi-system-sweep-20260718/ \
  >>"$LOG" 2>&1 || { echo "FAILED catch-all" >>"$LOG"; exit 1; }
echo ALLDONE >>"$LOG"
EOF
sudo chmod +x /tmp/restore.sh
```

6d. Launch detached (the ssh-wrapper stall gotcha: fully detach, then close the
session — never babysit a long rsync through an interactive ssh):

```bash
# on msi
sudo bash -c 'nohup /tmp/restore.sh >/dev/null 2>&1 & disown'
```

```bash
# from the Mac — poll; ~20-40 min for 700G on the 10Gbps cable
ssh z@$MSI "tr '\r' '\n' < /tmp/restore-20260718.log | tail -3"
# done when the last line is ALLDONE. Any FAILED line: read the log, fix, re-run
# /tmp/restore.sh — it's additive and idempotent.
```

6e. Sanity after ALLDONE:

```bash
# on msi
du -sh /data/media /data/nextcloud /home/znav/nas
find /data/media/photos -type f | wc -l     # expect 67861
sudo umount /mnt/sandisk                    # clean unmount; drive stays plugged, untouched
```

## 7. Bring-up + verification

7a. Reboot — cleanest way to exercise real unit ordering (dependsOn already
serializes db→app: immich-db/redis before immich-server, nextcloud-db/redis
before nextcloud, llamacpp before open-webui, qdrant before khoj):

```bash
sudo reboot
# then, after ~2 min:
ssh z@$MSI 'systemctl --failed; podman ps --format "{{.Names}} {{.Status}}"'
# llamacpp will crash-loop until its gguf exists — expected; see the ollama row in step 4.
```

7b. Cloudflared tunnel. Secret name is `cloudflared_token`
(modules/cloudflared.nix); secrets.yaml must contain it as a full env-file line
`TUNNEL_TOKEN=<token>` (verified in step 2). Ingress is DASHBOARD-managed:

```bash
journalctl -u podman-cloudflared -n 20 --no-pager   # want "Registered tunnel connection"
```

7c. Per-service HTTP (from the Mac — through Cloudflare, the real path):

```bash
for h in gnomenav.com jellyfin.gnomenav.com music.gnomenav.com books.gnomenav.com \
         nextcloud.gnomenav.com llm.gnomenav.com blog.gnomenav.com wiki.gnomenav.com; do
  printf '%-28s %s\n' "$h" "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://$h/")"
done
```

Expected at this stage: jellyfin/music/books/nextcloud/llm → 200 (or 302).
**blog/wiki → 502 until step 7e. gnomenav.com → 502 until the parked compose
site (gnomenav-site/homepage) returns — the homepage module is utility-role
(x220), not msi.** If EVERYTHING 502s while containers run fine locally, the
dashboard ingress likely targets old names/networks (possibly a `caddy` that
only exists in the parked compose) — check Zero Trust > Networks > Tunnels and
point hostnames at the new container names on the tunnel's network.

7d. Local-first debugging for any 502: `podman exec cloudflared wget -qO- http://jellyfin:8096` etc.

7e. **Blog + wiki (the gap from flag 1).** Two options; pick one tonight:

```bash
# Option A — compose under podman (fast path):
cd /home/znav/nas
nix shell nixpkgs#podman-compose -c podman-compose up -d ghost wikijs wikijs-db  # names per the compose file — check it first
# make them reachable from cloudflared (they're on the compose net, tunnel is on 'proxy'):
podman network connect proxy ghost && podman network connect proxy wikijs
# re-check blog./wiki. in 7c. Note: compose drift is documented — the file may
# not match last-known-running config exactly; verify wife signs off on both sites.
```
Option B — write real oci-container modules for ghost/wikijs (correct long-term,
not a tonight job). Either way: record which one happened in the vault.

7f. Full-tree verify pass once services look right: log into jellyfin (libraries
present?), navidrome (music plays?), kavita (books load?), nextcloud (files +
existing users log in?), one arr (root folders valid?).

## 8. Rollback / abort

- **First boot fails / unreachable**: nothing is lost — the SanDisk is
  unplugged and untouched. Re-running nixos-anywhere from the x220 is SAFE any
  number of times **before restore starts** (recreate `/tmp/disk.key` on the
  x220 each time; `--disk-encryption-keys /tmp/disk.key /tmp/disk.key`).
- **After restore has started**: do NOT re-run disko/nixos-anywhere casually —
  it wipes the restored data and forces a full re-restore from the sole copy.
  Config-level problems get fixed with `nixos-rebuild switch`, not a reinstall.
- **Mid-restore rsync failure**: additive + idempotent — fix cause, re-run
  `/tmp/restore.sh`.
- **The SanDisk remains the ONLY copy until msi is verified stable** (services
  up, wife's sites confirmed, a few days of runtime). Until then: no writes, no
  repurposing, ro mounts only, physically safe storage. After stability, it
  stays cold-storage until a second backup target exists — then and only then
  may it be reused, and never the 2025 snapshot or top-level secrets files.
