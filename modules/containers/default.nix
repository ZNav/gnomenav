{ config, pkgs, lib, ... }:
let role = config.gnomenav.role or "compute";
in {
  imports = [
    ./options.nix
    ./web.nix        # dashboard, adguard, portainer, kiwix  (both roles, split inside)
    ./media.nix      # jellyfin, navidrome, kavita, immich    (compute)
    ./arr.nix        # *arr + qbittorrent + prowlarr           (compute)
    ./vpn.nix        # gluetun WireGuard egress + kill-switch  (compute)
    ./nextcloud.nix  # nextcloud + db + redis                  (compute)
    ./llm.nix        # llama.cpp + open-webui                  (compute)
    ./ai-silo.nix    # qdrant + khoj + nightly index (RAG/Jarvis)  (compute)
    ./openclaw.nix   # Telegram↔Claude gateway (compute; opt-in via gnomenav.openclaw.enable)
    ./sites.nix      # ghost (wife's blog), wikijs(+db), gnomenav site+backend (compute)
  ];

  # Podman as the docker-compatible backend.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;                 # `docker` CLI works too
    defaultNetwork.settings.dns_enabled = true;
  };
  virtualisation.oci-containers.backend = "podman";

  # Shared user-defined network so containers resolve each other by name.
  systemd.services.init-proxy-net = {
    description = "create podman 'proxy' network";
    wantedBy = [ "multi-user.target" ];
    after = [ "podman.service" ];
    serviceConfig.Type = "oneshot";
    script = "${pkgs.podman}/bin/podman network exists proxy || ${pkgs.podman}/bin/podman network create proxy";
  };
}
