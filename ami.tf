# Discover latest NixOS AMI based on module configuration
data "aws_ami" "nixos_arm64" {
  owners      = [var.ami_owner]
  most_recent = true

  filter {
    name   = "name"
    values = var.ami_filter.name
  }

  filter {
    name   = "architecture"
    values = var.ami_filter.architecture
  }
}

