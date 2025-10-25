# Discover latest NixOS arm64 AMI (owner: 427812963091)
data "aws_ami" "nixos_arm64" {
  owners      = ["427812963091"]
  most_recent = true

  filter {
    name   = "name"
    values = ["nixos/25.05*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

