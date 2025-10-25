# ============================================================================
# VPC for GitLab Runners (conditionally created)
# Runners with private IPs → NAT Instance/Gateway → Internet (GitLab)
# ============================================================================

# VPC
resource "aws_vpc" "main" {
  count = var.create_vpc ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-gitlab-runner-vpc"
    }
  )
}

# Internet Gateway (for NAT)
resource "aws_internet_gateway" "main" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-igw"
    }
  )
}

# ============================================================================
# Public Subnet (only for NAT Gateway)
# ============================================================================

resource "aws_subnet" "public" {
  count = var.create_vpc ? 1 : 0

  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = local.availability_zones[0]
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-public-subnet"
    }
  )
}

resource "aws_route_table" "public" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-public-rt"
    }
  )
}

resource "aws_route_table_association" "public" {
  count = var.create_vpc ? 1 : 0

  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}

# ============================================================================
# Private Subnets (for runners)
# ============================================================================

resource "aws_subnet" "private" {
  count = var.create_vpc ? length(local.availability_zones) : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.availability_zones[count.index]

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-private-subnet-${count.index + 1}"
    }
  )
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

# Security Group for NAT Instance
resource "aws_security_group" "nat_instance" {
  count = var.create_vpc && !var.enable_nat_gateway ? 1 : 0

  name        = "${var.environment}-nat-instance-sg"
  description = "Security group for NAT Instance"
  vpc_id      = aws_vpc.main[0].id

  # Allow all traffic from VPC for NAT functionality
  ingress {
    description = "All TCP traffic from VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "All UDP traffic from VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Optional SSH access for debugging
  dynamic "ingress" {
    for_each = length(var.allowed_ssh_cidr_blocks) > 0 ? [1] : []
    content {
      description = "SSH for debugging"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_ssh_cidr_blocks
    }
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-nat-instance-sg"
    }
  )
}

# NAT Instance
resource "aws_instance" "nat" {
  count = var.create_vpc && !var.enable_nat_gateway ? 1 : 0

  ami                         = data.aws_ami.nat_instance.id
  instance_type               = var.nat_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.nat_instance[0].id]
  source_dest_check           = false
  associate_public_ip_address = true

  # User data to configure NAT functionality
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

    # Configure iptables for NAT
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -s ${var.vpc_cidr} -j ACCEPT
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
  EOF
  )

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-nat-instance"
    }
  )
}

# NAT Gateway (alternative to NAT Instance)
resource "aws_eip" "nat" {
  count  = var.create_vpc && var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-nat-eip"
    }
  )
}

resource "aws_nat_gateway" "main" {
  count = var.create_vpc && var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-nat-gateway"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# Route table for runners (private → NAT)
resource "aws_route_table" "private" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  # Route to NAT Instance (if using NAT instance)
  dynamic "route" {
    for_each = !var.enable_nat_gateway ? [1] : []
    content {
      cidr_block           = "0.0.0.0/0"
      network_interface_id = aws_instance.nat[0].primary_network_interface_id
    }
  }

  # Route to NAT Gateway (if using NAT gateway)
  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-private-rt"
    }
  )
}

resource "aws_route_table_association" "private" {
  count = var.create_vpc ? length(aws_subnet.private) : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}
