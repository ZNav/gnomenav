{ config, lib, pkgs, ... }:
let
  c = config.gnomenav;
  onCompute = c.role == "compute";
  onUtility = c.role == "utility";
in {
  # RETIRED 2026-07-19 (Zander's keep/kill pass, day 2 post-migration):
  # adguard, kiwix (its 116G zim data died with the old x220 NFS), crucix,
  # worldmonitor (+sidecars), wanderer (+db+meili), openwebrx. Ingress rules
  # pruned to the 404 catch-all. Revive = re-declare here + re-add ingress.
  virtualisation.oci-containers.containers = lib.mkMerge [

    (lib.mkIf onCompute {
      # dash.gnomenav.com — the dashboard. Config restored from the SanDisk
      # backup (glance/config/glance.yml).
      glance = {
        image = "docker.io/glanceapp/glance:latest";
        autoStart = true;
        extraOptions = [ "--network=proxy" ];
        volumes = [ "${c.configRoot}/glance/config:/app/config" ];
      };

      # portainer.gnomenav.com — revived per Zander 2026-07-19. Fresh instance:
      # FIRST VISITOR CREATES ADMIN and init locks ~5 min after start — claim
      # it immediately after the switch (restart the unit first if it locked).
      # Belongs behind Cloudflare Access with the arrs when that lands.
      portainer = {
        image = "docker.io/portainer/portainer-ce:latest";
        autoStart = true;
        extraOptions = [ "--network=proxy" ];
        volumes = [
          "/run/podman/podman.sock:/var/run/docker.sock"
          "${c.configRoot}/portainer:/data"
        ];
      };
    })

    # Dormant: no utility-role host exists since the x220 left the repo
    # (2026-07-15). Kept as the template for a future utility box.
    (lib.mkIf onUtility {
      homepage = {
        image = "ghcr.io/gethomepage/homepage:latest";
        autoStart = true;
        extraOptions = [ "--network=proxy" ];
        environment.HOMEPAGE_ALLOWED_HOSTS = "gnomenav.com";
        volumes = [
          "${c.configRoot}/homepage:/app/config"
          "/run/podman/podman.sock:/var/run/docker.sock:ro"
        ];
      };
    })
  ];
}
