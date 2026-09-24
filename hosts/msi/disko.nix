# Disk layout for msi — mirrors the live Arch layout (discovered 2026-07-14):
#   nvme0n1p1  2G   vfat  /boot (UEFI ESP)
#   nvme0n1p2  rest LUKS2 (aes-xts-plain64) -> btrfs
#     subvols: @ -> /, @home -> /home, @log -> /var/log, @nix -> /nix
#     (@nix replaces Arch's @pkg; same idea — keep the store out of / snapshots)
#   compress=zstd:3 everywhere, matching current fstab. Swap is zram (see
#   zramSwap in hosts/msi/default.nix), not a partition.
# LUKS passphrase comes from a key file so nixos-anywhere can run it
# non-interactively: create /tmp/disk.key ON THE INSTALL DRIVER (x220),
# chmod 600, and pass `--disk-encryption-keys /tmp/disk.key /tmp/disk.key`.
# The passphrase in that file is what gets typed at the msi console on boot.
{ ... }:
let
  btrfsOpts = [ "compress=zstd:3" "ssd" "space_cache=v2" "relatime" ];
in
{
  disko.devices.disk.main = {
    device = "/dev/nvme0n1";     # confirmed via lsblk 2026-07-14
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "2G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings.allowDiscards = true;
            # non-interactive format for nixos-anywhere; file created on the
            # install driver and shipped via --disk-encryption-keys
            passwordFile = "/tmp/disk.key";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@" = {
                  mountpoint = "/";
                  mountOptions = btrfsOpts;
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = btrfsOpts;
                };
                "@log" = {
                  mountpoint = "/var/log";
                  mountOptions = btrfsOpts;
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = btrfsOpts ++ [ "noatime" ];
                };
              };
            };
          };
        };
      };
    };
  };
}
