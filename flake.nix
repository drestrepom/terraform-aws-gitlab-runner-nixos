{
  description = "GitLab Runner NixOS Infrastructure Management";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-schemas.url = "github:DeterminateSystems/flake-schemas";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      debug = false;

      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" "x86_64-darwin" ];

      # Global outputs
      flake = {
        schemas = inputs.flake-schemas.schemas;
      };

      perSystem = { inputs', pkgs, self', system, ... }:
        let
          projectPath = path: ./. + path;
          lib' = {
            inherit projectPath;
            terraform = import ./nix/lib/terraform.nix { inherit pkgs; };
          };
        in {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          # Main application
          apps.default = {
            type = "app";
            program = "${self'.packages.infra}/bin/sifts-infra";
          };

          # Development shell
          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              curl
              git
              jq
              wget
              nixpkgs-fmt
              terraform
              tflint
              terraform-docs
              tfsec
              checkov
              shellcheck
              awscli2
              patchelf
            ];
          };

          # Packages
          packages = import ./nix/pkgs { 
            inherit inputs' lib' pkgs inputs self'; 
          };
        };
    };
}
