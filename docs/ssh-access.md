# SSH access

How to reach msi and x220 from anywhere, on the LAN, or over a phone tether.

## Three paths

| Path | When to use | Hostname |
|---|---|---|
| Direct LAN | At home | `msi-wifi` (10.0.0.175), `x220` (10.0.0.138) |
| CF tunnel + SSO | Anywhere with internet | `msi`, `x220-jump` |
| Browser-rendered SSH | Phone, no `cloudflared` | `https://ssh.gnomenav.com` |

## Local Mac / Linux setup

### 1. Install cloudflared

```bash
# macOS
brew install cloudflare/cloudflare/cloudflared

# Debian/Ubuntu (or Arch via pacman -S cloudflared)
curl -L https://pkg.cloudflare.com/cloudflared-linux-amd64.deb -o cloudflared.deb
sudo dpkg -i cloudflared.deb
```

### 2. Add to `~/.ssh/config`

```
# CF tunnel — works from anywhere
Host msi
  HostName ssh.gnomenav.com
  User znav
  ProxyCommand /opt/homebrew/bin/cloudflared access ssh --hostname %h
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30
  ForwardAgent yes

# Direct LAN, faster when home
Host msi-wifi
  HostName 10.0.0.175
  User znav
  ServerAliveInterval 30
  ForwardAgent yes

Host x220
  HostName 10.0.0.138
  User x220-edge
  ServerAliveInterval 30
  ForwardAgent yes

# x220 from anywhere via msi tunnel jump
Host x220-jump
  HostName 10.0.0.138
  User x220-edge
  ProxyJump msi
```

(Adjust the `cloudflared` path if it's not `/opt/homebrew/bin/cloudflared` —
on Linux it's usually `/usr/local/bin/cloudflared` or `/usr/bin/cloudflared`.)

### 3. First connect

```bash
ssh msi
```

Browser will pop with the Cloudflare Access SSO page. Pick one of the allowed
emails. Enter the OTP that arrives in your inbox. The SSO session is then
cached for the configured session duration (default 24h), so subsequent
`ssh msi` calls in that window are silent.

## Phone access

**Browser-based SSH** — no install, works on any phone:

1. In CF dashboard → Zero Trust → Access → Applications → `nav-ssh` →
   enable **Browser rendering → Render SSH**.
2. On your phone, visit `https://ssh.gnomenav.com`.
3. SSO with one of the allowed emails.
4. Full SSH terminal renders in the browser. `nav status`, `nav restart`,
   etc. all work.

**Termius app** — better keyboard ergonomics for longer sessions. Native iOS /
Android. Supports Cloudflare Access endpoints. Configure the host the same
way as `~/.ssh/config` above; Termius handles the SSO callback in-app.

## Access policy

5 allowed emails on the `nav-ssh` Access app:
- zandernavratil@gmail.com
- zander@cooksbook.com
- gnomenav@proton.me
- z@gnomenav.com
- kehoetaija@gmail.com

Note: the `@gnomenav.com` mailboxes inbound-route via Cloudflare Email Routing
to Gmail, so OTPs land in Gmail anyway. Effective security floor = Gmail
account security.

## Short-lived cert mode (optional, not currently configured)

If you want to skip SSH key auth entirely and rely on Cloudflare-issued
short-lived SSH user certificates instead:

1. Generate a CA in CF dashboard → Zero Trust → Access → Service Auth → SSH.
2. Copy the public key.
3. On msi: `sudo tee /etc/ssh/cf-ca.pub <<< "<the pubkey>"`
4. Edit `/etc/ssh/sshd_config`: add `TrustedUserCAKeys /etc/ssh/cf-ca.pub`.
5. `sudo systemctl reload sshd`.
6. On Mac, regenerate ssh-config:
   ```
   cloudflared access ssh-config --hostname ssh.gnomenav.com --short-lived-cert
   ```

The plain SSH-key-through-tunnel path (current setup) works fine for
single-device or few-device use. Short-lived certs only earn their keep when
you have many devices and don't want to manage SSH keypairs on each.
