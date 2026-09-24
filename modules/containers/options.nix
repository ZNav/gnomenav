{ lib, ... }:
{
  options.gnomenav = {
    role = lib.mkOption {
      type = lib.types.enum [ "compute" "utility" ];
      default = "compute";
      description = "compute = msi (heavy stacks); utility = x220 (dns/proxy/light)";
    };
    dataRoot = lib.mkOption { type = lib.types.str; default = "/data"; };
    configRoot = lib.mkOption { type = lib.types.str; default = "/var/lib/appdata"; };
  };
}
