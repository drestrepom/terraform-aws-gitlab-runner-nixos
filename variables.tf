# ============================================
# MODULE CONFIGURATION
# ============================================

variable "environment" {
  description = "A name that identifies the environment, used as prefix and for tagging (e.g., 'production', 'staging', 'dev')"
  type        = string
}

variable "vpc_id" {
  description = "The VPC ID where the GitLab runners will be deployed. If not provided, a new VPC will be created."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of private subnet IDs where the GitLab runners will be deployed. If not provided, new subnets will be created."
  type        = list(string)
  default     = []
}

# ============================================
# GITLAB CONFIGURATION (required)
# ============================================

variable "gitlab_url" {
  description = "GitLab URL (defaults to gitlab.com)"
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_token" {
  description = "GitLab Personal Access Token with 'create_runner' scope (or admin privileges). The module will automatically create the runner."
  type        = string
  sensitive   = true
}

variable "gitlab_project_id" {
  description = "GitLab Project ID where the runner will be registered. Find this in Project Settings → General."
  type        = number
}

variable "gitlab_runner_description" {
  description = "Runner description that will appear in GitLab"
  type        = string
  default     = "NixOS ARM64 Autoscaled Runner"
}

variable "gitlab_runner_tags" {
  description = "Tags to assign to the GitLab runner"
  type        = list(string)
  default     = ["nixos", "nix", "arm64", "shell"]
}

variable "gitlab_runner_untagged" {
  description = "Whether the runner accepts untagged jobs"
  type        = bool
  default     = false
}

# ============================================
# AWS CONFIGURATION
# ============================================

variable "availability_zones" {
  description = "List of availability zones for the runners. If not provided, defaults will be used based on region."
  type        = list(string)
  default     = []
}

# ============================================
# RUNNER INSTANCE CONFIGURATION
# ============================================

variable "instance_types" {
  description = "List of instance types for the runner. The first available will be used. Supports ARM64 instance types."
  type        = list(string)
  default     = ["t4g.medium", "t4g.small", "c6g.medium", "c7g.medium", "m6g.medium"]
}

variable "ami_filter" {
  description = "AMI filter for selecting the NixOS AMI. Default searches for NixOS 25.05 ARM64 images."
  type = object({
    name         = list(string)
    architecture = list(string)
  })
  default = {
    name         = ["nixos/25.05*"]
    architecture = ["arm64"]
  }
}

variable "ami_owner" {
  description = "AWS account ID that owns the NixOS AMI"
  type        = string
  default     = "427812963091" # Official NixOS account
}

variable "root_volume_size" {
  description = "Size of the root volume in GB. Nix store requires significant space for builds."
  type        = number
  default     = 40

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "Root volume size must be at least 20 GB for Nix operations."
  }
}

variable "root_volume_type" {
  description = "Type of the root volume (gp2, gp3, io1, io2)"
  type        = string
  default     = "gp3"
}

variable "gitlab_runner_volume_size" {
  description = "Size of the additional EBS volume for GitLab Runner builds in GB"
  type        = number
  default     = 100

  validation {
    condition     = var.gitlab_runner_volume_size >= 100
    error_message = "GitLab Runner volume size must be at least 100 GB for builds and cache."
  }
}

variable "gitlab_runner_volume_type" {
  description = "Type of the GitLab Runner volume (gp2, gp3, io1, io2)"
  type        = string
  default     = "gp3"
}

# ============================================
# AUTOSCALING CONFIGURATION
# ============================================

variable "concurrent_jobs_per_instance" {
  description = "Number of concurrent jobs each runner instance can execute"
  type        = number
  default     = 2

  validation {
    condition     = var.concurrent_jobs_per_instance > 0
    error_message = "concurrent_jobs_per_instance must be greater than 0"
  }
}

variable "min_idle_instances" {
  description = "Minimum number of idle runner instances to keep warm"
  type        = number
  default     = 0

  validation {
    condition     = var.min_idle_instances >= 0
    error_message = "min_idle_instances must be 0 or greater"
  }
}

variable "max_instances" {
  description = "Maximum number of runner instances the autoscaling group can create"
  type        = number
  default     = 10

  validation {
    condition     = var.max_instances > 0
    error_message = "max_instances must be greater than 0"
  }
}

variable "min_instances" {
  description = "Minimum number of runner instances in the autoscaling group"
  type        = number
  default     = 0
}

variable "desired_capacity" {
  description = "Initial desired capacity of the autoscaling group (will be adjusted by Lambda)"
  type        = number
  default     = 0
}

