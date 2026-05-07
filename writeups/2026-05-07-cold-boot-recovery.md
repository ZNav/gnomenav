# What broke when I came back: 4 failure modes from a homelab cold boot

*2026-05-07 — first in a series on operating gnomenav.com*

I run a self-hosted stack at `gnomenav.com` — about 30 services on a single
Ryzen box (msi), with an old ThinkPad x220 hanging off it as an NFS server.
Jellyfin, Nextcloud, Wiki.js, mail server, an *arr stack behind a VPN, custom
dashboards, the whole thing fronted by Cloudflare Zero Trust tunnels.

Earlier this month the power went out for a while. When I came back and turned
everything on, **`gnomenav.com` returned 502**. Then I noticed `nextcloud`
worked but couldn't see my files. Then `adguard.gnomenav.com` was dead.

Four distinct things had broken on cold boot, each with a different root cause.
Here's what they were, how I diagnosed them, and what I changed so they don't
hit me the same way again.

## 1. NFS silently failing to mount

**Symptom:** `/mnt/x220` was empty on msi. Jellyfin showed an empty media
library. Kavita said "no books." The *arr containers logged "no such file or
directory" all over.

**Diagnosis:** msi boots faster than x220 (different hardware generations).
When systemd tried to mount the NFS share at boot, x220 wasn't responding yet.
With `nofail` set in `fstab`, the mount silently gave up — and never retried.

```bash
$ ssh msi df -h /mnt/x220
df: /mnt/x220: No such file or directory
$ grep x220 /etc/fstab
10.0.0.138:/home/x220-edge/nas /mnt/x220 nfs defaults,_netdev,nofail,vers=3 0 0
```

**Fix:** swap `nofail` for `x-systemd.automount`. The mount becomes a deferred
unit — systemd doesn't try to mount until something actually accesses
`/mnt/x220`, by which point x220 is up. The mount becomes self-healing.

```fstab
10.0.0.138:/home/x220-edge/nas /mnt/x220 nfs \
  defaults,_netdev,nofail,vers=3,noauto,x-systemd.automount,x-systemd.idle-timeout=600 \
  0 0
```

`systemctl daemon-reload`, then test by `ls /mnt/x220`. The mount unit fires
on access. Reboots no longer race x220.

## 2. AdGuard's port 53 bound to a stale IP

**Symptom:** `adguard.gnomenav.com` returned 502. `docker ps` showed
`adguardhome` in a restart loop.

**Diagnosis:** The compose block had AdGuard binding port 53 to a specific
host IP:

```yaml
adguardhome:
  ports:
    - "10.0.0.176:53:53/tcp"
    - "10.0.0.176:53:53/udp"
```

After the reboot, msi came up at `10.0.0.172` (wired) / `10.0.0.175` (wifi)
instead of the historical `10.0.0.176` it used to hold. DHCP, no reservation
on the router. The bind failed:

```
failed to bind host port 10.0.0.176:53/tcp: cannot assign requested address
```

That bind failure prevented the container from attaching to its network at
all — which is why the web UI was also unreachable, not just DNS. One bad
bind cascaded into total service death.

