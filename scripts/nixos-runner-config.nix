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

  systemd.tmpfiles.rules = [
    "d /var/lib/gitlab-runner-builds 755 gitlab-runner gitlab-runner -"
    "d /var/lib/gitlab-runner-builds/builds 755 gitlab-runner gitlab-runner -"
    "d /var/lib/gitlab-runner-builds/tmp 755 gitlab-runner gitlab-runner -"
  ];

  # Configure GitLab Runner service with proper environment variables
  systemd.services.gitlab-runner.serviceConfig = {
    Environment = [ "HOME=/var/lib/gitlab-runner" ];
    SupplementaryGroups = [ "nixbld" ];
    RequiresMountsFor = [ "/var/lib/gitlab-runner-builds" ];
  };

  systemd.services.gitlab-runner-volume-setup = {
    description = "Ensure GitLab Runner build volume directories";
    after = [ "var-lib-gitlab\\x2drunner\\x2dbuilds.mount" ];
    requires = [ "var-lib-gitlab\\x2drunner\\x2dbuilds.mount" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      install -d -m 755 -o gitlab-runner -g gitlab-runner /var/lib/gitlab-runner-builds
      install -d -m 755 -o gitlab-runner -g gitlab-runner /var/lib/gitlab-runner-builds/builds
      install -d -m 755 -o gitlab-runner -g gitlab-runner /var/lib/gitlab-runner-builds/tmp
    '';
  };

  # Ensure EBS volume is formatted once and mounted declaratively
  systemd.services.format-gitlab-volume = {
    description = "Format GitLab runner EBS volume";
    wantedBy = [ "local-fs.target" ];
    before = [ "var-lib-gitlab\\x2drunner\\x2dbuilds.mount" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      while [ ! -b /dev/sdf ]; do
        echo "Waiting for /dev/sdf to be available..."
        sleep 2
      done

      current_label=$(${pkgs.util-linux}/bin/blkid -s LABEL -o value /dev/sdf || true)
      if [ "$current_label" != "gitlab-runner" ]; then
        echo "Formatting /dev/sdf as ext4 with label gitlab-runner..."
        ${pkgs.e2fsprogs}/bin/mkfs.ext4 -F -L gitlab-runner /dev/sdf
      else
        echo "EBS volume already formatted with correct label"
      fi
    '';
  };

  fileSystems."/var/lib/gitlab-runner-builds" = {
    device = "/dev/disk/by-label/gitlab-runner";
    fsType = "ext4";
    options = [ "nofail" "x-systemd.device-timeout=2min" ];
    neededForBoot = false;
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
