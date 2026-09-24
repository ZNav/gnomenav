{
  description = "gnomenav homelab — declarative NixOS for msi + x220";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, sops-nix, ... }:
  let
    system = "x86_64-linux";
    mkHost = host: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit self; };
      modules = [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        ./modules/common.nix
        ./modules/users.nix
        ./modules/containers
        ./modules/prowlarr-autosort.nix
        ./modules/cloudflared.nix
        ./modules/rice.nix
        ./modules/tui-first.nix
        ./hosts/${host}
      ];
    };
  in {
    nixosConfigurations = {
      msi  = mkHost "msi";
      x220 = mkHost "x220";
    };
  };
}
