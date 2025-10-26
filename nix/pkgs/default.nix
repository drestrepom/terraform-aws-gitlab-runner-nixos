{ inputs', inputs, lib', pkgs, self' }:
 {
  infra = import ./infra { inherit inputs' pkgs; };
  shellcheck = import ./shellcheck { inherit inputs' pkgs; };
}
