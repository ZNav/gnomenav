{ config, pkgs, lib, ... }:
{
  imports = [ ./disko.nix ./hardware-configuration.nix ];
  networking.hostName = "msi";

  # UEFI: systemd-boot on the ESP that disko creates.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Swap is zram (matches live Arch setup: 4G zram0, no swap partition).
  zramSwap = { enable = true; memoryPercent = 25; };

  # MSI Delta 15 — Ryzen 7 5800H + Radeon RX 6700M (gfx1031).
  # AMD GPU userspace for Vulkan (LLM) + VAAPI (Jellyfin transcode).
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ mesa vaapiVdpau libvdpau-va-gl amdvlk ];
  };
  # Lid stays open->awake when docked (mirrors your logind tweak, now declarative).
  # (25.05 options; `services.logind.settings` only exists on 25.11+.)
  services.logind = {
    lidSwitch = "ignore";
    lidSwitchExternalPower = "ignore";
    lidSwitchDocked = "ignore";
  };

  # msi is the compute box: runs the heavy containers.
  gnomenav.role = "compute";

  # TTY-first main interface: boot lands in the zellij/yazi deck on tty1;
  # Hyprland exists only behind the `gui` command. See modules/tui-first.nix.
  gnomenav.tuiFirst.enable = true;

  # Telegram ↔ Claude gateway; secrets are real in secrets/secrets.yaml
  # (2026-07-14). allowFrom in the openclaw.json config volume, per
  # docs/TELEGRAM-OPENCLAW.md.
  gnomenav.openclaw.enable = true;

  # beets ran on the HOST in the old world (not a container) — revived the
  # same way 2026-07-19. Config: ~z/.config/beets/config.yaml (restored from
  # the SanDisk, paths updated /home/znav/nas -> /data); library db at
  # /data/beets_library.db.
  environment.systemPackages = [ pkgs.beets ];
  services.xserver.displayManager.autologin.enable = true;
  services.xserver.displayManager.autologin.user = "z";
}
