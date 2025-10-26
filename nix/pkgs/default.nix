{ inputs', inputs, lib', pkgs, self' }:
{
  infra = import ./infra { inherit inputs' pkgs; };
  shellcheck = import ./shellcheck { inherit inputs' pkgs; };
  nix-lint = import ./nix-lint { inherit inputs' pkgs; };
}
