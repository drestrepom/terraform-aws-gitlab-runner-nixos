{ config, pkgs, lib, modulesPath, ... }:

{
  imports =
    [ "${modulesPath}/virtualisation/amazon-image.nix" __NIX_CONFIG_IMPORT__ ];

  # Ensure EC2 user-data gets processed on boot
  virtualisation.amazon-init.enable = true;

  boot.loader.efi.canTouchEfiVariables = false;
  # Enable automatic partitioning for EC2
  boot.initrd.systemd.enable = true;

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
    awscli2
    cachix
    e2fsprogs
    util-linux
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
      concurrent = __CONCURRENT_JOBS__;
      check_interval = 10;
    };

    services = {
      "nixos-shell-runner" = {
        authenticationTokenConfigFile = "/etc/gitlab-runner-authentication.env";
        executor = "shell";
        buildsDir = "/var/lib/gitlab-runner-builds/builds";
      };
    };

    extraPackages = with pkgs; [ git curl wget ];
  };

  systemd.tmpfiles.rules =
    [ "d /var/lib/gitlab-runner-builds 755 gitlab-runner gitlab-runner -" ];

  # Setup GitLab Runner volume (format and mount)
  systemd.services.setup-gitlab-volume = {
    script = ''
      # Wait for the volume to be available
      while [ ! -b /dev/sdf ]; do
        echo "Waiting for /dev/sdf to be available..."
        sleep 2
      done

      # Check if the volume is already formatted
      if ! ${pkgs.util-linux}/bin/blkid /dev/sdf >/dev/null 2>&1; then
        echo "Formatting /dev/sdf as ext4..."
        ${pkgs.e2fsprogs}/bin/mkfs.ext4 -L gitlab-runner /dev/sdf
        echo "Volume formatted successfully"
      else
        echo "/dev/sdf is already formatted"
      fi

      # Mount the volume
      mkdir -p /var/lib/gitlab-runner-builds
      ${pkgs.util-linux}/bin/mount /dev/sdf /var/lib/gitlab-runner-builds
      echo "Volume mounted successfully"

      # Ensure builds directory has correct permissions
      mkdir -p /var/lib/gitlab-runner-builds/builds
      chown gitlab-runner:gitlab-runner /var/lib/gitlab-runner-builds/builds
      chmod 755 /var/lib/gitlab-runner-builds/builds

      echo "GitLab Runner volume setup completed"
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    wantedBy = [ "multi-user.target" ];
  };

  environment.etc."gitlab-runner-authentication.env" = {
    text = ''
      CI_SERVER_URL=__GITLAB_URL__
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
    script = ''
      __RUNNER_STATUS_SCRIPT__
    '';
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

  # Publish runner health to CloudWatch
  systemd.services.publish-runner-health = {
    script = ''
      __HEALTH_CHECK_SCRIPT__
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Environment = [
        "PATH=${pkgs.curl}/bin:${pkgs.jq}/bin:${pkgs.awscli2}/bin:/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
      ];
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  systemd.timers.publish-runner-health = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "60s";
    };
  };

  # Open HTTP port for health checks
  networking.firewall.allowedTCPPorts = [ 80 ];

  system.stateVersion = "25.05";
}
