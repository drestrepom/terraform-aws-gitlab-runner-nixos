{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [ "${modulesPath}/virtualisation/amazon-image.nix" ];

  boot.loader.efi.canTouchEfiVariables = false;
  # Enable automatic partitioning for EC2
  boot.initrd.systemd.enable = true;
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [ "https://cache.nixos.org" ];
    trusted-public-keys =
      [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
    trusted-users = [ "root" "ssm-user" ];
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
    procps
  ];

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "systemd-journal" "adm" ];
    shell = pkgs.bashInteractive;
  };

  # AWS Systems Manager Agent
  services.amazon-ssm-agent = { enable = true; };
  security.sudo.extraRules = [{
    users = [ "ssm-user" ];
    commands = [{
      command = "ALL";
      options = [ "NOPASSWD" ];
    }];
  }];
  # Ensure ssm-user has proper groups and permissions
  users.users.ssm-user.extraGroups =
    lib.mkAfter [ "systemd-journal" "adm" "wheel" "nixbld" ];

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

  # Nginx for health check endpoint
  services.nginx = {
    enable = true;

    # disable extra localhost status vhost to avoid shadowing our routes
    statusPage = false;

    virtualHosts."_" = {
      default = true;
      root = "/var/www";

      locations."= /health" = {
        extraConfig = ''
          access_log off;
          default_type application/json;
          try_files /health/status.json =503;
        '';
      };

      locations."= /runner-status" = {
        extraConfig = ''
          access_log off;
          default_type application/json;
          try_files /health/status.json =503;
        '';
      };
    };
  };

  # Systemd timer to update runner status file
  systemd.services.update-runner-status = {
    script = ''__RUNNER_STATUS_SCRIPT__'';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  systemd.timers.update-runner-status = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10s";
      OnUnitActiveSec = "30s";
    };
  };

  # Open HTTP port for health checks
  networking.firewall.allowedTCPPorts = [ 80 ];

  system.stateVersion = "25.05";
}
