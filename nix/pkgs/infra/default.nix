{ inputs', pkgs }:
pkgs.writeShellApplication {
  name = "infra";
  runtimeInputs = [
    pkgs.terraform
    pkgs.tflint
  ];
  text = ''
    # shellcheck disable=SC1091
    source "${./main.sh}" "$@"
  '';
}
