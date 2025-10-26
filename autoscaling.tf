locals {
  # Load the NixOS configuration template
  nix_src_base = file("${path.module}/scripts/nixos-runner-config.nix")
  nix_src      = var.custom_nixos_config != "" ? var.custom_nixos_config : local.nix_src_base
  # Generate additional imports from user-provided configs
  additional_imports = length(var.additional_nixos_configs) > 0 ? [
    for config in var.additional_nixos_configs : "(${config})"
  ] : []

  # Generate the imports section
  imports_section = join("\n    ", local.additional_imports)

  # Template replacements
  replacements = {
    "__GITLAB_RUNNER_TOKEN__"  = local.runner_token # Token from GitLab provider
    "__GITLAB_URL__"           = var.gitlab_url
    "__HEALTH_CHECK_SCRIPT__"  = file("${path.module}/scripts/health-check.sh")
    "__RUNNER_STATUS_SCRIPT__" = file("${path.module}/scripts/runner-status.sh")
    "__CONCURRENT_JOBS__"      = tostring(var.concurrent_jobs_per_instance)
    "__NIX_CONFIG_IMPORT__"    = local.imports_section
  }

  # Perform replacements in order
  keys_order = ["__GITLAB_RUNNER_TOKEN__", "__GITLAB_URL__", "__HEALTH_CHECK_SCRIPT__", "__RUNNER_STATUS_SCRIPT__", "__CONCURRENT_JOBS__", "__NIX_CONFIG_IMPORT__"]

  step1     = replace(local.nix_src, local.keys_order[0], local.replacements[local.keys_order[0]])
  step2     = replace(local.step1, local.keys_order[1], local.replacements[local.keys_order[1]])
  step3     = replace(local.step2, local.keys_order[2], local.replacements[local.keys_order[2]])
  step4     = replace(local.step3, local.keys_order[3], local.replacements[local.keys_order[3]])
  step5     = replace(local.step4, local.keys_order[4], local.replacements[local.keys_order[4]])
  step6     = replace(local.step5, local.keys_order[5], local.replacements[local.keys_order[5]])
  user_data = base64encode(local.step6)
}
resource "aws_launch_template" "nixos_runner" {
  name_prefix = "${var.environment}-nixos-runner-"
  description = "Launch template for NixOS GitLab runners with native Nix support"
  image_id    = data.aws_ami.nixos_arm64.id

  vpc_security_group_ids = concat(
    [aws_security_group.nixos_instance.id],
    var.additional_security_group_ids
  )

  iam_instance_profile {
    name = aws_iam_instance_profile.nixos_runner.name
  }

  user_data = local.user_data

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      delete_on_termination = true
      encrypted             = true
    }
  }

  # Additional EBS volume for GitLab Runner builds
  dynamic "block_device_mappings" {
    for_each = var.gitlab_runner_volume_size > 0 ? [1] : []
    content {
      device_name = "/dev/sdf"
      ebs {
        volume_size           = var.gitlab_runner_volume_size
        volume_type           = var.gitlab_runner_volume_type
        delete_on_termination = true
        encrypted             = true
      }
    }
  }

  # Enable IMDSv2 (more secure)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = var.enable_cloudwatch_monitoring
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.runner_tags,
      {
        Name = "${var.environment}-nixos-runner"
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      local.common_tags,
      {
        Name = "${var.environment}-nixos-runner-volume"
      }
    )
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-nixos-runner-template"
    }
  )
}

# Auto Scaling Group - Managed by Lambda
resource "aws_autoscaling_group" "nixos_runners" {
  name                      = "${var.environment}-nixos-gitlab-runners"
  vpc_zone_identifier       = local.subnet_ids
  target_group_arns         = []
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  min_size         = var.min_instances
  max_size         = var.max_instances
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
      spot_allocation_strategy                 = var.spot_allocation_strategy
    }
  }

  # Lifecycle hooks for graceful shutdown
  initial_lifecycle_hook {
    name                 = "${var.environment}-gitlab-runner-shutdown"
    default_result       = "CONTINUE"
    heartbeat_timeout    = var.instance_termination_timeout
    lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
  }

  # Dynamic tags from locals
  dynamic "tag" {
    for_each = local.runner_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.environment}-nixos-gitlab-runner"
    propagate_at_launch = true
  }

  # Instance refresh for updates
  dynamic "instance_refresh" {
    for_each = var.enable_instance_refresh ? [1] : []
    content {
      strategy = "Rolling"
      preferences {
        min_healthy_percentage = 90
      }
    }
  }
}
