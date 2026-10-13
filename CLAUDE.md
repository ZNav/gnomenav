# gnomenav homelab — master context (read first)

Single source of truth for the homelab overhaul + NixOS migration + local AI.
If you're Claude Code picking this up: everything you need is here and in `docs/`.

## North star
Modular, professional, reproducible homelab across two machines. Consistent
styling, easy cross-linking, everything as code, disks/machines add/remove cleanly.
End state: NixOS (declarative) on both hosts, containers via podman oci-containers,
Cloudflare-fronted, plus a central data silo + local RAG assistant ("Jarvis").

## How to operate these machines
Runs as a command loop from a Mac that has SSH access + keys:
- `ssh msi-wifi`  → msi (10.0.0.170), Arch, **passwordless sudo**, wired gigabit.
- `ssh x220`      → x220 (10.0.0.138), **NixOS 26.05 desktop** (user `x220`,
  passwordless sudo, fish shell — pipe scripts via `ssh … bash -s <<'EOF'`).
- Both boxes can `ssh mac` (→ 10.0.0.106, user znav, key-auth; set up 2026-07-17/18).
- msi↔x220 direct ssh: keyed BOTH directions 2026-07-25, BatchMode-verified
  (x220 key in msi `~/.ssh/authorized_keys`; msi keypair generated + added on x220;
  x220 has a `Host msi` alias).
- All IPs are DHCP leases — re-discover if a host goes quiet.

## ⚠ 2026-07-18 REALITY UPDATE (overrides stale claims below)
The x220 was **wiped and reinstalled 2026-07-15** as a NixOS 26.05 Hyprland desktop
(see the vault: Active Priorities + 2026-07-15/16/17 journals). Consequences:
- The old Debian NAS, its NFS export, `/home/x220-edge/nas`, the **121G photo
  mirror, and `backup-msi-precious` are GONE.** Disk is ~6% used (~59G/938G).
- **DATA-SAFETY GATE: SATISFIED 2026-07-18** — full 702G nas verified on the
  SanDisk 2TB at msi `/mnt/sandisk/backup-msi-20260718/` (photos 67,861/120G
  identical, spot checksums clean). Single-copy by Zander's explicit decision.
  **That drive is the only backup: nothing writes to it, nobody unplugs it
  until msi is rebuilt and data restored.** Gate details + log: vault
  `Homelab/Migration Coordination`.
- msi's `/mnt/x220` NFS mount points at a dead export — don't trust or use it.
- Any statement below about x220-as-NAS, the NFS share, or "photos already
  mirrored" is **stale**.
- msi is additionally in a **partial-upgrade state** (binaries want glibc 2.43,
  system has 2.42 — node and jq are broken). Don't reboot msi casually; don't
  `pacman -Syu` without gating (live containers incl. the blog).

## HARD RULES
1. **Data safety gate**: `disko` wipes disks. NEVER wipe a host until its precious
   data (~130G, mostly 121G photos) is on another disk AND verified. Backups are
   **additive, no `--delete`** — never risk the only copy.
