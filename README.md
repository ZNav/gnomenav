# gnomenav

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
![Services](https://img.shields.io/badge/services-30%2B-blue)
![Edge](https://img.shields.io/badge/edge-Cloudflare%20Zero%20Trust-orange)
![Status](https://img.shields.io/website?url=https%3A%2F%2Fgnomenav.com&label=gnomenav.com)

Self-hosted homelab orchestration powering [`gnomenav.com`](https://gnomenav.com).
30+ services on docker-compose across two hosts, gated by Cloudflare Zero Trust
tunnels, with a single CLI dispatcher (`nav`) for ops from anywhere.

> Built on the principle that infrastructure should answer to the operator,
> not the other way around. Every byte stays on hardware I own.

## Latest writing

- **2026-05-07** — [What broke when I came back: 4 failure modes from a homelab cold boot](writeups/2026-05-07-cold-boot-recovery.md)

See [`WRITEUPS.md`](WRITEUPS.md) for the full index.

## Topology

```
┌─────────────────────────┐         ┌─────────────────────────┐
│  msi  (Arch, 5800H)     │  NFS    │  x220  (Debian 13, i7)  │
│  /home/znav/nas/        │◄───────►│  /home/x220-edge/nas/   │
│  • compose stack        │         │  • NFS server           │
│  • cloudflared tunnel   │         │  • novelty CLI box      │
│  • mailserver           │         │  • offline kiwix host   │
└──────────┬──────────────┘         └─────────────────────────┘
           │
           ▼  Cloudflare Zero Trust
   ┌──────────────────────────────────────────┐
   │ gnomenav.com / *.gnomenav.com (public)   │
   │ ssh.gnomenav.com (Access SSO-gated)      │
   └──────────────────────────────────────────┘
```

See [`docs/topology.md`](docs/topology.md) for the full service map.

## Stack

| Layer | Tools |
|---|---|
| Orchestration | Docker Compose (single-file, 30+ services) |
| Edge | Cloudflare Zero Trust tunnels + Access apps |
| VPN | WireGuard (Mullvad) for the *arr / qBittorrent stack only |
| Storage | NFS over LAN, x220 NAS exporting to msi at `/mnt/x220` |
| Mail | docker-mailserver + Roundcube + CF Email Routing → Gmail |
| DNS | AdGuard Home (network-wide blocking) |
| Knowledge | Wiki.js (couple-collab), Kiwix (offline Wikipedia) |
| Ops | `bin/nav` shell dispatcher (status / restart / logs / files / read / etc.) |

## Repository layout

```
compose/docker-compose.yml      # full service stack — secrets via ${VARS}
.env.example                    # template for .env (real .env stays on msi)
bin/nav                         # ops dispatcher; lives at /usr/local/bin/nav
gnomenav-site/                  # static site served at gnomenav.com (nginx)
wikijs/wargames-theme.css       # phosphor-green CRT theme for Wiki.js admin UI
docs/
  topology.md                   # services, ports, hosts, Cloudflare routes
  cold-boot-recovery.md         # what breaks after a power cycle and how to fix
  cf-tunnel-routes.md           # tunnel ingress map (dashboard reference)
  ssh-access.md                 # tunnel + LAN paths, cloudflared client setup
```

## Bootstrap on a fresh host

1. Install Docker + Compose plugin.
2. Clone this repo to the compose root: `git clone … /opt/homelab && cd /opt/homelab`
3. Copy `.env.example` → `.env`, fill in real values (CF tunnel token, WG creds,
   DB passwords). Never commit `.env`.
4. NFS mount the x220 export to `/mnt/x220` (see [`docs/cold-boot-recovery.md`](docs/cold-boot-recovery.md)
   for the `x-systemd.automount` fstab pattern that survives boot-order races).
5. `docker compose -f compose/docker-compose.yml up -d`
6. Install the `nav` dispatcher: `sudo install -m755 bin/nav /usr/local/bin/nav`

## Operations

```
nav status              # uptime, disk, memory, container state
nav restart <svc>       # restart any compose service
nav logs <svc> [-f]     # tail logs
nav update              # pacman/apt + docker pull + recreate
nav health              # cloudflared + public endpoint probe
nav reboot [msi|x220]   # full host reboot via SSH
nav files               # yazi TUI file browser
nav read [book]         # epy ebook reader
nav dash                # lazydocker
```

Full subcommand list: `nav --help`.

## License

All original code in this repository is dual-licensed MIT / public domain
(at the user's choice). Third-party container images retain their own licenses.
