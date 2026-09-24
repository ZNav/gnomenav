{ config, lib, pkgs, ... }:
let
  c = config.gnomenav; onCompute = c.role == "compute";
  py = pkgs.python3.withPackages (ps: [ ps.requests ps.guessit ]);
  script = ../scripts/prowlarr-autosort.py;
in lib.mkIf onCompute {
  # Manual Prowlarr grabs (qbit category 'prowlarr') are invisible to the arrs;
  # this classifies them and fires the right arr's Downloaded*Scan so they get
  # hardlink-imported into /data/media. Event-driven via a trigger file qbit
  # touches on torrent completion, plus an hourly catch-up sweep.
  sops.secrets.qbittorrent_env = {};

  systemd.services.prowlarr-autosort = {
    description = "route manual Prowlarr grabs into the arrs";
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.sops.secrets.qbittorrent_env.path;
      ExecStart = "${py}/bin/python3 ${script}";
    };
  };

  # qbit's on-complete hook (set in its prefs) touches this file inside the
  # container's /config mount; the path unit turns that into an instant run.
  systemd.paths.prowlarr-autosort = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathModified = "${c.configRoot}/qbittorrent/autosort-trigger";
  };

  systemd.timers.prowlarr-autosort = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "hourly"; Persistent = true; RandomizedDelaySec = 300; };
  };
}
