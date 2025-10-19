# Lambda function to collect GitLab job metrics
resource "aws_lambda_function" "gitlab_metrics_collector" {
  filename         = "gitlab_metrics_collector.zip"
  function_name    = "gitlab-metrics-collector"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.11"
  timeout         = 30

  depends_on = [data.archive_file.lambda_zip]

  environment {
    variables = {
      GITLAB_TOKEN = var.gitlab_token
      GITLAB_PROJECT_ID = var.gitlab_project_id
      GITLAB_URL = var.gitlab_url
    }
  }

  tags = {
    Name = "gitlab-metrics-collector"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

# Create the Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "gitlab_metrics_collector.zip"
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      gitlab_url = var.gitlab_url
    })
    filename = "lambda_function.py"
  }
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "gitlab-metrics-lambda-role"

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

  tags = {
    Name = "gitlab-metrics-lambda-role"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

# IAM policy for Lambda to write CloudWatch metrics
resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {
  name = "gitlab-metrics-cloudwatch-policy"
  role = aws_iam_role.lambda_execution_role.id

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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# EventBridge rule to trigger Lambda every 1 minute
resource "aws_cloudwatch_event_rule" "gitlab_metrics_schedule" {
  name                = "gitlab-metrics-schedule"
  description         = "Trigger GitLab metrics collection every 1 minute"
  schedule_expression = "rate(1 minute)"

  tags = {
    Name = "gitlab-metrics-schedule"
    "comp" = "nixos-ci"
    "line" = "cost"
  }
}

# EventBridge target to invoke Lambda
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.gitlab_metrics_schedule.name
  target_id = "GitLabMetricsLambdaTarget"
  arn       = aws_lambda_function.gitlab_metrics_collector.arn
}

# Permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.gitlab_metrics_collector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.gitlab_metrics_schedule.arn
}
