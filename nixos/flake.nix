{
  description = "Gerhard's NixOs Manager System";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      # NixOS system configuration
      nixosConfigurations = {
        nix = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./configuration.nix
            home-manager.nixosModules.home-manager

            # Configure Home Manager user to import home.nix
            ({ config, lib, pkgs, ... }: {
              home-manager.users.{{username}} = { imports = [ ./home.nix ]; };
            })
          ];
        };
      };
    };
}
