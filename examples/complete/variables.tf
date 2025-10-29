# Variables for the complete example

# ============================================
# AWS Configuration
# ============================================

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., production, staging, dev)"
  type        = string
  default     = "production"
}

# ============================================
# GitLab Configuration
# ============================================

variable "gitlab_url" {
  description = "GitLab instance URL"
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_token" {
  description = "GitLab Personal Access Token with 'create_runner' and 'read_api' scopes"
  type        = string
  sensitive   = true
}

variable "gitlab_project_id" {
  description = "GitLab Project ID where the runner will be registered"
  type        = number
}

# ============================================
# Networking Configuration
# ============================================

variable "internet_access_type" {
  description = "Type of internet access for GitLab runners. Options: 'public_ip' (each instance gets public IP), 'nat_instance' (use NAT instance), 'nat_gateway' (use NAT Gateway)"
  type        = string
  default     = "nat_instance"
  validation {
    condition     = contains(["public_ip", "nat_instance", "nat_gateway"], var.internet_access_type)
    error_message = "internet_access_type must be one of: public_ip, nat_instance, nat_gateway."
  }
}

# ============================================
# Capacity Configuration
# ============================================

variable "max_instances" {
  description = "Maximum number of runner instances"
  type        = number
  default     = 10
}

variable "min_idle_instances" {
  description = "Minimum number of idle instances to keep warm"
  type        = number
  default     = 1
}

variable "concurrent_jobs_per_instance" {
  description = "Number of concurrent jobs each runner can execute"
  type        = number
  default     = 2
}

# ============================================
# Instance Configuration
# ============================================

variable "instance_types" {
  description = "List of EC2 instance types to use"
  type        = list(string)
  default     = ["t4g.medium", "t4g.small", "c6g.medium"]
}

variable "root_volume_size" {
  description = "Size of the root volume in GB (for Nix store)"
  type        = number
  default     = 40
}

# ============================================
# Tags
# ============================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

