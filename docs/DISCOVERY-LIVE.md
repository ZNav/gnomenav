# Live discovery — captured 2026-07-14 via SSH (real state, not assumptions)

## Hosts
| Host | Alias | IP | OS | Disk | Encryption |
|---|---|---|---|---|---|
| msi | `msi-wifi` | 10.0.0.170 | Arch (kernel 6.17) | Micron 953G NVMe | **LUKS + btrfs** (subvols @, @home, @log, @pkg; snapper snapshots) |
| x220 | `x220` | 10.0.0.138 | Debian 13 | Inland 953G SATA SSD | **LUKS + LVM + ext4** |

- **msi runs the entire live homelab** — 34 containers, master compose
  `/home/znav/nas/docker-compose.yml` (+ homepage/, + a windows VM compose).
- **x220 is the NAS**: exports `/home/x220-edge/nas` over NFS to `10.0.0.0/24`
  (`rw,no_root_squash`), mounted on msi at `/mnt/x220`. It also holds a partial
  older DUPLICATE of the homelab tree.
- Routing is a **Cloudflare Tunnel** container (`cloudflared-tunnel`), not NPM/Traefik.
- **WireGuard** container (`vpn`) present.

## Storage map (msi)
- Root btrfs, 703G/952G used. Nearly all service data under `/home/znav/nas/`.
- NFS from x220 at `/mnt/x220` (255G): kiwix zim, downloads, `files/` (Google Takeout).

## Sizes
| Path | Size | Class |
|---|---|---|
| msi `/home/znav/nas/media/photos` | **121G** | 🔴 PRECIOUS (family photos) |
| msi media movies/shows/music/books/porn/videos | ~391G | replaceable |
| msi `/home/znav/nas/nextcloud` | 1.2G | 🔴 precious |
| msi ghost (wife's blog) | 1.3M | 🔴 precious, DO NOT TOUCH |
| msi wanderer / crucix / gnomenav-backend | ~90M | 🔴 precious (custom apps) |
| x220 `nas/files` (Takeout) | 5.9G | 🔴 precious |
| x220 `nas/media` | 125G | duplicate/older copy of msi media |
| x220 `nas/nextcloud` | 1.3G | duplicate/older copy |
| x220 `nas/kiwix` | 116G | replaceable (re-downloadable Wikipedia zim) |

**Total irreplaceable set ≈ 130G** (dominated by photos). Everything else is
re-downloadable or a duplicate.

## The 34 containers (verdict vs earlier plan)
Live services beyond the original list, now accounted for:
- `ghost` = **blog.gnomenav.com** (wife's) — DO NOT TOUCH. Data: nas/ghost.
- `glance` + `homepage` = two dashboards; `gnomenav-site`+`gnomenav-backend` = the
  custom root site. Consolidate to ONE (Homepage) during overhaul; dash = glance.
- `wanderer` (+db, +meili) = self-hosted trail/GPS app (Strava-like). Keep, precious data.
- `crucix` = custom app (healthy). `worldmonitor` (+ais-relay,+redis,+redis-rest) =
  ship/AIS tracking (currently unhealthy).
- `mailserver` (docker-mailserver) + `roundcube` (exited) = mail — DEFERRED per you.
- `wikijs`+`wikijs-db` = wiki (keep). `ollama`+`open-webui` = LLM (currently Ollama;
  swap model to Qwen3.5-9B). `vpn` = wireguard (keep).
- Broken now: `kiwix` (exited 255), `spotdl` (exited 1), `kavita` (unhealthy),
  `cockpit-proxy` (exited 127), `roundcube` (exited 127).

## 🔴 Security issues found (act before anything else)
1. **Secrets in the NFS share**: `hacker1-recovery-kit.txt`, `proton-recovery-kit.pdf`,
   and `.env` sit in `/home/x220-edge/nas`, exported `rw` to the whole `/24` with
   **`no_root_squash`**. Any LAN device can read/overwrite them, as root. Move these
   out to an encrypted location; tighten `/etc/exports` to specific host IPs, drop
   `no_root_squash`, consider `ro` where possible.
2. `api.gnomenav.com` leakage audit still pending (do from off-LAN).

## Correction to the Nix plan
Both machines are ENCRYPTED. disko configs must reproduce that (LUKS + btrfs for
msi with subvolumes/snapper; LUKS + LVM + ext4 for x220) — NOT the plain-ext4
placeholders. And `/home/znav/nas` (703G, incl. 121G photos) lives on the same
disk we'd wipe, so a verified off-disk backup of the ~130G precious set is
mandatory before msi is touched.

## Update: compose drift (found 2026-07-14)
`/home/znav/nas/docker-compose.yml` does not define all running containers
(kavita among them) though their labels point back to it. The live stack has
drifted from the file. Treat the RUNNING containers (captured above) as the
source of truth for the NixOS translation, not the on-disk compose.
