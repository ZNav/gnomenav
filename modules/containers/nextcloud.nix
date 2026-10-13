{ config, lib, pkgs, ... }:
let c = config.gnomenav; onCompute = c.role == "compute";
in lib.mkIf onCompute {
  sops.secrets.nextcloud_db_password = {};
  virtualisation.oci-containers.containers = {
    nextcloud-db = {
      image = "docker.io/mariadb:11";
      autoStart = true;
      extraOptions = [ "--network=proxy" ];
      cmd = [ "--transaction-isolation=READ-COMMITTED" "--log-bin=binlog" "--binlog-format=ROW" ];
      environmentFiles = [ config.sops.secrets.nextcloud_db_password.path ];
      environment = { MYSQL_DATABASE = "nextcloud"; MYSQL_USER = "nextcloud"; MARIADB_AUTO_UPGRADE = "1"; MYSQL_RANDOM_ROOT_PASSWORD = "1"; };
      volumes = [ "${c.configRoot}/nextcloud/db:/var/lib/mysql" ];
    };
    nextcloud-redis = { image = "docker.io/redis:alpine"; autoStart = true; extraOptions = [ "--network=proxy" ]; };
    nextcloud = {
      image = "docker.io/nextcloud:apache";
      autoStart = true;
      dependsOn = [ "nextcloud-db" "nextcloud-redis" ];
      extraOptions = [ "--network=proxy" ];
      environmentFiles = [ config.sops.secrets.nextcloud_db_password.path ];
      environment = {
        MYSQL_HOST = "nextcloud-db"; MYSQL_DATABASE = "nextcloud"; MYSQL_USER = "nextcloud";
        REDIS_HOST = "nextcloud-redis";
        NEXTCLOUD_TRUSTED_DOMAINS = "nextcloud.gnomenav.com";
        OVERWRITEPROTOCOL = "https"; OVERWRITECLIURL = "https://nextcloud.gnomenav.com";
      };
      volumes = [ "${c.configRoot}/nextcloud/html:/var/www/html" "${c.dataRoot}/nextcloud:/var/www/html/data" ];
    };
  };
}