# ============================================
# SPOT INSTANCES CONFIGURATION
# ============================================

variable "spot_allocation_strategy" {
  description = "How to allocate capacity across spot pools. 'price-capacity-optimized' balances price and availability."
  type        = string
  default     = "price-capacity-optimized"

  validation {
    condition     = contains(["lowest-price", "capacity-optimized", "price-capacity-optimized"], var.spot_allocation_strategy)
    error_message = "spot_allocation_strategy must be one of: lowest-price, capacity-optimized, price-capacity-optimized"
  }
}

# ============================================
# AUTOSCALING ALGORITHM PARAMETERS
# ============================================

variable "scale_factor" {
  description = "Scaling factor for pending jobs (1.0 = create instance for every pending job)"
  type        = number
  default     = 1.0

  validation {
    condition     = var.scale_factor > 0 && var.scale_factor <= 2.0
    error_message = "scale_factor must be between 0 and 2.0"
  }
}

variable "max_growth_rate" {
  description = "Maximum number of instances to add per scaling iteration"
  type        = number
  default     = 10
}

variable "scale_in_threshold" {
  description = "Minimum utilization percentage before scaling in (e.g., 0.3 = scale in when < 30% utilized)"
  type        = number
  default     = 0.3

  validation {
    condition     = var.scale_in_threshold >= 0 && var.scale_in_threshold <= 1.0
    error_message = "scale_in_threshold must be between 0 and 1.0"
  }
}

variable "lambda_check_interval" {
  description = "How often the Lambda function checks for scaling needs (in minutes, minimum 1)"
  type        = number
  default     = 1

  validation {
    condition     = var.lambda_check_interval >= 1
    error_message = "lambda_check_interval must be at least 1 minute"
  }
}

# ============================================
# NETWORKING CONFIGURATION
# ============================================

variable "create_vpc" {
  description = "Whether to create a new VPC for the runners. Set to false if providing existing vpc_id and subnet_ids."
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (only used if create_vpc is true)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Use AWS NAT Gateway instead of NAT instance"
  type        = bool
  default     = false
}

variable "nat_instance_type" {
  description = "Instance type for NAT instance (only used if enable_nat_gateway is false)"
  type        = string
  default     = "t3.nano"
}

# ============================================
# GITLAB API ACCESS (for metrics collection)
# ============================================

variable "enable_gitlab_metrics" {
  description = "Enable GitLab API metrics collection for intelligent autoscaling. Uses the same gitlab_token provided above."
  type        = bool
  default     = true
}

# ============================================
# SECURITY CONFIGURATION
# ============================================

variable "enable_ssm_access" {
  description = "Enable AWS Systems Manager (SSM) access to runner instances for debugging"
  type        = bool
  default     = true
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to NAT instance (for debugging). Leave empty for no SSH access."
  type        = list(string)
  default     = []
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs to attach to runner instances"
  type        = list(string)
  default     = []
}

# ============================================
# MONITORING CONFIGURATION
# ============================================

variable "enable_cloudwatch_monitoring" {
  description = "Enable detailed CloudWatch monitoring for runner instances and health checks"
  type        = bool
  default     = true
}

variable "health_check_grace_period" {
  description = "Time (in seconds) after instance comes into service before checking health"
  type        = number
  default     = 300
}

variable "health_check_type" {
  description = "Type of health check for autoscaling group (EC2 or ELB)"
  type        = string
  default     = "EC2"

  validation {
    condition     = contains(["EC2", "ELB"], var.health_check_type)
    error_message = "health_check_type must be either EC2 or ELB"
  }
}

# ============================================
# TAGGING
# ============================================

variable "tags" {
  description = "Additional tags to apply to all resources created by this module"
  type        = map(string)
  default     = {}
}

variable "runner_tags" {
  description = "Additional tags to apply specifically to runner instances"
  type        = map(string)
  default     = {}
}

# ============================================
# ADVANCED CONFIGURATION
# ============================================

variable "additional_nixos_configs" {
  description = "List of additional NixOS configuration blocks to import. Each item should be a valid NixOS configuration block that can be imported."
  type        = list(string)
  default     = []
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda function in MB"
  type        = number
  default     = 128
}

# ============================================
# LIFECYCLE CONFIGURATION
# ============================================

variable "instance_termination_timeout" {
  description = "Timeout in seconds for graceful instance termination (allows running jobs to complete)"
  type        = number
  default     = 300
}

variable "enable_instance_refresh" {
  description = "Enable automatic instance refresh when launch template changes"
  type        = bool
  default     = true
}
