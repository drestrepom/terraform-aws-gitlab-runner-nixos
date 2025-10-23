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
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = var.availability_zones[0]

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
# NAT Gateway (for outbound Internet access)
# Cost: ~$32/month + traffic
# ============================================================================

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "nixos-ci-nat-eip"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.main]

  tags = {
    Name = "nixos-ci-nat-gateway"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

# Route table for runners (private → NAT)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
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
