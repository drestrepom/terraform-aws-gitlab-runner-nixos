{ config, pkgs, ... }:

{
  # Boot configuration
  boot.loader.grub.enable = true;
  boot.loader.grub.devices = [ "/dev/xvda" ];

  # File systems
  fileSystems."/" = {
    device = "/dev/xvda1";
    fsType = "ext4";
  };

  # Enable SSH service
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.KbdInteractiveAuthentication = false;
  services.openssh.openFirewall = true;
  services.openssh.permitRootLogin = "prohibit-password";

  # Configure nixos user
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys =
      [ (builtins.readFile "/etc/nixos/nix_builder_key.pub") ];
  };

  # Allow root login via key
  users.users.root.openssh.authorizedKeys.keys =
    [ (builtins.readFile "/etc/nixos/nix_builder_key.pub") ];

  # Basic Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # Use binary caches for faster builds
    substituters = [ "https://cache.nixos.org" ];
    trusted-public-keys =
      [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
  };

  # Basic system configuration
  system.stateVersion = "25.05";
}
