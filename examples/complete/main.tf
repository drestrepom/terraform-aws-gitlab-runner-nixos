# Complete Example: GitLab Runner with Native Nix Support
#
# This example demonstrates a production-ready setup with:
# - Intelligent autoscaling based on GitLab API
# - 100% spot instances with multiple instance types for cost optimization

terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = ">= 16.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "gitlab" {
  token    = var.gitlab_token
  base_url = var.gitlab_url
}

# Use the GitLab Runner module
module "gitlab_runner" {
  source = "../../" # In production, use: github.com/your-org/terraform-aws-gitlab-runner-nixos

  # Environment configuration
  environment = var.environment

  # GitLab configuration (runner created automatically)
  gitlab_url        = var.gitlab_url
  gitlab_token      = var.gitlab_token
  gitlab_project_id = var.gitlab_project_id

  # GitLab API for intelligent autoscaling (uses same token)
  enable_gitlab_metrics = true

  # Runner configuration
  gitlab_runner_description = "NixOS Auto-Scaled Runner - ${var.environment}"
  gitlab_runner_tags        = ["nixos", "nix", "arm64", "shell", var.environment]
  gitlab_runner_untagged    = false

  # Capacity configuration
  max_instances                = var.max_instances
  min_idle_instances           = var.min_idle_instances
  concurrent_jobs_per_instance = var.concurrent_jobs_per_instance

  # Instance configuration
  instance_types   = var.instance_types
  root_volume_size = var.root_volume_size

  # Note: gitlab_runner_volume_size and gitlab_runner_volume_type use module defaults

  # Spot instances
  spot_allocation_strategy = "price-capacity-optimized"

  # Networking
  # Three internet access options:
  # 1. "public_ip" - Each runner gets a public IP (simplest, but less secure)
  # 2. "nat_instance" - Use a NAT instance (cost-effective, good for dev/test)
  # 3. "nat_gateway" - Use AWS NAT Gateway (most reliable, recommended for production)
  internet_access_type = var.internet_access_type
  
  # VPC configuration (only needed for NAT options)
  create_vpc = var.internet_access_type != "public_ip"
  vpc_cidr   = "10.0.0.0/16"
  
  # Deprecated: Use internet_access_type instead
  enable_nat_gateway = var.internet_access_type == "nat_gateway"

  # Autoscaling configuration
  scale_factor       = 1.0
  max_growth_rate    = 10
  scale_in_threshold = 0.3

  # Tags
  tags = merge(
    var.additional_tags,
    {
      Environment = var.environment
      Project     = "gitlab-ci"
      ManagedBy   = "Terraform"
    }
  )

  runner_tags = {
    Purpose = "gitlab-runner"
  }

  additional_nixos_configs = [
    file("${path.module}/nix-config.nix"),
    file("${path.module}/cachix-config.nix")
  ]
}

# Outputs
output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = module.gitlab_runner.autoscaling_group_name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.gitlab_runner.vpc_id
}

output "runner_security_group_id" {
  description = "ID of the runner security group"
  value       = module.gitlab_runner.runner_security_group_id
}

output "nat_instance_ip" {
  description = "Public IP of the NAT instance"
  value       = module.gitlab_runner.nat_instance_public_ip
}

output "runner_config" {
  description = "Summary of runner configuration"
  value       = module.gitlab_runner.runner_config
}

