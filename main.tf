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

# Use provided availability zones or default to region's AZs
locals {
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : [
    "${data.aws_region.current.id}a",
    "${data.aws_region.current.id}b"
  ]

  # Determine if we need to create networking resources
  vpc_id     = var.create_vpc ? aws_vpc.main[0].id : var.vpc_id
  subnet_ids = var.create_vpc ? aws_subnet.private[*].id : var.subnet_ids

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
