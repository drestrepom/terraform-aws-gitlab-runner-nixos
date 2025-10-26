{ inputs', pkgs }:
pkgs.writeShellApplication {
  name = "nix-lint";
  runtimeInputs = [
    pkgs.nixpkgs-fmt
    pkgs.nixfmt
  ];
  text = ''
    # shellcheck disable=SC1091
    source "${./main.sh}" "$@"
  '';
}
