# ============================================================================
# Simple VPC for GitLab Runners
# Runners with private IPs → NAT Gateway → Internet (GitLab)
# ============================================================================

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "nixos-ci-vpc"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

# Internet Gateway (for NAT Gateway)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "nixos-ci-igw"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

# ============================================================================
# Public Subnet (only for NAT Gateway)
# ============================================================================

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "nixos-ci-nat-subnet"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "nixos-ci-public-rt"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ============================================================================
# Private Subnets (for runners)
# ============================================================================

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "nixos-ci-runner-subnet-${count.index + 1}"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

# ============================================================================
# NAT Instance (for outbound Internet access)
# Cost: ~$3.50/month (89% savings vs NAT Gateway)
# ============================================================================

# Get latest Amazon Linux 2 AMI for NAT
data "aws_ami" "nat_instance" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for NAT Instance (PERMISIVO TEMPORAL - PARA TESTING)
resource "aws_security_group" "nat_instance" {
  name        = "nixos-ci-nat-instance"
  description = "Security group for NAT Instance (PERMISSIVE FOR TESTING)"
  vpc_id      = aws_vpc.main.id

  # TEMPORAL: Allow ALL traffic from VPC (muy permisivo para testing)
  ingress {
    description = "ALL traffic from VPC (TEMPORAL)"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # Todo el VPC
  }

  ingress {
    description = "ALL UDP traffic from VPC (TEMPORAL)"
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]  # Todo el VPC
  }

  # TEMPORAL: Allow SSH from anywhere (para debugging)
  ingress {
    description = "SSH for debugging (TEMPORAL)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nixos-ci-nat-instance-sg-permissive"
    "comp" = "nixos-ci"
    "line" = "cost"
    "security" = "permissive-testing"
  }
}

# NAT Instance
resource "aws_instance" "nat" {
  ami                         = data.aws_ami.nat_instance.id
  instance_type              = var.nat_instance_type
  subnet_id                  = aws_subnet.public.id
  vpc_security_group_ids     = [aws_security_group.nat_instance.id]
  source_dest_check          = false
  associate_public_ip_address = true

  # User data to configure NAT functionality (ENHANCED FOR DEBUGGING)
  user_data_base64 = base64encode(<<-EOF
    #!/bin/bash
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
    echo "Starting NAT Instance configuration..."

    # Update system
    yum update -y

    # Enable IP forwarding
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
    sysctl -p /etc/sysctl.conf
    echo "IP forwarding enabled: $(cat /proc/sys/net/ipv4/ip_forward)"

    # Configure iptables for NAT (más permisivo para testing)
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -s 10.0.0.0/16 -j ACCEPT
    iptables -A FORWARD -j DROP

    # Save iptables rules
    iptables-save > /etc/sysconfig/iptables

    # Enable and start iptables service
    systemctl enable iptables
    systemctl start iptables

    # Install CloudWatch agent for monitoring
    yum install -y amazon-cloudwatch-agent

    # Create a simple health check endpoint
    yum install -y httpd
    systemctl enable httpd
    systemctl start httpd
    echo "NAT Instance is healthy - $(date)" > /var/www/html/health

    echo "NAT Instance configuration completed successfully!"
    echo "Current iptables rules:"
    iptables -L -n -v
    echo "NAT rules:"
    iptables -t nat -L -n -v
  EOF
  )

  tags = {
    Name = "nixos-ci-nat-instance"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

# Route table for runners (private → NAT Instance)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat.primary_network_interface_id
  }

  tags = {
    Name = "nixos-ci-private-rt"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
