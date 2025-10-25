# IAM Role for NixOS Runner EC2 instances
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

# IAM Policy for CloudWatch metrics
resource "aws_iam_role_policy" "nixos_runner_cloudwatch_put" {
  name = "nixos-runner-cloudwatch-put-metric"
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
          StringEquals = { "cloudwatch:namespace" = ["GitLab/Runner"] }
        }
      }
    ]
  })
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

