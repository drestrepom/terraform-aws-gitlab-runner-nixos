# Launch Template for NixOS instances
resource "aws_launch_template" "nixos_runner" {
  name_prefix   = "nixos-runner-"
  description   = "Launch template for NixOS GitLab runners"
  image_id      = data.aws_ami.nixos_arm64.id
  instance_type = var.nix_builder_instance_type
  key_name      = aws_key_pair.nixos_instance.key_name

  vpc_security_group_ids = [aws_security_group.nixos_instance.id]

  user_data = base64encode(templatefile("${path.module}/nixos-runner-config.nix", {
    gitlab_runner_token = gitlab_user_runner.nixos_runner.token
    nix_builder_authorized_key = chomp(coalesce(var.nix_builder_authorized_key, file("${path.module}/nix_builder_key.pub")))
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.nix_builder_disk_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                 = "nixos-runner"
      "comp"              = "nixos-ci"
      "line"              = "cost"
      "gitlab-runner-id"  = gitlab_user_runner.nixos_runner.id
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name                 = "nixos-runner-volume"
      "comp"              = "nixos-ci"
      "line"              = "cost"
    }
  }

  tags = {
    Name                 = "nixos-runner-template"
    "comp"              = "nixos-ci"
    "line"              = "cost"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "nixos_runners" {
  name                = "nixos-gitlab-runners"
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = []
  health_check_type   = var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  # Mixed instance policy for spot instances
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.nixos_runner.id
        version           = "$Latest"
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "capacity-optimized"
    }
  }

  # Lifecycle hooks for graceful shutdown
  initial_lifecycle_hook {
    name                 = "gitlab-runner-shutdown"
    default_result       = "CONTINUE"
    heartbeat_timeout    = 300
    lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
  }

  tag {
    key                 = "Name"
    value               = "nixos-gitlab-runner"
    propagate_at_launch = true
  }

  tag {
    key                 = "comp"
    value               = "nixos-ci"
    propagate_at_launch = true
  }

  tag {
    key                 = "line"
    value               = "cost"
    propagate_at_launch = true
  }

  tag {
    key                 = "gitlab-runner-id"
    value               = gitlab_user_runner.nixos_runner.id
    propagate_at_launch = true
  }
}

# Auto Scaling Group scaling policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "nixos-runners-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.nixos_runners.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "nixos-runners-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.nixos_runners.name
}

# CloudWatch alarms for scaling
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "nixos-runners-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.nixos_runners.name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "nixos-runners-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.nixos_runners.name
  }
}
