# Lambda function to collect GitLab job metrics and manage autoscaling
resource "aws_lambda_function" "gitlab_metrics_collector" {
  count = var.enable_gitlab_metrics ? 1 : 0

  filename      = "${path.module}/infra/gitlab_metrics_collector.zip"
  function_name = "${var.environment}-gitlab-metrics-collector"
  role          = aws_iam_role.lambda_execution_role[0].arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  depends_on = [data.archive_file.lambda_zip]

  environment {
    variables = {
      GITLAB_TOKEN      = var.gitlab_token
      GITLAB_PROJECT_ID = tostring(var.gitlab_project_id)
      GITLAB_URL        = var.gitlab_url
      ASG_NAME          = aws_autoscaling_group.nixos_runners.name
      RUNNER_TAG        = length(var.gitlab_runner_tags) > 0 ? var.gitlab_runner_tags[0] : "nixos"

      # Basic scaling configuration
      JOBS_PER_INSTANCE  = tostring(var.concurrent_jobs_per_instance)
      MIN_IDLE_INSTANCES = tostring(var.min_idle_instances)
      MAX_INSTANCES      = tostring(var.max_instances)

      # Advanced scaling parameters (inspired by fleeting plugin logic)
      SCALE_FACTOR       = tostring(var.scale_factor)
      MAX_GROWTH_RATE    = tostring(var.max_growth_rate)
      SCALE_IN_THRESHOLD = tostring(var.scale_in_threshold)
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-gitlab-metrics-collector"
    }
  )
}

# Create the Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/infra/gitlab_metrics_collector.zip"
  source {
    content = templatefile("${path.module}/infra/lambda_function.py", {
      gitlab_url = var.gitlab_url
    })
    filename = "lambda_function.py"
  }
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  count = var.enable_gitlab_metrics ? 1 : 0

  name = "${var.environment}-gitlab-metrics-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-gitlab-metrics-lambda-role"
    }
  )
}

# IAM policy for Lambda to write CloudWatch metrics and access ASG/EC2
resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {
  count = var.enable_gitlab_metrics ? 1 : 0

  name = "${var.environment}-gitlab-metrics-enhanced-policy"
  role = aws_iam_role.lambda_execution_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:SetDesiredCapacity"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
      }
    ]
  })
}

# EventBridge rule to trigger Lambda at configured interval
resource "aws_cloudwatch_event_rule" "gitlab_metrics_schedule" {
  count = var.enable_gitlab_metrics ? 1 : 0

  name                = "${var.environment}-gitlab-metrics-schedule"
  description         = "Trigger GitLab metrics collection and autoscaling"
  schedule_expression = "rate(${var.lambda_check_interval} minute${var.lambda_check_interval > 1 ? "s" : ""})"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-gitlab-metrics-schedule"
    }
  )
}

# EventBridge target to invoke Lambda
resource "aws_cloudwatch_event_target" "lambda_target" {
  count = var.enable_gitlab_metrics ? 1 : 0

  rule      = aws_cloudwatch_event_rule.gitlab_metrics_schedule[0].name
  target_id = "GitLabMetricsLambdaTarget"
  arn       = aws_lambda_function.gitlab_metrics_collector[0].arn
}

# Permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.enable_gitlab_metrics ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.gitlab_metrics_collector[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.gitlab_metrics_schedule[0].arn
}
