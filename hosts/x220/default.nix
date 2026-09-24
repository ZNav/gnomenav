{ config, pkgs, lib, ... }:
{
  imports = [ ./disko.nix ./hardware-configuration.nix ];
  networking.hostName = "x220";

  # X220 boots BIOS/legacy (live Debian disk is MBR) — GRUB, not systemd-boot.
  # disko fills boot.loader.grub.devices from the EF02 partition —
  # setting `device` here too would duplicate it (mirroredBoots assertion).
  boot.loader.grub.enable = true;

  # ThinkPad X220 — utility box: DNS/adblock + proxy + light services.
  gnomenav.role = "utility";

  # Ricing + offensive-security console (modules/rice.nix). Large closure —
  # dry-build before switch (see the GATE note in rice.nix).
  gnomenav.rice.enable = true;

  # Console-only login for z: this box is WiFi-attached until it gets a
  # permanent cable, and WiFi creds are not declared — first boot needs a
  # keyboard login to run `nmtui`. SSH stays key-only (common.nix hardening).
  users.users.z.hashedPassword = "$6$vosYFwhIwu0OOd0t$ZXc05rrMtBLnx7JTTdhKgmHsWyPnNhHpl0bXU22KSZjw..8KwNMXePnoX3l5EJVWvBPzBtsqKiJBT9vpmGgeR/";

  # AdGuard runs here; open DNS only on this host.
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  # navdeck: console TUI launcher (jellyfin via mpv on DRM, w3m browser).
  # Script deployed to /home/z/navdeck.py; Sandy Bridge vaapi for hw decode.
  environment.systemPackages = with pkgs; [ python3 mpv w3m ];
  hardware.graphics = {
    enable = true;
    extraPackages = [ pkgs.intel-vaapi-driver ];
  };
}
