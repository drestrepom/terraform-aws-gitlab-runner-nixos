{ inputs', pkgs }:
pkgs.writeShellApplication {
  name = "shellcheck-lint";
  runtimeInputs = [
    pkgs.shellcheck
    pkgs.shfmt
  ];
  text = ''
    # shellcheck disable=SC1091
    source "${./main.sh}" "$@"
  '';
}