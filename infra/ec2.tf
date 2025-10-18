# Create GitLab Runner
resource "gitlab_user_runner" "nixos_runner" {
  runner_type = "project_type"
  project_id  = var.gitlab_project_id

  description = var.gitlab_runner_description
  tag_list    = var.gitlab_runner_tags
  untagged    = var.gitlab_runner_untagged
}

# Create AWS Key Pair for NixOS instance
resource "aws_key_pair" "nixos_instance" {
  key_name   = "nixos-ci-instance"
  public_key = coalesce(var.nix_builder_authorized_key, file("${path.module}/nix_builder_key.pub"))

  tags = {
    Name                 = "nixos-ci-instance"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}



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

resource "aws_security_group" "nixos_instance" {
  name        = "nixos-ci-instance"
  description = "Security group for NixOS instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  dynamic "ingress" {
    for_each = var.nix_builder_ssh_cidr_blocks
    content {
      description = "Allow SSH from custom CIDR"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name                 = "nixos-ci-instance"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

locals {
  nixos_cloud_init = <<EOF
#!/usr/bin/env bash
exec > >(tee -a /dev/console) 2>&1
set -euxo pipefail

echo "=== NixOS GitLab Runner Auto-Configuration ==="
echo "Starting at: $(date)"

# Wait for network to be ready
echo "Waiting for network..."
sleep 10

# Update system first
echo "Updating system packages..."
nix-channel --update || true

mkdir -p /etc/nixos

# Write NixOS configuration with placeholder
echo "Writing NixOS configuration..."
cat > /etc/nixos/configuration.nix <<'NIXCONF'
${file("${path.module}/nixos-runner-config.nix")}
NIXCONF

# Replace placeholder with actual GitLab runner token
echo "Configuring GitLab runner token..."
sed -i 's|__GITLAB_RUNNER_TOKEN__|${gitlab_user_runner.nixos_runner.token}|g' /etc/nixos/configuration.nix

# Write public key for authorized_keys in Nix config
echo "Setting up SSH keys..."
cat > /etc/nixos/nix_builder_key.pub <<'PUBKEY'
${chomp(coalesce(var.nix_builder_authorized_key, file("${path.module}/nix_builder_key.pub")))}
PUBKEY
chmod 0644 /etc/nixos/nix_builder_key.pub

# Apply configuration with retries
echo "Applying NixOS configuration..."
for i in {1..3}; do
  echo "Attempt $i/3: Applying configuration..."
  if nixos-rebuild switch --show-trace; then
    echo "Configuration applied successfully!"
    break
  else
    echo "Configuration failed, retrying in 30 seconds..."
    sleep 30
  fi
done
EOF
}

resource "aws_instance" "nixos_instance" {
  ami                         = data.aws_ami.nixos_arm64.id
  instance_type               = var.nix_builder_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.nixos_instance.id]
  associate_public_ip_address = var.nix_builder_enable_public_ip
  key_name                    = aws_key_pair.nixos_instance.key_name

  user_data = local.nixos_cloud_init

  root_block_device {
    volume_size = var.nix_builder_disk_size
    volume_type = "gp3"
  }

  tags = {
    Name                 = "nixos-ci-instance"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

output "nixos_instance_public_ip" {
  value       = aws_instance.nixos_instance.public_ip
  description = "Public IP for the NixOS instance (if enabled)"
}

output "nixos_instance_private_ip" {
  value       = aws_instance.nixos_instance.private_ip
  description = "Private IP for the NixOS instance"
}

output "nixos_instance_ssh_command" {
  value       = "ssh -i infra/nix_builder_key root@${aws_instance.nixos_instance.public_ip}"
  description = "SSH command to connect to the NixOS instance"
}

# GitLab Runner outputs
output "gitlab_runner_id" {
  value       = gitlab_user_runner.nixos_runner.id
  description = "GitLab Runner ID"
}

output "gitlab_runner_token" {
  value       = gitlab_user_runner.nixos_runner.token
  description = "GitLab Runner authentication token"
  sensitive   = true
}

output "gitlab_runner_runner_type" {
  value       = gitlab_user_runner.nixos_runner.runner_type
  description = "GitLab Runner type"
}

