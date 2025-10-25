# IAM Role for NixOS Runner EC2 instances
resource "aws_iam_role" "nixos_runner" {
  name = "${var.environment}-nixos-runner-role"

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

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-nixos-runner-role"
    }
  )
}

# Attach AWS managed policy for SSM (if enabled)
resource "aws_iam_role_policy_attachment" "nixos_runner_ssm" {
  count = var.enable_ssm_access ? 1 : 0

  role       = aws_iam_role.nixos_runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Policy for CloudWatch metrics (if enabled)
resource "aws_iam_role_policy" "nixos_runner_cloudwatch_put" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  name = "${var.environment}-nixos-runner-cloudwatch-put-metric"
  role = aws_iam_role.nixos_runner.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData"
        ],
        Resource = "*",
        Condition = {
          StringEquals = { "cloudwatch:namespace" = ["GitLab/Runner", "GitLab/CI"] }
        }
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "nixos_runner" {
  name = "${var.environment}-nixos-runner-profile"
  role = aws_iam_role.nixos_runner.name

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-nixos-runner-profile"
    }
  )
}

