{
  description = "NixOS flake and module for Pangolin reverse proxy and tunneling";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    flake-utils.lib.eachSystem supportedSystems (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages = {
          default = self.packages.${system}.pangolin;
          pangolin = pkgs.callPackage ./package.nix {
            fosrl-pangolin = pkgs.fosrl-pangolin;
            nodejs = pkgs.nodejs_22;
          };
          pangctl = pkgs.writeShellScriptBin "pangctl" ''
            exec ${self.packages.${system}.pangolin}/bin/pangctl "$@"
          '';
        };

        apps = {
          default = {
            type = "app";
            program = "${self.packages.${system}.pangolin}/bin/pangolin";
          };
          pangctl = {
            type = "app";
            program = "${self.packages.${system}.pangolin}/bin/pangctl";
          };
        };
      }
    )
    // {
      nixosModules = {
        default = self.nixosModules.pangolin;
        pangolin =
          { config, pkgs, ... }:
          {
            imports = [ ./module.nix ];
            services.pangolin.package = nixpkgs.lib.mkDefault self.packages.${pkgs.system}.pangolin;
          };
      };

      overlays.default = final: prev: {
        pangolin = self.packages.${prev.system}.pangolin;
      };
    };
}
