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
  description = "EC2 instance type for the Nix builder"
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
  default     = "104.30.134.27/32"
}
