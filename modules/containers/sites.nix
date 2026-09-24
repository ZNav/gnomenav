{ config, lib, pkgs, ... }:
# Personal + family sites, formerly compose-drift orphans (ran with no source
# definition on Arch docker; resurrected declaratively 2026-07-18 post-migration).
#
# ghost   = blog.gnomenav.com — WIFE'S BLOG. Pinned to the 5.x line (restored
#           db is ghost 5.130 — do NOT bump to 6 casually; majors need a
#           deliberate upgrade). SQLite (content/data/ghost.db).
# wikijs  = wiki.gnomenav.com — couple-shared. Postgres 15 (data dir restored;
#           role/db = wiki/wiki). DB password was reset at resurrection (old
#           container env died with the wipe) — value lives in sops
#           `wikijs_db_env`, applied to postgres via ALTER USER at restore.
# gnomenav-site    = gnomenav.com static site (nginx; content synced from the
#                    Mac's ~/gnomenav repo — that repo is authoritative).
# gnomenav-backend = api.gnomenav.com — image built ON-HOST from the parked
#                    source (localhost/gnomenav-backend:latest, podman build
#                    at /home/znav/nas/gnomenav-backend). Declarative build is
#                    a phase-2 item.
let c = config.gnomenav; onCompute = c.role == "compute";
in lib.mkIf onCompute {
  sops.secrets.wikijs_db_env = { };

  virtualisation.oci-containers.containers = {
    ghost = {
      image = "docker.io/library/ghost:5-alpine";
      autoStart = true;
      extraOptions = [ "--network=proxy" ];
      environment = {
        url = "https://blog.gnomenav.com";
        NODE_ENV = "production";
        database__client = "sqlite3";
        database__connection__filename = "/var/lib/ghost/content/data/ghost.db";
      };
      volumes = [ "${c.configRoot}/ghost/content:/var/lib/ghost/content" ];
    };

    wikijs-db = {
      image = "docker.io/library/postgres:15-alpine";
      autoStart = true;
      extraOptions = [ "--network=proxy" ];
      volumes = [ "${c.configRoot}/wikijs/db:/var/lib/postgresql/data" ];
    };

    wikijs = {
      image = "ghcr.io/requarks/wiki:2";
      autoStart = true;
      dependsOn = [ "wikijs-db" ];
      extraOptions = [ "--network=proxy" ];
      environment = {
        DB_TYPE = "postgres";
        DB_HOST = "wikijs-db";
        DB_PORT = "5432";
        DB_USER = "wiki";
        DB_NAME = "wiki";
      };
      environmentFiles = [ config.sops.secrets.wikijs_db_env.path ];
    };

    gnomenav-site = {
      image = "docker.io/library/nginx:alpine";
      autoStart = true;
      extraOptions = [ "--network=proxy" ];
      volumes = [ "${c.configRoot}/gnomenav/site:/usr/share/nginx/html:ro" ];
    };

    gnomenav-backend = {
      image = "localhost/gnomenav-backend:latest";
      autoStart = true;
      extraOptions = [ "--network=proxy" "--pull=never" ];
    };
  };
}
