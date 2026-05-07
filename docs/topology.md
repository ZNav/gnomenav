# Topology

## Hosts

| Host | OS | CPU / RAM | Role |
|---|---|---|---|
| `msi` | Arch Linux (rolling) | Ryzen 7 5800H / 16 GB | Compose host, all services |
| `x220` | Debian 13 (trixie) + limine + snapper | i7-2620M / 7.5 GB | NFS server, novelty CLI box, offline kiwix host |

**MSI IP drifts on DHCP** (last confirmed 2026-05-05): wired `enp6s0f4u1u1c2`
on 10.0.0.172, wifi `wlan0` on 10.0.0.175. Until a DHCP reservation is set on
the router, IP-pinned configs (AdGuard port-53 bind, some Cloudflare tunnel
ingresses) keep breaking on reboot. Use container DNS (e.g. `http://glance:8080`)
in tunnel ingresses, not host-IP+published-port.

## Service map (Cloudflare tunnel → container)

| Public URL | Container | Internal port | Notes |
|---|---|---|---|
| gnomenav.com / dash.gnomenav.com | glance | 8080 | dashboard |
| jellyfin.gnomenav.com | jellyfin | 8096 | |
| nextcloud.gnomenav.com | nextcloud | 80 | |
| llm.gnomenav.com | open-webui | 8080 | Ollama frontend |
| music.gnomenav.com | navidrome | 4533 | Subsonic API |
| books.gnomenav.com | kavita | 5000 | |
| memories.gnomenav.com | wanderer | 3000 | trip / memory journal |
| worldmonitor.gnomenav.com | worldmonitor | 8080 | geopolitical intel dashboard |
| crucix.gnomenav.com | crucix | 3117 | OSINT agent/monitor |
| mail.gnomenav.com | roundcube | 80 | Gmail IMAP frontend |
| adguard.gnomenav.com | adguardhome | 3000 | Web UI only; port 53 binding disabled |
| blog.gnomenav.com | ghost | 2368 | Ghost CMS |
| portainer.gnomenav.com | portainer | 9000 | |
| wiki.gnomenav.com | wikijs | 3000 | couple-shared Wiki.js |
| kiwix.gnomenav.com | kiwix | 8080 | offline Wikipedia (parked under compose profile) |
| ssh.gnomenav.com | host:22 (via 172.19.0.1) | 22 | SSH SSO-gated by CF Access |
| cockpit-msi.gnomenav.com | host:9090 (via 172.19.0.1) | 9090 | |
| cockpit-x220.gnomenav.com | 10.0.0.138:9090 | 9090 | direct, TLS verify off |

## VPN-routed services

The *arr stack and qBittorrent run with `network_mode: "service:vpn"` so all
their traffic exits via Mullvad WireGuard. **If the `vpn` container is ever
recreated, every dependent service must also be recreated**, otherwise their
network namespace is gone:

```
docker compose up -d sonarr radarr prowlarr lidarr readarr qbittorrent
```

Service ports for the VPN-attached containers are published on the `vpn`
container (so `8080` for qbit, `8989` for sonarr, etc. all exit on the VPN
container's localhost).

## Networks

| Network | Subnet | Role |
|---|---|---|
| `nas_media-lan` | 172.19.0.0/16 | main service mesh |
| `nas_torrent-vpn` | 172.21.0.0/16 | VPN-routed services |
| `nas_default` | dynamic | docker bridge default |

`172.19.0.1` is the docker bridge gateway = msi's host interface from inside
docker. Used for tunnel ingresses that need to reach a host service (sshd,
cockpit, netdata).

## Mail

- `mailserver` (docker-mailserver) handles SMTP for `@gnomenav.com`.
- Outbound: relayed via Gmail SMTP (ISP blocks port 25).
- Inbound: Cloudflare Email Routing forwards `*@gnomenav.com` → Gmail; Roundcube
  reads via Gmail IMAP.
- Self-signed TLS certs at `/home/znav/nas/mailserver/config/ssl/`.
- Accounts: `admin@`, `znav@`, `z@`.

## Pending

See [Homelab TODO](https://github.com/ZNav/homelab-infra/issues) (or your local
TODO memory) for outstanding work — DHCP reservation, router DNS to AdGuard,
backup mail relay VPS, etc.
