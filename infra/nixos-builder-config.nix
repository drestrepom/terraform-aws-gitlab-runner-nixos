{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

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
    trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
  };

  environment.systemPackages = with pkgs; [
    git curl wget unzip gcc gnumake nix jq
  ];

  services.gitlab-runner = {
    enable = true;

    settings = {
      concurrent = 1;
      check_interval = 10;
    };

    services = {
      "nixos-shell-runner" = {
        registrationConfigFile = "/etc/gitlab-runner-registration.env";
        executor = "shell";
        tagList = [ "nixos" "arm64" "shell" ];
        runUntagged = false;
        registrationFlags = [ "--tag-list nixos,arm64,shell" ];
      };
    };
    extraPackages = with pkgs; [ git curl wget ];
  };

  environment.etc."gitlab-runner-registration.env".text = ''
    CI_SERVER_URL=https://gitlab.com
    REGISTRATION_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  '';

  # Enable SSH service
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
    openFirewall = true;
    permitRootLogin = "prohibit-password";
  };

  # Configure nixos user
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = [ (builtins.readFile "/etc/nixos/nix_builder_key.pub") ];
  };

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
