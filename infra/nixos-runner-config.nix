{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.grub = {
    enable = true;
    devices = [ "/dev/nvme0n1" ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  boot.loader.efi.canTouchEfiVariables = false;
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [ "https://cache.nixos.org" ];
    trusted-public-keys =
      [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    unzip
    gcc
    gnumake
    nix
    jq
  ];

  # AWS Systems Manager Agent
  services.ssm-agent = { enable = true; };

  services.gitlab-runner = {
    enable = true;

    settings = {
      concurrent = 1;
      check_interval = 10;
    };

    services = {
      "nixos-shell-runner" = {
        authenticationTokenConfigFile = "/etc/gitlab-runner-authentication.env";
        executor = "shell";
      };
    };
    extraPackages = with pkgs; [ git curl wget ];
  };

  environment.etc."gitlab-runner-authentication.env" = {
    text = ''
      CI_SERVER_URL=https://gitlab.com
      CI_SERVER_TOKEN=__GITLAB_RUNNER_TOKEN__
    '';
    mode = "0400";
    user = "gitlab-runner";
    group = "gitlab-runner";
  };

  # SSH disabled - using SSM Agent for remote access
  services.openssh.enable = false;

  # Configure nixos user (no SSH keys needed)
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "systemd-journal" "adm" ];
    shell = pkgs.bashInteractive;
  };

  security.sudo.extraRules = [{
    users = [ "ssm-user" ];
    commands = [{
      command = "ALL";
      options = [ "NOPASSWD" ];
    }];
  }];

  users.users.ssm-user.extraGroups = lib.mkAfter [ "systemd-journal" "adm" ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/f222513b-ded1-49fa-b591-20ce86a2fe7f";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/12CE-A600";
    fsType = "vfat";
  };

  swapDevices = [ ];

  system.stateVersion = "25.05";
}
