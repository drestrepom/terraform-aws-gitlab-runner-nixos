locals {
  nix_src = file("${path.module}/nixos-runner-config.nix")
  replacements = {
    "__GITLAB_RUNNER_TOKEN__" = gitlab_user_runner.nixos_runner.token
    "__HEALTH_CHECK_SCRIPT__" = file("${path.module}/health-check.sh")
    "__RUNNER_STATUS_SCRIPT__" = file("${path.module}/runner-status.sh")
    "__CONCURRENT_JOBS__"     = tostring(var.concurrent_jobs_per_instance)
  }

  keys_order = ["__GITLAB_RUNNER_TOKEN__", "__HEALTH_CHECK_SCRIPT__", "__RUNNER_STATUS_SCRIPT__", "__CONCURRENT_JOBS__"]

  step1 = replace(local.nix_src, local.keys_order[0], local.replacements[local.keys_order[0]])
  step2 = replace(local.step1,   local.keys_order[1], local.replacements[local.keys_order[1]])
  step3 = replace(local.step2,   local.keys_order[2], local.replacements[local.keys_order[2]])
  step4 = replace(local.step3,   local.keys_order[3], local.replacements[local.keys_order[3]])

  user_data = base64encode(local.step4)
}
resource "aws_launch_template" "nixos_runner" {
  name_prefix = "nixos-runner-"
  description = "Launch template for NixOS GitLab runners"
  image_id    = data.aws_ami.nixos_arm64.id

  vpc_security_group_ids = [aws_security_group.nixos_instance.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.nixos_runner.name
  }

  user_data = local.user_data

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
      Name               = "nixos-runner"
      "comp"             = "nixos-ci"
      "line"             = "cost"
      "gitlab-runner-id" = gitlab_user_runner.nixos_runner.id
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name   = "nixos-runner-volume"
      "comp" = "nixos-ci"
      "line" = "cost"
    }
  }

  tags = {
    Name   = "nixos-runner-template"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

# Auto Scaling Group - Managed by Lambda
resource "aws_autoscaling_group" "nixos_runners" {
  name                      = "nixos-gitlab-runners"
  vpc_zone_identifier       = aws_subnet.private[*].id
  target_group_arns         = []
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  # Mixed instance policy for spot instances
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.nixos_runner.id
        version            = "$Latest"
      }

      # Multiple instance types for better Spot availability
      dynamic "override" {
        for_each = var.instance_types
        content {
          instance_type = override.value
        }
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = var.on_demand_percentage
      spot_allocation_strategy                 = "price-capacity-optimized"
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
