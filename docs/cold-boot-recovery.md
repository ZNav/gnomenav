# Cold-boot recovery

What breaks after a power cycle, and how to fix it. Lessons accumulated from
real reboots — most recently 2026-05-05.

## 1. NFS mount silently skipped

**Symptom**: `/mnt/x220` empty on msi after boot; `nav status` shows the mount
missing; jellyfin / kavita / *arr can't see media.

**Root cause**: msi boots faster than x220, so the NFS server isn't responsive
when systemd tries the mount. With `nofail` set in fstab, the mount silently
fails and never retries.

**Fix (one-time)**: switch from `nofail` → `x-systemd.automount`. The mount is
deferred until the path is first accessed, by which time x220 is up.

```fstab
10.0.0.138:/home/x220-edge/nas /mnt/x220 nfs \
  defaults,_netdev,nofail,vers=3,noauto,x-systemd.automount,x-systemd.idle-timeout=600 \
  0 0
```

`systemctl daemon-reload` after editing.

## 2. AdGuard port-53 bind fails on IP drift

**Symptom**: `adguard.gnomenav.com` returns 502; container is in restart loop;
`docker logs adguardhome` shows `failed to bind host port 10.0.0.176:53/tcp`.

**Root cause**: AdGuard's compose block had `10.0.0.176:53:53/tcp` and `:53/udp`
host bindings. When MSI's IP drifts to `10.0.0.172` after a DHCP cycle, those
bindings become invalid; the port-bind failure prevents the container from
attaching to the network at all.

**Fix (current)**: both `53/tcp` and `53/udp` host bindings commented out
2026-05-05. Web UI on `:3000` still works through Cloudflare tunnel. AdGuard
isn't currently the LAN DNS resolver (router still points to ISP DNS).

**Re-enable conditions**:
1. Router DHCP reservation pinning MSI to a stable IP, AND
2. systemd-resolved on host released from `:53` (it currently binds
   `127.0.0.53:53` for stub resolver) — otherwise `0.0.0.0:53` fights it.

## 3. Cloudflare tunnel ingress drift

**Symptom**: `crucix.gnomenav.com` and `worldmonitor.gnomenav.com` return 502
or DNS errors after MSI's IP changes.

**Root cause**: Tunnel ingress configured on Cloudflare dashboard side as
`tcp://10.0.0.176:3117` / `tcp://10.0.0.176:3005`. When MSI's IP drifts, those
become unreachable. (Other ingresses like `wiki` use container DNS like
`http://wikijs:3000` and survive the drift.)

**Fix**: change ingress to use docker DNS:
- `crucix.gnomenav.com` → `http://crucix:3117`
- `worldmonitor.gnomenav.com` → `http://worldmonitor:8080` (note: published on
  host as :3005, but internal container port is 8080)

Done via Cloudflare Zero Trust dashboard → Tunnels → Public Hostnames.

## 4. Compose / running-container divergence

**Symptom**: `docker compose ps` shows fewer services than `docker ps`. Running
`docker compose up -d --remove-orphans` would silently delete services that
never made it into the compose file.

**Background**: As of 2026-05-07, 8 containers run with `project=nas` label
but their service definitions are missing from `compose/docker-compose.yml`:
roundcube, mailserver, cockpit-proxy, wanderer, wanderer-db, wanderer-meili,
navidrome, kavita. They survive because of `restart: unless-stopped` even
after host reboot, but they're not in source. (mindset-backend was the 9th —
killed 2026-05-07.)

**DO NOT run `docker compose up -d --remove-orphans` until either**:
- (a) those services are added back to `docker-compose.yml`, OR
- (b) you actually intend to remove them.

(`navidrome` and `kavita` _are_ defined in `test-stack.yml` — possibly the
historical source.)

## 5. VPN container recreated → arr services orphaned

**Symptom**: After `docker compose up -d vpn` (especially on a tag/version
bump), `sonarr`, `radarr`, `prowlarr`, `lidarr`, `readarr`, `qbittorrent` all
fail because their network namespace is gone (`network_mode: "service:vpn"`
breaks when the parent recreates).

**Fix**: explicitly recreate the dependent set:

```
docker compose up -d sonarr radarr prowlarr lidarr readarr qbittorrent
```

## Standard recovery sequence

```
ssh msi-wifi               # or `ssh msi` over CF tunnel from anywhere
nav status                 # see what's up / down
ls /mnt/x220               # confirm NFS mount populated
nav restart cloudflared    # if public endpoints down
nav health                 # hit each public URL, see codes
nav logs <broken-svc>      # dig into specific failures
```
