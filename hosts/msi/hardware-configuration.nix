# PLACEHOLDER. Generated on the box during install:
#   nixos-generate-config --show-hardware-config  (nixos-anywhere does this for you)
# Commit the real one after first install.
{ config, lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "usbhid" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];
  nixpkgs.hostPlatform = "x86_64-linux";
}
