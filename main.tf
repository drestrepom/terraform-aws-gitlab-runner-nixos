# ============================================
# Terraform Module: GitLab Runner with Native Nix Support
# ============================================
# This module creates auto-scaling GitLab runners on AWS with native
# Nix flake support - no Docker required!
#
# Key advantages:
# - Persistent Nix store across jobs (derivations are cached)
# - No Docker overhead
# - Spot instances for flexibility
# - Intelligent autoscaling based on job queue
# ============================================

# Get current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get default VPC and subnets (for public IP option)
data "aws_vpc" "default" {
  count   = local.internet_access_type == "public_ip" && var.vpc_id == "" ? 1 : 0
  default = true
}

data "aws_subnets" "default_vpc" {
  count = local.internet_access_type == "public_ip" && var.vpc_id == "" ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

# Use provided availability zones or default to region's AZs
locals {
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : [
    "${data.aws_region.current.id}a",
    "${data.aws_region.current.id}b"
  ]

  # Determine internet access type (backward compatibility)
  internet_access_type = var.enable_nat_gateway != null ? (
    var.enable_nat_gateway ? "nat_gateway" : "nat_instance"
  ) : var.internet_access_type

  # Determine if we need VPC (only for NAT options)
  need_vpc = local.internet_access_type != "public_ip"

  # Determine subnet IDs based on internet access type
  subnet_ids = local.internet_access_type == "public_ip" ? (
    # For public IP: use provided subnets or default VPC subnets
    length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default_vpc[0].ids
  ) : (
    # For NAT options: use created private subnets or provided subnets
    var.create_vpc ? aws_subnet.private[*].id : var.subnet_ids
  )

  # Determine VPC ID
  vpc_id = local.internet_access_type == "public_ip" ? (
    # For public IP: use provided VPC or default VPC
    var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  ) : (
    # For NAT options: use created VPC or provided VPC
    var.create_vpc ? aws_vpc.main[0].id : var.vpc_id
  )

  # Common tags for all resources
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "gitlab-runner-nixos"
    },
    var.tags
  )

  # Runner-specific tags
  runner_tags = merge(
    local.common_tags,
    var.runner_tags,
    {
      Component = "gitlab-runner"
    }
  )
}
