{ config, lib, pkgs, ... }:
let
  c = config.gnomenav; onCompute = c.role == "compute";
  # Identity from the registry (modules/users.nix) — never hardcode uids here.
  env = {
    PUID = toString c.ids.arr.uid;
    PGID = toString c.ids.arr.gid;
    TZ = config.time.timeZone;
  };
  # GOLDEN RULE: every arr + qbit mounts dataRoot at /data (identical path) so
  # imports hardlink instead of copy and land in the right per-type folder.
  dataMount = "${c.dataRoot}:/data";
  mk = image: cfg: {
    inherit image; autoStart = true;
    environment = env;
    extraOptions = [ "--network=proxy" ];
  } // cfg;
in lib.mkIf onCompute {
  virtualisation.oci-containers.containers = {
    qbittorrent = mk "lscr.io/linuxserver/qbittorrent:latest" {
      environment = env // { WEBUI_PORT = "8080"; };
      volumes = [ "${c.configRoot}/qbittorrent:/config" dataMount ];
      # Torrent traffic must only exist inside the VPN tunnel: share gluetun's
      # netns (kill-switch covers us) — web UI is reached at vpn:8080.
      extraOptions = [ "--network=container:vpn" ];
      dependsOn = [ "vpn" ];
    };
    prowlarr = mk "lscr.io/linuxserver/prowlarr:latest" {
      volumes = [ "${c.configRoot}/prowlarr:/config" ];
      # Indexer searches carry the home IP if they leave bare — tunnel them like
      # the torrents. Gluetun's DoT resolver replaces podman DNS in this netns,
      # so prowlarr's app links must use public hostnames, not container names;
      # the arrs reach prowlarr at vpn:9696.
      extraOptions = [ "--network=container:vpn" ];
      dependsOn = [ "vpn" ];
    };
    sonarr  = mk "lscr.io/linuxserver/sonarr:latest"  { volumes = [ "${c.configRoot}/sonarr:/config"  dataMount ]; };
    radarr  = mk "lscr.io/linuxserver/radarr:latest"  { volumes = [ "${c.configRoot}/radarr:/config"  dataMount ]; };
    lidarr  = mk "lscr.io/linuxserver/lidarr:latest"  { volumes = [ "${c.configRoot}/lidarr:/config"  dataMount ]; };
    # Soulseek lane (2026-07-28): slskd shares the vpn netns like the torrents,
    # so peer traffic only exists inside Mullvad. Mullvad dropped port-forwarding,
    # so inbound peers can't reach us — downloads from open-port peers still work.
    # UI/API at vpn:5030. Config (incl. soulseek creds + API key) is the sops
    # slskd_yml secret bind-mounted over /app/slskd.yml.
    # not via mk: the image refuses PUID/PGID env combined with --user
    slskd = {
      image = "ghcr.io/slskd/slskd:latest";
      autoStart = true;
      environment = { TZ = config.time.timeZone; };
      volumes = [
        "${c.configRoot}/slskd:/app"
        dataMount
        "${config.sops.secrets.slskd_yml.path}:/app/slskd.yml:ro"
      ];
      # official image (not lscr): no PUID self-chown — run directly as the arr id
      extraOptions = [
        "--network=container:vpn"
        "--user=${toString c.ids.arr.uid}:${toString c.ids.arr.gid}"
      ];
      dependsOn = [ "vpn" ];
    };
    # soularr bridges lidarr's wanted/cutoff-unmet queue -> slskd searches, then
    # triggers the lidarr import. config.ini (holds both API keys) is generated
    # on-host by scripts/soularr-config.sh — never in git.
    # image insists on /data as its CONFIG dir, so it can't take the golden-rule
    # dataMount — it only needs slskd's complete dir, mounted at /downloads.
    soularr = mk "docker.io/mrusse08/soularr:latest" {
      environment = env // { SCRIPT_INTERVAL = "600"; };
      volumes = [
        "${c.configRoot}/soularr:/data"
        "${c.dataRoot}/downloads/slskd/complete:/downloads"
      ];
      dependsOn = [ "lidarr" ];
    };
    recyclarr = mk "ghcr.io/recyclarr/recyclarr:latest" {
      volumes = [ "${c.configRoot}/recyclarr:/config" ];
    };
  };

  # Nightly spotdl sync + weekly recyclarr, declaratively (replaces host crontab).
  systemd.services.spotdl-sync = {
    description = "spotdl -> navidrome sync";
    serviceConfig = { Type = "oneshot"; EnvironmentFile = config.sops.secrets.spotify_env.path; };
    script = ''
      ${pkgs.podman}/bin/podman run --rm \
        -v ${c.dataRoot}/media/music:/music -v ${c.configRoot}/spotdl:/state \
        -e SPOTIFY_CLIENT_ID -e SPOTIFY_CLIENT_SECRET \
        docker.io/spotdl/spotify-downloader:latest \
        sync saved --save-file /state/liked.spotdl \
        --output "/music/{artist}/{album}/{track-number} - {title}.{output-ext}" \
        --format opus --bitrate disable
    '';
  };
  systemd.timers.spotdl-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*-*-* 03:15:00"; Persistent = true; };
  };

  # Disk guard for the Soulseek lane (2026-08-02: hi-res FLAC filled the fs in
  # five days). Below 40G free on /data the downloaders stop; restarting them
  # after freeing space is a manual, deliberate act.
  systemd.services.music-disk-guard = {
    description = "stop soularr/slskd when /data runs low";
    serviceConfig.Type = "oneshot";
    script = ''
      avail=$(${pkgs.coreutils}/bin/df --output=avail -BG /data | ${pkgs.gnused}/bin/sed -n '2s/G//p' | tr -d ' ')
      if [ "$avail" -lt 40 ]; then
        echo "only ''${avail}G free — stopping soularr + slskd"
        systemctl stop podman-soularr podman-slskd
      fi
    '';
  };
  systemd.timers.music-disk-guard = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*:0/15"; Persistent = true; };
  };
  sops.secrets.spotify_env = {};
  # owner z (=arr id 1000) so the --user'd slskd container can read its config
  sops.secrets.slskd_yml = { owner = "z"; };
}
