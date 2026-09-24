{ config, lib, pkgs, ... }:
let c = config.gnomenav; onCompute = c.role == "compute";
in lib.mkIf onCompute {
  sops.secrets.immich_db_password = {};

  virtualisation.oci-containers.containers = {
    jellyfin = {
      # NOTE 2026-07-18: old compose mounted ./jellyfin/config:/config — the
      # restore initially landed one level deep (config/ nesting) and 10.11
      # crash-looped migrating an "empty" config. Fixed by hoisting the nested
      # tree up; data was already 10.11-migrated in the old world.
      image = "jellyfin/jellyfin:latest";
      autoStart = true;
      extraOptions = [ "--network=proxy" "--device=/dev/dri:/dev/dri" "--group-add=video" ];
      environment.JELLYFIN_PublishedServerUrl = "https://jellyfin.gnomenav.com";
      volumes = [
        "${c.configRoot}/jellyfin:/config"
        # Mount the media root at /data: the restored library DB references
        # /data/shows, /data/movies, etc. (old compose layout). Mounting at
        # /data/media left every library path dangling — playback 404'd.
        "${c.dataRoot}/media:/data:ro"
      ];
    };

    navidrome = {
      image = "deluan/navidrome:latest";
      autoStart = true;
      extraOptions = [ "--network=proxy" ];
      environment = {
        ND_SCANSCHEDULE = "30m";
        ND_BASEURL = "https://music.gnomenav.com";
      };
      volumes = [
        "${c.configRoot}/navidrome:/data"
        "${c.dataRoot}/media/music:/music:ro"
      ];
    };

    kavita = {
      image = "jvmilazz0/kavita@sha256:1f2acae7466d022f037ea09f7989eb7c487f916b881174c7a6de33dbfa8acb39"; # pinned known-good (0.8.9.1-compatible)
      autoStart = true;
      extraOptions = [ "--network=proxy" ];
      volumes = [
        "${c.configRoot}/kavita:/kavita/config"
        "${c.dataRoot}/media/books:/books"
      ];
    };

    # --- Immich (memories.gnomenav.com) ---
    immich-server = {
      image = "ghcr.io/immich-app/immich-server:release";
      autoStart = true;
      dependsOn = [ "immich-db" "immich-redis" ];
      extraOptions = [ "--network=proxy" ];
      environmentFiles = [ config.sops.secrets.immich_db_password.path ];
      environment = {
        DB_HOSTNAME = "immich-db"; DB_USERNAME = "immich"; DB_DATABASE_NAME = "immich";
        REDIS_HOSTNAME = "immich-redis";
      };
      volumes = [ "${c.dataRoot}/immich:/usr/src/app/upload" ];
    };
    immich-ml = {
      image = "ghcr.io/immich-app/immich-machine-learning:release";
      autoStart = true;
      extraOptions = [ "--network=proxy" ];
      volumes = [ "${c.configRoot}/immich/ml-cache:/cache" ];
    };
    immich-redis = {
      image = "docker.io/redis:6.2-alpine";
      autoStart = true;
      extraOptions = [ "--network=proxy" ];
    };
    immich-db = {
      image = "ghcr.io/immich-app/postgres:14-vectorchord0.3.0";
      autoStart = true;
      extraOptions = [ "--network=proxy" ];
      environmentFiles = [ config.sops.secrets.immich_db_password.path ];
      environment = { POSTGRES_USER = "immich"; POSTGRES_DB = "immich"; };
      volumes = [ "${c.configRoot}/immich/db:/var/lib/postgresql/data" ];
    };
  };
}
