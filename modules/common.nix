{ config, pkgs, lib, ... }:
{
  # ---- Nix / flakes ----
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 30d"; };
  nixpkgs.config.allowUnfree = true;          # jellyfin, nvidia-free amd fine; needed for some firmware
  system.stateVersion = "25.05";

  # ---- Boot ----
  # Bootloader is per-host: msi is UEFI (systemd-boot), x220 is BIOS/legacy
  # (GRUB on /dev/sda). See hosts/<h>/default.nix.

  # ---- Networking ----
  networking.domain = "gnomenav.com";
  networking.networkmanager.enable = true;
  networking.firewall = {
    enable = true;
    # Only what we actually serve. Admin apps go through the tunnel, NOT open ports.
    allowedTCPPorts = [ 80 443 ];             # caddy; tailscale handles the rest
    # AdGuard DNS opened only on the host that runs it (see hosts/*/default.nix).
  };

  # ---- Identity-based SSH via Tailscale (replaces ssh.gnomenav.com) ----
  services.tailscale = { enable = true; useRoutingFeatures = "server"; };

  # ---- Hardened OpenSSH: keys only, no root pw, no defaults ----
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";   # key-only root for nixos-anywhere/rebuild
      X11Forwarding = false;
    };
  };

  # ---- Admin user: identity (uid/groups) lives in modules/users.nix; ----
  # ---- only authentication material stays here.                       ----
  users.mutableUsers = false;
  users.users.z = {
    # Replace with YOUR public key(s). Generate: ssh-keygen -t ed25519
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP/2U0OQTBbBWm7gmPJ1NpwjnVTli8bYj9pvVIKHe9e2 znav@zs-MacBook-Air.local"
    ];
  };
  # root gets the same key so nixos-anywhere can log in during install.
  users.users.root.openssh.authorizedKeys.keys =
    config.users.users.z.openssh.authorizedKeys.keys;

  security.sudo.wheelNeedsPassword = false;    # wheel via key-authenticated ssh only

  # ---- Secrets (sops-nix, age). Encrypted file is safe to commit. ----
  sops.defaultSopsFile = ../secrets/secrets.yaml;
  # secrets/secrets.yaml is committed sops-encrypted (placeholder values until
  # pre-install; see secrets/README.md and .sops.yaml for the key roster).
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";   # per-host, NEVER in git

  # ---- Baseline tooling ----
  environment.systemPackages = with pkgs; [
    git vim curl wget htop btop tmux rsync tree jq age sops
  ];

  # ---- Auto security updates: OFF until the repo actually lives on GitHub ----
  # (was enabled with a REPLACE_ME flake URL — a nightly-failing footgun).
  # Re-enable with the real URL when roadmap item "push to GitHub" lands.
  system.autoUpgrade = {
    enable = false;
    flake = "github:REPLACE_ME/nixos-homelab#${config.networking.hostName}";
    dates = "04:30";
    flags = [ "--update-input" "nixpkgs" "--no-write-lock-file" ];
  };

  time.timeZone = "America/New_York";
}
