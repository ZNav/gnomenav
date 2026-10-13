{ config, lib, pkgs, ... }:
# Cloudflare Tunnel — public hostnames reach containers with ZERO open ports.
# Admin apps get a Cloudflare Access policy in front (free Zero Trust, 50 users).
#
# The live tunnel is DASHBOARD-MANAGED (remotely configured): the connector
# authenticates with a token (sops `cloudflared_token`, stored as
# `TUNNEL_TOKEN=<token>` for environmentFiles), and the hostname->service
# ingress map lives in the Cloudflare dashboard (Zero Trust > Networks >
# Tunnels), NOT in a local config file. NixOS `services.cloudflared` only
# supports locally-managed tunnels (credentials JSON + local ingress), so we
# run the same container as the live Arch setup — drop-in continuity.
#
# The canonical hostname list is kept below as version-controlled
# documentation. If/when the tunnel migrates to locally-managed (Cloudflare
# cleanup step, needs API token), switch to `services.cloudflared` and move
# this list into real `ingress` config.
#
# Canonical public hostnames (dashboard-managed; live ingress v77, 2026-07-14):
#   Public (no Access):
#     gnomenav.com, api., jellyfin., music., books., memories., nextcloud.,
#     llm., kiwix., dash., crucix., worldmonitor., blog. (HANDS-OFF), wiki.
#     (HANDS-OFF), mail. (roundcube exited; kept for MX-adjacent safety)
#   Admin (PUT BEHIND CLOUDFLARE ACCESS — see docs/CLOUDFLARE.md; still
#   ungated as of 2026-07-14, Zander deferred):
#     sonarr., radarr., lidarr., prowlarr., qbittorrent., portainer.,
#     adguard., cockpit-msi., cockpit-x220., ssh.  (.gnomenav.com)
#   Pruned 2026-07-14 (ingress removed; stale CNAMEs remain pending DNS:Edit):
#     readarr., navidrome-test., kavita-test., spotdl., netdata.
#
# Caddy still terminates internally on :80 and routes by Host to each container.
let c = config.gnomenav;
in lib.mkIf (c.role == "compute") {
  sops.secrets.cloudflared_token = {};

  virtualisation.oci-containers.containers.cloudflared = {
    image = "docker.io/cloudflare/cloudflared:latest";
    autoStart = true;
    extraOptions = [ "--network=proxy" ];
    environmentFiles = [ config.sops.secrets.cloudflared_token.path ];
    cmd = [ "tunnel" "--no-autoupdate" "run" ];
  };
}
