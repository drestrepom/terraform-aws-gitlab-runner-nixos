# Create GitLab Runner
resource "gitlab_user_runner" "nixos_runner" {
  runner_type = "project_type"
  project_id  = var.gitlab_project_id

  description = var.gitlab_runner_description
  tag_list    = var.gitlab_runner_tags
  untagged    = var.gitlab_runner_untagged
}

# Create AWS Key Pair for NixOS instance
resource "aws_key_pair" "nixos_instance" {
  key_name   = "nixos-ci-instance"
  public_key = coalesce(var.nix_builder_authorized_key, file("${path.module}/nix_builder_key.pub"))

  tags = {
    Name                 = "nixos-ci-instance"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

# IAM Role for SSM Agent
resource "aws_iam_role" "nixos_runner" {
  name = "nixos-runner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "nixos-runner-role"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

# Attach AWS managed policy for SSM
resource "aws_iam_role_policy_attachment" "nixos_runner_ssm" {
  role       = aws_iam_role.nixos_runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "nixos_runner" {
  name = "nixos-runner-profile"
  role = aws_iam_role.nixos_runner.name

  tags = {
    Name = "nixos-runner-profile"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

# Discover latest NixOS arm64 AMI (owner: 427812963091)
data "aws_ami" "nixos_arm64" {
  owners      = ["427812963091"]
  most_recent = true

  filter {
    name   = "name"
    values = ["nixos/25.05*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

resource "aws_security_group" "nixos_instance" {
  name        = "nixos-ci-instance"
  description = "Security group for NixOS instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  dynamic "ingress" {
    for_each = var.nix_builder_ssh_cidr_blocks
    content {
      description = "Allow SSH from custom CIDR"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name                 = "nixos-ci-instance"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

# La instancia individual se reemplaza por el Auto Scaling Group
# Ver archivo autoscaling.tf para la configuración completa

# Auto Scaling Group outputs
output "autoscaling_group_name" {
  value       = aws_autoscaling_group.nixos_runners.name
  description = "Name of the Auto Scaling Group"
}

output "autoscaling_group_arn" {
  value       = aws_autoscaling_group.nixos_runners.arn
  description = "ARN of the Auto Scaling Group"
}

output "launch_template_id" {
  value       = aws_launch_template.nixos_runner.id
  description = "ID of the Launch Template"
}

output "current_instances_count" {
  value       = "Use 'aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $(terraform output -raw autoscaling_group_name) --query \"AutoScalingGroups[0].Instances[?LifecycleState=='InService'] | length(@)\"' to get current count"
  description = "Command to get current number of instances in the ASG"
}

output "desired_capacity" {
  value       = aws_autoscaling_group.nixos_runners.desired_capacity
  description = "Desired capacity of the ASG"
}

# GitLab Runner outputs
output "gitlab_runner_id" {
  value       = gitlab_user_runner.nixos_runner.id
  description = "GitLab Runner ID"
}

output "gitlab_runner_token" {
  value       = gitlab_user_runner.nixos_runner.token
  description = "GitLab Runner authentication token"
  sensitive   = true
}

output "gitlab_runner_runner_type" {
  value       = gitlab_user_runner.nixos_runner.runner_type
  description = "GitLab Runner type"
}

