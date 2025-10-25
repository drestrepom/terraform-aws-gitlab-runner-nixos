{ inputs', inputs, lib', pkgs, self' }:
 {
  infra = import ./infra { inherit inputs' pkgs; };
}
