{ inputs', pkgs }:
pkgs.writeShellApplication {
  name = "sifts-infra";
  runtimeInputs = [
    pkgs.terraform
    pkgs.tflint
    pkgs.terraform-docs
    pkgs.tfsec
    pkgs.checkov
    pkgs.shellcheck
    pkgs.awscli2
    pkgs.jq
    pkgs.curl
  ];
  text = ''
    # shellcheck disable=SC1091
    source "${./main.sh}" "$@"
  '';
}