**Fix (immediate):** comment out the host bindings. AdGuard's web UI on
`:3000` still reaches it through the Cloudflare tunnel via container DNS.
Port-53 LAN-DNS-server mode goes back online once I either set a DHCP
reservation on the router or change the binding to `0.0.0.0:53` (and resolve
the conflict with `systemd-resolved`, which holds `127.0.0.53:53` on the
host's stub resolver).

```yaml
ports:
  # - "0.0.0.0:53:53/tcp" # disabled 2026-05-05: re-enable on stable IP
  # - "0.0.0.0:53:53/udp"
```

**Lesson:** *don't pin host IPs in compose unless you control the IP.* Every
service that binds a specific host IP becomes brittle on DHCP drift.

## 3. Cloudflare tunnel ingress drift

**Symptom:** `crucix.gnomenav.com` and `worldmonitor.gnomenav.com` returned
502 even though their containers were running fine.

**Diagnosis:** Same root cause as AdGuard, different layer. The Cloudflare
Zero Trust dashboard had ingress routes hardcoded as
`tcp://10.0.0.176:3117` / `tcp://10.0.0.176:3005` — pointing at an IP msi
no longer holds.

The Cloudflare tunnel daemon is running inside docker, so it sees the host
through the docker bridge. When it tried to reach `10.0.0.176:3117`, that
address didn't exist on the LAN anymore.

**Fix:** rewrite the tunnel ingress to use docker DNS, not host IP:

| Service | Before | After |
|---|---|---|
| `crucix.gnomenav.com` | `tcp://10.0.0.176:3117` | `http://crucix:3117` |
| `worldmonitor.gnomenav.com` | `tcp://10.0.0.176:3005` | `http://worldmonitor:8080` |

Container DNS resolves inside the cloudflared container's network attachment.
It doesn't care what address the host has on the LAN. **Whoever set those
ingresses originally pinned the IP because it was easy at the time** — and
created a failure mode that triggers every time DHCP gives msi a different
lease.

**Lesson:** *prefer container DNS over host IP for tunnel ingress.* The
pattern `http://<service-name>:<container-internal-port>` is the same shape
whether you have one host or ten.

## 4. VPN-attached services orphaned by a parent recreate

**Symptom (potential, didn't actually fire this time but I noticed the
shape of it while debugging):** the *arr stack runs with
`network_mode: "service:vpn"`, sharing the WireGuard container's network
namespace. If `vpn` ever gets recreated on its own, every dependent service
loses its network and can't be reached even though the container is "up."

**Diagnosis:** docker doesn't know about the soft dependency. `docker compose
up -d vpn` recreates `vpn` and silently strands `sonarr`, `radarr`,
`prowlarr`, `lidarr`, `readarr`, `qbittorrent`. Their containers keep
running, but their network namespace is gone.

**Fix:** if you ever bounce `vpn`, you have to bounce the dependent set too:

```bash
docker compose up -d sonarr radarr prowlarr lidarr readarr qbittorrent
```

I now have this in a recovery checklist that lives next to the compose file.

## What changed in my operational habit

After the fourth one I stopped fixing things ad-hoc and put the fixes
into source control:

1. **The recovery checklist became a real doc** — every failure mode I diagnosed got written up the same evening, with root cause, symptom, and the fix. It lives at `docs/cold-boot-recovery.md` in the gnomenav repo.
2. **A small CLI dispatcher (`nav`)** emerged for the diagnostic loop I kept running — `nav status`, `nav health`, `nav logs <svc>` — so the next outage is a 30-second triage instead of "remember the docker compose incantation."
3. **The compose file got templated** — every value that was a literal got pulled out into `.env`, and the `.env.example` lives in source. Reduces the ways future-me can be surprised.
4. **The whole thing went on GitHub** — public repo at [`ZNav/gnomenav`](https://github.com/ZNav/gnomenav). The point isn't the code; it's that "what does this do" is answerable from the repo without remembering anything.

## What I'd do differently next time

- **Set the DHCP reservation on day one.** Almost every problem above traces back to "the IP changed and something assumed it wouldn't." A reservation is two minutes on the router. I haven't been able to set mine yet (LAN is shared, can't touch router config), but the next homelab gets one before the first compose file is written.
- **Audit IP literals before publishing.** Once I templated the obvious secrets, I went and grepped for IPs across all configs — found four more in CF dashboard ingress alone. The audit takes 10 minutes; the cost of not doing it is one outage per environment change.
- **Treat compose drift as a leak.** When live containers don't match `docker-compose.yml`, you've already lost source-of-truth. I'd run a "what's running but not in source?" check as a pre-deploy gate.

## What's next

Up next in this series:
- *Designing `nav`: one CLI for two-host homelab ops*
- *Going public with my homelab repo: secrets I almost shipped (and one GitGuardian caught me on)*
- *Cloudflare Zero Trust SSH from anywhere: the 30-minute setup*

The whole gnomenav stack is at [`github.com/ZNav/gnomenav`](https://github.com/ZNav/gnomenav).

---
*Comments / questions / better ways to do any of this:
[zandernavratil@gmail.com](mailto:zandernavratil@gmail.com)*
