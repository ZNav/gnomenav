# Install walkthrough — nixify x220 then msi

Runs as a command-loop: you run each block, paste output, I confirm before the
next. Destructive steps are flagged 🔴.

## Prereqs (on your Mac / control machine)
```bash
# Nix with flakes (Determinate installer is easiest):
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
# SSH key you'll use everywhere:
ssh-keygen -t ed25519 -C "z@gnomenav"          # if you don't have one
cat ~/.ssh/id_ed25519.pub                       # -> paste into modules/common.nix
```

## Phase 0 — DATA SAFETY 🔴 gate
```bash
# On BOTH machines (current OS):
bash scripts/data-inventory.sh > ~/inventory-$(hostname).txt
# Send both files back. We dedupe, then:
BACKUP_DEST=/mnt/<external-or-other-host> SRC_DIRS="<precious dirs>" \
  bash scripts/backup-precious.sh
# Do NOT continue until it prints "SAFE TO PROCEED" for that host.
```

## Phase 1 — confirm disk devices
```bash
lsblk -o NAME,SIZE,MODEL,SERIAL     # on each host
```
Match the real device into `hosts/<host>/disko.nix` (`/dev/nvme0n1` for msi,
`/dev/sda` for x220 — CONFIRM, don't assume).

## Phase 1.5 — dry-build BOTH configs (catch errors before wiping)
```bash
nix flake check                      # evaluates the flake
nix build .#nixosConfigurations.x220.config.system.build.toplevel --dry-run
nix build .#nixosConfigurations.msi.config.system.build.toplevel  --dry-run
```
Green here = the config evaluates. Fix any error now; a broken config after a wipe
means a machine that won't boot.

## Phase 2 — install x220 (guinea pig) 🔴 WIPES x220
From your control machine (x220 reachable by IP, current OS has sshd or boot the
NixOS minimal ISO):
```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#x220 --target-host root@<x220-ip>
```
nixos-anywhere kexecs into an installer, runs disko (partitions/formats), installs,
reboots. When it's back:
```bash
ssh z@<x220-ip>            # key-only; confirm you can log in
ssh z@<x220-ip> sudo nixos-generate-config --show-hardware-config  # -> commit real hw config
```
Bring up its containers (adguard, homepage, portainer, kiwix) — they auto-start.
Point your router DHCP DNS at x220. Verify adguard.gnomenav.com + dashboard.

## Phase 3 — install msi 🔴 WIPES msi
Only after x220 is confirmed good and msi's precious data is backed up + verified.
```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#msi --target-host root@<msi-ip>
```
Then: download the LLM model, restore container config volumes from backup
(nextcloud html/db, immich upload/db), verify each app.

**Nextcloud DB migration (discovered 2026-07-14):** the live Arch instance runs
**sqlite3**, but the Nix config declares MariaDB (`nextcloud-db`). Restoring the
old volume is NOT enough — either run `occ db:convert-type mysql nextcloud
nextcloud-db nextcloud` from the restored instance, or stand up fresh and
re-import data files. Decide before Phase 3.

## Phase 4 — secrets + cloudflare
```bash
# host age keys -> .sops.yaml, then fill secrets:
sops secrets/secrets.yaml
sudo nixos-rebuild switch --flake .#<host>    # re-run per host to pick up secrets
```
Then work through docs/CLOUDFLARE.md (tunnel token, Access policies, prune records).

## Day-2: change anything, anywhere
Edit the repo, then:
```bash
nixos-rebuild switch --flake .#msi  --target-host z@<msi-ip>  --use-remote-sudo
nixos-rebuild switch --flake .#x220 --target-host z@<x220-ip> --use-remote-sudo
```
This is "conductor from here": you drive both machines' OS from this one repo.
