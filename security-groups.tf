# Security Group for NixOS Runner instances
resource "aws_security_group" "nixos_instance" {
  name        = "${var.environment}-nixos-runners-sg"
  description = "Security group for NixOS GitLab runners with native Nix support"
  vpc_id      = local.vpc_id

  # Health check ingress rule
  ingress {
    description = "Health check from within VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.create_vpc ? var.vpc_cidr : "10.0.0.0/8"]
  }

  # Egress rules - only what's needed for GitLab runners
  egress {
    description = "HTTPS to GitLab API"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP for package downloads"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Git SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "NTP"
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-nixos-runners-sg"
    }
  )
}

