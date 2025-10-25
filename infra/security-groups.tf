# Security Group for NixOS Runner instances
resource "aws_security_group" "nixos_instance" {
  name        = "nixos-ci-runners"
  description = "Security group for NixOS GitLab runners in private subnets"
  vpc_id      = aws_vpc.main.id

  # Health check ingress rule
  ingress {
    description = "Health check from within VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # VPC CIDR
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

  tags = {
    Name = "nixos-ci-runners-sg"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

