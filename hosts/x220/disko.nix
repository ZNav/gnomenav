# Disk layout for x220 — mirrors the live Debian layout (discovered 2026-07-14):
#   sda1  ~1G  ext4  /boot   (unencrypted; GRUB can't unlock LUKS2 sanely)
#   sda5  rest LUKS -> LVM vg "x220-vg": swap 8G + root (ext4, 100%)
# IMPORTANT: this machine boots **BIOS/legacy**, not UEFI (live disk is MBR with
# an extended partition). We keep BIOS boot but move to GPT + a 1M EF02 BIOS-boot
# partition so GRUB can embed. Bootloader = GRUB on /dev/sda (hosts/x220/default.nix);
# systemd-boot from common.nix is force-disabled there.
# GOTCHA (hit 2026-07-14): the x220 firmware skips legacy-booting GPT disks
# unless the protective MBR has its boot flag set. After any re-partition, run:
#   parted /dev/sda disk_set pmbr_boot on
{ ... }:
{
  disko.devices.disk.main = {
    device = "/dev/sda";         # confirmed via lsblk 2026-07-14
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02";         # GRUB embed area for BIOS boot on GPT
        };
        boot = {
          size = "1G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/boot";
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings.allowDiscards = true;
            # Install-time passphrase source: nixos-anywhere ships the local
            # file here via --disk-encryption-keys /tmp/disk.key <file>.
            # NOTE: must sit at the luks-content level, NOT under `settings`
            # (settings maps straight onto boot.initrd.luks.devices.*, which
            # has no passwordFile option — dry-build caught this 2026-07-14).
            passwordFile = "/tmp/disk.key";
            content = {
              type = "lvm_pv";
              vg = "x220-vg";
            };
          };
        };
      };
    };
  };

  disko.devices.lvm_vg."x220-vg" = {
    type = "lvm_vg";
    lvs = {
      swap = {
        size = "8G";
        content = { type = "swap"; };
      };
      root = {
        size = "100%FREE";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/";
        };
      };
    };
  };
}
