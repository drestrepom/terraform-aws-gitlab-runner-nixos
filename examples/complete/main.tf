# Complete Example: GitLab Runner with Native Nix Support
#
# This example demonstrates a production-ready setup with:
# - Intelligent autoscaling based on GitLab API
# - Spot instances with multiple instance types
# - CloudWatch monitoring
# - SSM access for debugging

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

  # Spot instances
  spot_allocation_strategy = "price-capacity-optimized"

  # Networking
  create_vpc         = true
  enable_nat_gateway = false # Use NAT Instance

  # Autoscaling configuration
  scale_factor       = 1.0
  max_growth_rate    = 10
  scale_in_threshold = 0.3

  # Monitoring
  enable_cloudwatch_monitoring = true
  enable_ssm_access            = true

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
    file("${path.module}/nix-config.nix")
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

output "ssm_connect_command" {
  description = "Command to connect to a runner via SSM"
  value       = module.gitlab_runner.ssm_connect_command
}

output "scaling_status_command" {
  description = "Command to check scaling status"
  value       = module.gitlab_runner.scaling_status_command
}

output "cloudwatch_dashboard_url" {
  description = "URL to CloudWatch dashboard"
  value       = module.gitlab_runner.cloudwatch_dashboard_url
}

output "runner_config" {
  description = "Summary of runner configuration"
  value       = module.gitlab_runner.runner_config
}

