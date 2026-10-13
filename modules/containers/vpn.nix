{ config, lib, ... }:
let
  c = config.gnomenav; onCompute = c.role == "compute";
in lib.mkIf onCompute {
  # WireGuard egress for torrent traffic. gluetun = VPN client + kill-switch:
  # when the tunnel is down its firewall drops all non-VPN egress, so anything
  # sharing this netns (qbittorrent) can never leak onto the bare WAN.
  sops.secrets.wireguard_env = {};

  virtualisation.oci-containers.containers.vpn = {
    image = "ghcr.io/qdm12/gluetun:latest";
    autoStart = true;
    extraOptions = [
      "--network=proxy"
      "--cap-add=NET_ADMIN"
      "--device=/dev/net/tun"
    ];
    environment = {
      VPN_SERVICE_PROVIDER = "custom";
      VPN_TYPE = "wireguard";
      # qbittorrent (8080), prowlarr (9696) and slskd (5030) ride this netns —
      # cloudflared and the arrs reach them at vpn:<port>, which gluetun's
      # firewall must let in.
      FIREWALL_INPUT_PORTS = "8080,9696,5030";
      # LAN + podman proxy net stay outside the tunnel.
      FIREWALL_OUTBOUND_SUBNETS = "10.0.0.0/24,10.89.0.0/24";
    };
    # WIREGUARD_PRIVATE_KEY / WIREGUARD_PUBLIC_KEY / WIREGUARD_ADDRESSES /
    # VPN_ENDPOINT_IP / VPN_ENDPOINT_PORT — sops only (scripts/migrate-wg-to-sops.sh).
    environmentFiles = [ config.sops.secrets.wireguard_env.path ];
  };
}
