{ config, lib, ... }:
# ─────────────────────────────────────────────────────────────────────────────
# users.nix — the identity registry. Single source of truth for every uid,
# gid, group membership, and state-directory ownership in the fleet.
# Services NEVER invent identities; they reference `config.gnomenav.ids`.
#
# HARD CONSTRAINT: `z` and the `media` group stay 1000:1000 — the 702G nas
# tree (and its SanDisk backup) is owned 1000:1000; the registry must match
# it so restored data never needs a recursive chown.
#
# Phase 2 (post-restore hardening, see vault Homelab/Nix Build Reorg Plan):
# split service identities into the 3100+ range (arr→3102 etc., createUser
# = true), convert non-lscr containers to podman `--user`, and `chmod -R g+w`
# the shared media tree. NOT done pre-wipe by design: lscr images self-chown
# on PUID change but official images don't, and restore day is the wrong day
# to make freshly-restored state unreadable.
# ─────────────────────────────────────────────────────────────────────────────
let
  cfg = config.gnomenav;
  c = cfg;
  # registry entries that materialize as real accounts
  userEntries = lib.filterAttrs (_: id: id.createUser) cfg.ids;
in
{
  options.gnomenav.ids = lib.mkOption {
    default = { };
    description = "fleet-wide identity registry: every uid/gid lives here";
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        uid = lib.mkOption { type = lib.types.int; };
        gid = lib.mkOption { type = lib.types.int; };
        groups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        human = lib.mkOption { type = lib.types.bool; default = false; };
        createUser = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "false = data-only entry (identity consumed via PUID/PGID, no OS account)";
        };
      };
    });
  };

  config = {
    gnomenav.ids = {
      # ---- humans ----
      z = {
        uid = 1000; gid = 1000; human = true;
        groups = [ "wheel" "podman" "docker" "video" "render" ];
      };
      # ---- service identities ----
      # arr = what the lscr containers (sonarr/radarr/lidarr/readarr/prowlarr/
      # qbittorrent/recyclarr) run as via PUID/PGID. Currently 1000:1000 =
      # today's live reality (shared media tree is owner-writable only).
      # Phase 2 flips this to 3102 + createUser = true.
      arr = { uid = 1000; gid = 1000; createUser = false; };
    };

    # `media` IS gid 1000 — the group that owns the nas tree.
    users.groups = { media.gid = 1000; }
      // lib.mapAttrs (_: id: { gid = id.gid; })
           (lib.filterAttrs (n: _: n != "z") userEntries);

    users.users =
      lib.mapAttrs (name: id:
        if id.human then {
          uid = id.uid;
          isNormalUser = true;
          group = "media";                  # primary group = gid 1000, matches nas
          extraGroups = id.groups ++ [ "networkmanager" ];
        } else {
          uid = id.uid;
          isSystemUser = true;
          group = name;
          extraGroups = id.groups;
        }) userEntries;

    # ---- Declarative state-directory ownership ----
    # Every container config/data dir pre-created with the right owner; kills
    # the "first run as root then chown" drift class entirely. Owners reflect
    # the phase-1 reality documented above.
    systemd.tmpfiles.rules = [
      # lscr stack (self-chowns to PUID internally; dirs owned by the arr id)
      "d ${c.configRoot}/qbittorrent 0750 z media -"
      "d ${c.configRoot}/prowlarr    0750 z media -"
      "d ${c.configRoot}/sonarr      0750 z media -"
      "d ${c.configRoot}/radarr      0750 z media -"
      "d ${c.configRoot}/lidarr      0750 z media -"
      "d ${c.configRoot}/readarr     0750 z media -"
      "d ${c.configRoot}/recyclarr   0750 z media -"
      "d ${c.configRoot}/spotdl      0750 z media -"
      "d ${c.configRoot}/slskd       0750 z media -"
      "d ${c.configRoot}/soularr     0750 z media -"
      # root-running official images (phase 2 converts these to --user)
      "d ${c.configRoot}/ghost           0755 root root -"
      "d ${c.configRoot}/wikijs          0755 root root -"
      "d ${c.configRoot}/gnomenav        0755 root root -"
      "d ${c.configRoot}/gnomenav/site   0755 root root -"
      # openclaw image runs as node (uid 1000) — root-owned dir EACCES-crashed
      # the gateway post-migration (fixed 2026-07-19)
      "d ${c.configRoot}/openclaw        0750 z media -"
      "d ${c.configRoot}/jellyfin        0755 root root -"
      "d ${c.configRoot}/navidrome       0755 root root -"
      "d ${c.configRoot}/kavita          0755 root root -"
      "d ${c.configRoot}/immich/ml-cache 0755 root root -"
      "d ${c.configRoot}/immich/db       0700 root root -"
      "d ${c.configRoot}/nextcloud/db    0700 root root -"
      "d ${c.configRoot}/nextcloud/html  0755 root root -"
      "d ${c.configRoot}/glance          0755 root root -"
      "d ${c.configRoot}/portainer       0755 root root -"
      "d ${c.configRoot}/llm/models      0755 root root -"
      "d ${c.configRoot}/open-webui      0755 root root -"
      # khoj parked 2026-07-19 (see ai-silo.nix) — rule kept commented for the RAG lane
      # "d ${c.configRoot}/khoj            0755 root root -"
      # data roots (the nas tree: always 1000:1000)
      "d ${c.dataRoot}                 0755 z media -"
      "d ${c.dataRoot}/media           0775 z media -"
      "d ${c.dataRoot}/nextcloud       0770 33 33 -"      # www-data in-container; sqlite journal needs dir write
      "d ${c.dataRoot}/immich          0755 root root -"
      "d ${c.dataRoot}/vectors         0755 root root -"
      "d ${c.dataRoot}/vectors/qdrant  0755 root root -"
      "d ${c.dataRoot}/downloads                  0775 z media -"
      "d ${c.dataRoot}/downloads/slskd            0775 z media -"
      "d ${c.dataRoot}/downloads/slskd/complete   0775 z media -"
      "d ${c.dataRoot}/downloads/slskd/incomplete 0775 z media -"
      "d ${c.dataRoot}/knowledge       0755 z media -"
      "d ${c.dataRoot}/kiwix           0755 z media -"
    ];
  };
}
