# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "account_id" {
  default = "205810638802"
  type    = string
}

variable "region" {
  default = "us-east-1"
  type    = string
}

variable "nix_builder_instance_type" {
  description = "EC2 instance type for the Nix builder (smallest available ARM64 for testing)"
  type        = string
  default     = "t4g.medium"
}

variable "nix_builder_disk_size" {
  description = "Disk size in GB for the Nix builder"
  type        = number
  default     = 20
}

variable "nix_builder_enable_public_ip" {
  description = "Whether to assign a public IP to the Nix builder"
  type        = bool
  default     = true
}

# Auto Scaling Group Configuration
variable "min_size" {
  description = "Minimum number of instances in the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances in the Auto Scaling Group"
  type        = number
  default     = 10
}

variable "desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "spot_price" {
  description = "Maximum price for spot instances (leave empty for on-demand price)"
  type        = string
  default     = ""
}

variable "health_check_grace_period" {
  description = "Time after instance launch before health checks begin"
  type        = number
  default     = 300
}

variable "health_check_type" {
  description = "Type of health check to perform"
  type        = string
  default     = "EC2"
}

variable "nix_builder_authorized_key" {
  description = "Public key for SSH access to the Nix builder (optional, will use nix_builder_key.pub if not provided)"
  type        = string
  default     = null
}

variable "nix_builder_ssh_cidr_blocks" {
  description = "Additional CIDR blocks allowed for SSH access to the NixOS instance"
  type        = list(string)
  default     = []
}

variable "admin_ip" {
  description = "Your public IP address for SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

# GitLab Configuration
variable "gitlab_token" {
  description = "GitLab Personal Access Token with 'create_runner' scope"
  type        = string
  sensitive   = true
}

variable "gitlab_url" {
  description = "GitLab URL"
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_project_id" {
  description = "GitLab Project ID where the runner will be created"
  type        = number
}

# GitLab Runner Configuration
variable "gitlab_runner_description" {
  description = "Description for the GitLab runner"
  type        = string
  default     = "NixOS ARM64 Shell Runner"
}

variable "gitlab_runner_tags" {
  description = "Tags for the GitLab runner"
  type        = list(string)
  default     = ["nixos", "arm64", "shell"]
}

variable "gitlab_runner_untagged" {
  description = "Whether the runner should run untagged jobs"
  type        = bool
  default     = true
}
