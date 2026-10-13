{ config, pkgs, lib, ... }:
# ─────────────────────────────────────────────────────────────────────────────
# tui-first.nix — TTY is the main interface; GUI exists only as a command.
# Opt-in per host via `gnomenav.tuiFirst.enable`. Design: vault page
# Homelab/TUI-First Interface Plan (2026-07-18).
#
# Login on tty1 lands in a 4-tab zellij "deck": files (yazi) · sys (btop +
# sysz) · stacks (lazydocker over podman) · shell. SSH sessions are NEVER
# touched — the Mac-driven ssh workflow stays a plain shell.
# `gui` launches Hyprland via uwsm; compositor exit returns to a login prompt.
# ─────────────────────────────────────────────────────────────────────────────
let
  cfg = config.gnomenav.tuiFirst;

  guiCmd = pkgs.writeShellScriptBin "gui" ''
    set -eu
    [ -n "''${SSH_CONNECTION:-}" ] && { echo "gui: refusing over SSH (compositor needs the seat)"; exit 1; }
    [ -n "''${WAYLAND_DISPLAY:-}''${DISPLAY:-}" ] && { echo "gui: a graphical session is already running"; exit 1; }
    # exec: on compositor exit this shell dies, getty respawns a login prompt
    # (autologinOnce means it will NOT auto-login again — intended).
    exec ${pkgs.uwsm}/bin/uwsm start -- hyprland-uwsm.desktop
  '';

  guiAppCmd = pkgs.writeShellScriptBin "gui-app" ''
    # one GUI app in a kiosk compositor, straight back to the TTY on exit
    exec ${pkgs.cage}/bin/cage -s -- "$@"
  '';

  deckLayout = pkgs.writeText "deck.kdl" ''
    layout {
      default_tab_template {
        pane size=1 borderless=true { plugin location="zellij:tab-bar"; }
        children
        pane size=1 borderless=true { plugin location="zellij:status-bar"; }
      }
      tab name="files" focus=true {
        pane command="yazi" { args "/home/${cfg.user}/nas"; }
      }
      tab name="sys" {
        pane split_direction="vertical" {
          pane command="btop"
          pane command="sysz"
        }
      }
      tab name="stacks" { pane command="lazydocker"; }
      tab name="shell" { pane; }
    }
  '';
in
{
  options.gnomenav.tuiFirst = {
    enable = lib.mkEnableOption
      "boot-to-TTY main interface (yazi/zellij deck) with GUI only via `gui`";
    user = lib.mkOption {
      type = lib.types.str; default = "z";
      description = "user that autologs into the deck on tty1";
    };
    autologin = lib.mkOption {
      type = lib.types.bool; default = true;
      description = "getty autologin, once per boot (LUKS is the physical gate)";
    };
    kmscon = lib.mkOption {
      type = lib.types.bool; default = true;
      description = "DRM console with real font rendering so the TTY looks like a terminal emulator";
    };
    gui.enable = lib.mkOption {
      type = lib.types.bool; default = true;
      description = "install Hyprland+uwsm and the `gui` / `gui-app` commands";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # ── Contract: NO display manager, ever ────────────────────────────────
      # (Importing this on the x220 would REPLACE its SDDM autostart world —
      #  that is a flagged decision; this assertion makes it loud.)
      assertions = [{
        assertion =
          !(config.services.displayManager.sddm.enable or false)
          && !(config.services.xserver.displayManager.gdm.enable or false)
          && !(config.services.greetd.enable or false);
        message = "gnomenav.tuiFirst: a display manager is enabled; this module is TTY-first by contract.";
      }];

      # ── Login → deck ──────────────────────────────────────────────────────
      services.getty = lib.mkIf cfg.autologin {
        autologinUser = cfg.user;
        autologinOnce = true;   # logout / gui-exit → normal password prompt
      };

      # Attach the deck ONLY on interactive tty1 login: never SSH, never nested.
      programs.fish.enable = true;
      programs.fish.interactiveShellInit = lib.mkAfter ''
        if status is-login; and test -z "$SSH_CONNECTION"; and test -z "$ZELLIJ"
          if test (tty) = /dev/tty1
            echo (set_color yellow)"failed units:" (systemctl --failed --no-legend | count) " · containers:" (podman ps -q | count)(set_color normal)
            exec zellij --layout /etc/zellij/deck.kdl attach --create deck
          end
        end
      '';
      environment.etc."zellij/deck.kdl".source = deckLayout;

      # ── The kit (self-contained; rice.nix overlap is harmless) ────────────
      environment.systemPackages = with pkgs; [
        zellij yazi btop lazygit lazydocker sysz fzf zoxide fastfetch
      ];
      # lazydocker speaks docker → point it at the podman socket
      virtualisation.podman.dockerSocket.enable = true;
      environment.variables.DOCKER_HOST = "unix:///run/podman/podman.sock";

      fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];
    }

    (lib.mkIf cfg.kmscon {
      services.kmscon = {
        enable = true;
        hwRender = true;
        fonts = [{
          name = "JetBrainsMono Nerd Font";
          package = pkgs.nerd-fonts.jetbrains-mono;
        }];
        extraConfig = "font-size=13";
      };
    })

    # ── GUI: exists, never auto ───────────────────────────────────────────
    (lib.mkIf cfg.gui.enable {
      programs.hyprland = { enable = true; withUWSM = true; };
      environment.systemPackages = [ guiCmd guiAppCmd pkgs.cage ];
      # deliberately NO displayManager, NO autostart, NO exec-in-profile
    })
  ]);
}
