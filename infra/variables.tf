# ============================================
# ESSENTIAL CONFIGURATION (required)
# ============================================

# AWS Credentials
variable "aws_access_key" {
  description = "AWS Access Key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Access Key"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# GitLab Configuration
variable "gitlab_token" {
  description = "GitLab Personal Access Token with 'create_runner' scope"
  type        = string
  sensitive   = true
}

variable "gitlab_project_id" {
  description = "GitLab Project ID where the runner will be created"
  type        = number
}

variable "gitlab_url" {
  description = "GitLab URL (defaults to gitlab.com)"
  type        = string
  default     = "https://gitlab.com"
}

# ============================================
# CAPACITY CONFIGURATION (important)
# ============================================

variable "max_size" {
  description = "Maximum number of runners autoscaling can create"
  type        = number
  default     = 10
}

variable "concurrent_jobs_per_instance" {
  description = "How many jobs each runner can execute simultaneously"
  type        = number
  default     = 1
  validation {
    condition     = var.concurrent_jobs_per_instance > 0
    error_message = "concurrent_jobs_per_instance must be greater than 0"
  }
}

variable "min_idle_instances" {
  description = "Minimum number of idle runners to always keep on (0 = most cost effective)"
  type        = number
  default     = 0
  validation {
    condition     = var.min_idle_instances >= 0
    error_message = "min_idle_instances must be 0 or greater"
  }
}

# ============================================
# ADVANCED CONFIGURATION (optional)
# ============================================

variable "on_demand_percentage" {
  description = "Percentage of on-demand instances vs spot (10 = 90% spot, more cost effective)"
  type        = number
  default     = 10
  validation {
    condition     = var.on_demand_percentage >= 0 && var.on_demand_percentage <= 100
    error_message = "on_demand_percentage must be between 0 and 100"
  }
}

variable "instance_types" {
  description = "ARM64 instance types for the runner (AWS will choose the cheapest available)"
  type        = list(string)
  default     = ["t4g.medium", "t4g.small", "c6g.medium", "c7g.medium", "m6g.medium"]
}

# ============================================
# INTERNAL VALUES (do not modify)
# ============================================

variable "min_size" {
  description = "Minimum instances in the ASG (managed by lambda)"
  type        = number
  default     = 0
}

variable "desired_capacity" {
  description = "Initial capacity of the ASG (lambda will adjust automatically)"
  type        = number
  default     = 0
}

variable "health_check_grace_period" {
  description = "Grace period before health checks (seconds)"
  type        = number
  default     = 300
}

variable "health_check_type" {
  description = "Type of health check"
  type        = string
  default     = "EC2"
}

variable "nix_builder_disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 20
}

variable "gitlab_runner_description" {
  description = "Runner description in GitLab"
  type        = string
  default     = "NixOS ARM64 Autoscaled Runner"
}

variable "gitlab_runner_tags" {
  description = "Runner tags"
  type        = list(string)
  default     = ["nixos", "arm64", "shell"]
}

variable "gitlab_runner_untagged" {
  description = "Whether the runner accepts untagged jobs"
  type        = bool
  default     = true
}


# Networking (hardcoded in vpc.tf)
variable "availability_zones" {
  description = "Availability zones for the runners"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# Deprecated but kept for compatibility
variable "account_id" {
  description = "[DEPRECATED] No need to configure manually"
  type        = string
  default     = ""
}

variable "spot_price" {
  description = "[DEPRECATED] Use on_demand_percentage instead"
  type        = string
  default     = ""
}

variable "max_capacity" {
  description = "[DEPRECATED] Use max_size instead"
  type        = number
  default     = 50
}