2. **Do NOT touch** `blog.gnomenav.com` (wife's Ghost blog) or `wiki.gnomenav.com`.
3. **No secrets in git.** sops-encrypted only. Real `.env`/age keys stay on-host.
4. Don't hand-edit the live `docker-compose.yml` — it has **drifted** from running
   state. Prefer the NixOS declarative config.

## Live infrastructure (discovered 2026-07-14, real)
| Host | OS | Disk | Encryption | Role |
|---|---|---|---|---|
| msi (`znav`) | Arch 6.17 | Micron 953G NVMe | **LUKS+btrfs** (@,@home,@log; snapper) | compute: runs all 34 containers |
| x220 | Debian 13 | Inland 953G SSD | **LUKS+LVM+ext4** | NAS: exports `/home/x220-edge/nas` (NFS) |

- Storage: msi data under `/home/znav/nas` (703G used, incl. 121G photos). x220 NFS
  at msi `/mnt/x220` (255G: kiwix 116G, files/Takeout 5.9G, media dup 125G).
- **x220 already mirrors the 121G photos** (verified byte-identical) + nextcloud.
- Routing: `cloudflared-tunnel` container, **token/dashboard-managed** (ingress
  lives in Cloudflare dashboard, not a local file). WireGuard `vpn` container present.
- Shared docker net for tunnel↔services: **`nas_nas_media-lan`**.
- Secrets on-host: msi `/home/znav/nas/.env` (WG + DuckDNS); x220 moved to
  `/home/x220-edge/secrets/` (was exposed in the NFS share — fixed).

### The 34 containers (highlights)
Media: jellyfin, navidrome, kavita, (no immich yet — photos are just files).
*arr: sonarr radarr lidarr prowlarr qbittorrent (+ spotdl exited). 
Docs/AI: nextcloud, wikijs(+db), ollama(+open-webui), kiwix.
Custom: gnomenav-site/backend, glance+homepage (2 dashboards), crucix,
worldmonitor(+ais-relay+redis+redis-rest), wanderer(+db+meili).
Mail (DEFERRED): mailserver, roundcube(exited). System: portainer, adguard, vpn.

## Decisions locked
- Email: **deferred** to phase 2.
- Both hosts → NixOS; **back-to-back, not simultaneous** (NAS serves while other rebuilds).
- Backup strategy: **x220↔msi dance** (x220 holds msi's precious during msi wipe, reverse after).
- Containers: **declarative oci-containers (podman)**.
- LLM: **Qwen3.5-9B via llama.cpp Vulkan** (RX 6700M). Ollama today is CPU-only.
- Central silo + **RAG** (not fine-tuning) for the local assistant. See docs/DATA-SILO-AND-JARVIS.md.

## Work completed (see docs/OPS-LOG.md for detail)
- Built this repo: flake, hosts (msi/x220), common (hardened SSH/Tailscale/firewall/
  sops/autoupgrade), oci-containers for all services, cloudflared, ai-silo, scripts.
- Live fixes (non-destructive): secured exposed secrets on x220; restarted kiwix;
  **fixed Kavita** (restored corrupt DB from backup + reconnected orphaned network →
  books.gnomenav.com now HTTP 200); pinned kavita image by digest in Nix.
- Verified 121G photos already mirrored on x220 (0 diffs). Staging remaining
  msi-only precious (nextcloud etc.) to `/mnt/x220/backup-msi-precious` (additive).

## Repo layout
```
flake.nix                 nixosConfigurations.msi / .x220
hosts/<h>/                default.nix + disko.nix + hardware-configuration.nix
modules/common.nix        hardened base
modules/containers/       oci-containers, split by role (+ ai-silo.nix)
modules/cloudflared.nix   tunnel ingress (version-controlled)
scripts/                  data-inventory, backup-precious, dedupe-plan,
                          spotdl-sync, recyclarr-sync, silo-index
docs/                     GOALS, SERVICES, DISCOVERY-LIVE, OPS-LOG,
                          DATA-SILO-AND-JARVIS, CLOUDFLARE, INSTALL_WALKTHROUGH,
                          GITHUB_SETUP, DATA_SAFETY, RUNBOOK, INDEX
```

## Roadmap (priority order, gates noted)
1. **Finish + verify** the msi precious backup to x220 (watch `/tmp/bkp-msi.log`
   for `ALLDONE`; confirm sizes). GATE for msi wipe.
2. **Correct disko** to reality before any install: msi = LUKS+btrfs+subvolumes;
   x220 = LUKS+LVM+ext4. (Current files are ext4 placeholders.)
3. **Push repo to GitHub** (private) + PR — see docs/GITHUB_SETUP.md.
4. **Cloudflare**: run plan-check; enable Access on admin apps; prune dead
   hostnames (dash, *-test, spotdl, ssh, crucix?, worldmonitor?). docs/CLOUDFLARE.md.
5. **Swap Ollama→llama.cpp Vulkan + Qwen3.5** (GPU); deploy Qdrant + silo; wire
   Open WebUI Knowledge / Khoj. docs/DATA-SILO-AND-JARVIS.md.
6. **Install NixOS** x220-then-msi (or msi-first per dance). docs/INSTALL_WALKTHROUGH.md.
   Dry-build (`nix flake check` + `--dry-run`) BEFORE wiping.
7. spotdl: route via `vpn` or `--audio piped` (YouTube-Music blocked it).

## Known gotchas
- compose drift (running ≠ file); token-managed tunnel (ingress in dashboard);
  NFS export is `rw,no_root_squash` to whole /24 (restrict after DHCP reservation
  for msi); kavita network was orphaned (fixed, but a `docker rm`+recreate re-orphans
  until NixOS owns it).
