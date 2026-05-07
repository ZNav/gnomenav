# Cloudflare Zero Trust — tunnel ingress map

Reference for the public hostname routes configured on the Cloudflare dashboard
(token-based tunnel; no local `config.yml`). Keep this in sync with the
Zero Trust → Networks → Tunnels → Public Hostnames panel.

## Pattern: prefer container DNS over host IP

Whenever possible, ingress points should use docker DNS:

```
http://<service-name>:<container-internal-port>
```

NOT host-IP+published-port. Container DNS resolves inside the
`cloudflared-tunnel` container's network attachments and survives MSI's DHCP IP
drift.

## Routes

| Public hostname | Type | Target | Notes |
|---|---|---|---|
| gnomenav.com | HTTP | `http://glance:8080` | dashboard |
| dash.gnomenav.com | HTTP | `http://glance:8080` | alias |
| jellyfin.gnomenav.com | HTTP | `http://jellyfin:8096` | |
| nextcloud.gnomenav.com | HTTP | `http://nextcloud:80` | |
| llm.gnomenav.com | HTTP | `http://open-webui:8080` | |
| music.gnomenav.com | HTTP | `http://navidrome:4533` | |
| books.gnomenav.com | HTTP | `http://kavita:5000` | |
| memories.gnomenav.com | HTTP | `http://wanderer:3000` | |
| worldmonitor.gnomenav.com | HTTP | `http://worldmonitor:8080` | ⚠️ **currently set to `tcp://10.0.0.176:3005` — broken on IP drift** |
| crucix.gnomenav.com | HTTP | `http://crucix:3117` | ⚠️ **currently set to `tcp://10.0.0.176:3117` — broken** |
| mail.gnomenav.com | HTTP | `http://roundcube:80` | |
| adguard.gnomenav.com | HTTP | `http://adguardhome:3000` | web UI only |
| blog.gnomenav.com | HTTP | `http://ghost:2368` | |
| portainer.gnomenav.com | HTTP | `http://portainer:9000` | |
| wiki.gnomenav.com | HTTP | `http://wikijs:3000` | |
| kiwix.gnomenav.com | HTTP | `http://kiwix:8080` | parked under compose profile until ZIM ready |
| mindset.gnomenav.com | HTTP | `http://mindset-backend:5000` | |
| netdata.gnomenav.com | HTTP | `http://172.19.0.1:19999` | host service via bridge gw |
| cockpit-msi.gnomenav.com | HTTPS | `https://172.19.0.1:9090` | TLS verify off |
| cockpit-x220.gnomenav.com | HTTPS | `https://10.0.0.138:9090` | direct, TLS verify off |
| ssh.gnomenav.com | SSH | `172.19.0.1:22` | gated by Access app |

## Access (SSO) applications

| App domain | Policy | Reason |
|---|---|---|
| ssh.gnomenav.com | Allow if email in {zandernavratil@gmail.com, zander@cooksbook.com, gnomenav@proton.me, z@gnomenav.com, kehoetaija@gmail.com} | SSH must SSO; bare SSH endpoint to internet is unacceptable |

Anything not listed here is _publicly_ reachable (anyone on the internet can
hit it). That's intentional for public sites (gnomenav.com, blog) but should
be reconsidered for admin UIs (portainer, glance, adguard).

## Team domain

`gnomenav.cloudflareaccess.com` — used for SSO callback and (eventually) for
the SSH CA pubkey if short-lived-cert mode is configured.
