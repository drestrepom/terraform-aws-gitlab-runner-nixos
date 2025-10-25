# Simple Example: Minimal GitLab Runner with Native Nix Support
#
# This example demonstrates the simplest possible setup with:
# - Minimal configuration
# - Cost-effective defaults
# - Single region deployment

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
  region = "us-east-1"
}

provider "gitlab" {
  token = var.gitlab_token
}

# Minimal module configuration
module "gitlab_runner" {
  source = "../../" # In production, use: github.com/your-org/terraform-aws-gitlab-runner-nixos

  # Required parameters
  environment       = "dev"
  gitlab_token      = var.gitlab_token
  gitlab_project_id = var.gitlab_project_id

  # Optional: Configure capacity (defaults shown)
  max_instances      = 5
  min_idle_instances = 0 # Most cost-effective

  # Tags
  tags = {
    Environment = "dev"
  }
}

# Outputs
output "autoscaling_group_name" {
  value = module.gitlab_runner.autoscaling_group_name
}

output "vpc_id" {
  value = module.gitlab_runner.vpc_id
}

output "scaling_status_command" {
  value = module.gitlab_runner.scaling_status_command
}

