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

# NAT Instance outputs
output "nat_instance_ip" {
  value       = aws_instance.nat.public_ip
  description = "Public IP of the NAT Instance (shared by all runners)"
}

output "nat_instance_id" {
  value       = aws_instance.nat.id
  description = "Instance ID of the NAT Instance"
}

# Lambda function outputs
output "lambda_function_name" {
  value       = aws_lambda_function.gitlab_metrics_collector.function_name
  description = "Name of the GitLab metrics collector Lambda function"
}

output "cloudwatch_dashboard_url" {
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#metricsV2:graph=~();namespace=GitLab%2FCI"
  description = "URL to view GitLab CI metrics in CloudWatch"
}

