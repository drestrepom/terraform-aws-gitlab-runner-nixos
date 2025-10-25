# ============================================
# MODULE OUTPUTS
# ============================================

# ============================================
# GitLab Runner
# ============================================

output "gitlab_runner_id" {
  value       = gitlab_user_runner.nixos_runner.id
  description = "GitLab Runner ID (visible in GitLab UI)"
}

output "gitlab_runner_token" {
  value       = gitlab_user_runner.nixos_runner.token
  description = "GitLab Runner authentication token (automatically generated)"
  sensitive   = true
}

output "gitlab_runner_type" {
  value       = gitlab_user_runner.nixos_runner.runner_type
  description = "GitLab Runner type (project_type)"
}

output "gitlab_project_id" {
  value       = var.gitlab_project_id
  description = "GitLab Project ID where the runner is registered"
}

# ============================================
# Auto Scaling Group
# ============================================

output "autoscaling_group_name" {
  value       = aws_autoscaling_group.nixos_runners.name
  description = "Name of the Auto Scaling Group managing the GitLab runners"
}

output "autoscaling_group_arn" {
  value       = aws_autoscaling_group.nixos_runners.arn
  description = "ARN of the Auto Scaling Group managing the GitLab runners"
}

output "launch_template_id" {
  value       = aws_launch_template.nixos_runner.id
  description = "ID of the Launch Template used by runner instances"
}

output "launch_template_latest_version" {
  value       = aws_launch_template.nixos_runner.latest_version
  description = "Latest version number of the Launch Template"
}

# ============================================
# IAM Roles and Profiles
# ============================================

output "runner_iam_role_name" {
  value       = aws_iam_role.nixos_runner.name
  description = "Name of the IAM role used by runner instances"
}

output "runner_iam_role_arn" {
  value       = aws_iam_role.nixos_runner.arn
  description = "ARN of the IAM role used by runner instances"
}

output "runner_instance_profile_name" {
  value       = aws_iam_instance_profile.nixos_runner.name
  description = "Name of the IAM instance profile attached to runner instances"
}

output "runner_instance_profile_arn" {
  value       = aws_iam_instance_profile.nixos_runner.arn
  description = "ARN of the IAM instance profile attached to runner instances"
}

# ============================================
# Security Groups
# ============================================

output "runner_security_group_id" {
  value       = aws_security_group.nixos_instance.id
  description = "ID of the security group attached to runner instances"
}

output "runner_security_group_name" {
  value       = aws_security_group.nixos_instance.name
  description = "Name of the security group attached to runner instances"
}

# ============================================
# Networking
# ============================================

output "vpc_id" {
  value       = local.vpc_id
  description = "ID of the VPC where runners are deployed"
}

output "subnet_ids" {
  value       = local.subnet_ids
  description = "IDs of the subnets where runner instances are deployed"
}

output "nat_instance_id" {
  value       = var.create_vpc && !var.enable_nat_gateway ? aws_instance.nat[0].id : null
  description = "Instance ID of the NAT instance (if NAT instance is used)"
}

output "nat_instance_public_ip" {
  value       = var.create_vpc && !var.enable_nat_gateway ? aws_instance.nat[0].public_ip : null
  description = "Public IP of the NAT instance (if NAT instance is used)"
}

output "nat_gateway_id" {
  value       = var.create_vpc && var.enable_nat_gateway ? aws_nat_gateway.main[0].id : null
  description = "ID of the NAT Gateway (if NAT Gateway is used)"
}

# ============================================
# Lambda Function (Autoscaling)
# ============================================

output "lambda_function_name" {
  value       = var.enable_gitlab_metrics ? aws_lambda_function.gitlab_metrics_collector[0].function_name : null
  description = "Name of the Lambda function that handles autoscaling"
}

output "lambda_function_arn" {
  value       = var.enable_gitlab_metrics ? aws_lambda_function.gitlab_metrics_collector[0].arn : null
  description = "ARN of the Lambda function that handles autoscaling"
}

output "lambda_role_arn" {
  value       = var.enable_gitlab_metrics ? aws_iam_role.lambda_execution_role[0].arn : null
  description = "ARN of the IAM role used by the Lambda function"
}

# ============================================
# Monitoring
# ============================================

output "cloudwatch_log_group" {
  value       = var.enable_cloudwatch_monitoring ? "/aws/lambda/${var.enable_gitlab_metrics ? aws_lambda_function.gitlab_metrics_collector[0].function_name : ""}" : null
  description = "CloudWatch log group for Lambda function logs"
}

output "cloudwatch_dashboard_url" {
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.id}#metricsV2:graph=~();namespace=GitLab"
  description = "URL to view GitLab runner metrics in CloudWatch console"
}

# ============================================
# AMI Information
# ============================================

output "nixos_ami_id" {
  value       = data.aws_ami.nixos_arm64.id
  description = "ID of the NixOS AMI used for runner instances"
}

output "nixos_ami_name" {
  value       = data.aws_ami.nixos_arm64.name
  description = "Name of the NixOS AMI used for runner instances"
}

# ============================================
# Configuration
# ============================================

output "runner_config" {
  value = {
    environment          = var.environment
    max_instances        = var.max_instances
    min_idle_instances   = var.min_idle_instances
    concurrent_jobs      = var.concurrent_jobs_per_instance
    instance_types       = var.instance_types
    on_demand_percentage = var.on_demand_percentage
  }
  description = "Summary of runner configuration"
}

# ============================================
# Helper Commands
# ============================================

output "ssm_connect_command" {
  value       = var.enable_ssm_access ? "aws ssm start-session --target <instance-id> --region ${data.aws_region.current.id}" : "SSM access is disabled"
  description = "AWS CLI command to connect to a runner instance via Systems Manager"
}

output "scaling_status_command" {
  value       = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.nixos_runners.name} --region ${data.aws_region.current.id} --query 'AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize,Instances[?LifecycleState==`InService`]|length(@)]' --output table"
  description = "AWS CLI command to check current scaling status"
}

output "lambda_logs_command" {
  value       = var.enable_gitlab_metrics ? "aws logs tail /aws/lambda/${aws_lambda_function.gitlab_metrics_collector[0].function_name} --follow --region ${data.aws_region.current.id}" : "GitLab metrics collection is disabled"
  description = "AWS CLI command to tail Lambda function logs"
}
