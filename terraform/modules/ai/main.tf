# AI Module - Bedrock Integration

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "enable_bedrock" {
  type = bool
}

variable "bedrock_model_id" {
  type = string
}

variable "kms_key_id" {
  type = string
}

variable "backend_iam_role_arn" {
  type = string
}

variable "tags" {
  type = map(string)
}

locals {
  module_tags = merge(var.tags, {
    Component = "ai"
  })
}

# CloudWatch Log Group for Bedrock
resource "aws_cloudwatch_log_group" "bedrock" {
  count             = var.enable_bedrock ? 1 : 0
  name              = "/aws/bedrock/${var.project_name}-${var.environment}"
  retention_in_days = 7
  kms_key_id        = var.kms_key_id

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-bedrock-logs"
  })
}

# Bedrock Model Access Logging Configuration
# Note: Bedrock log delivery can only be configured once per account/region.
# If multiple environments share an account, this might fail unless isolated to prod.
# We will disable creating this by default unless it's prod, or use a shared setup.
resource "aws_cloudwatch_log_resource_policy" "bedrock" {
  count           = var.enable_bedrock && var.environment == "prod" ? 1 : 0
  policy_name     = "${var.project_name}-${var.environment}-bedrock-logs"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# Bedrock Model Metrics in CloudWatch
resource "aws_cloudwatch_metric_alarm" "bedrock_errors" {
  count               = var.enable_bedrock ? 1 : 0
  alarm_name          = "${var.project_name}-${var.environment}-bedrock-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "ModelInvocationErrors"
  namespace           = "AWS/Bedrock"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Alert when Bedrock model invocation errors exceed threshold"

  dimensions = {
    Model = var.bedrock_model_id
  }

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-bedrock-errors-alarm"
  })
}

# CloudWatch Metric for Bedrock Latency
resource "aws_cloudwatch_metric_alarm" "bedrock_latency" {
  count               = var.enable_bedrock ? 1 : 0
  alarm_name          = "${var.project_name}-${var.environment}-bedrock-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ModelInvocationLatency"
  namespace           = "AWS/Bedrock"
  period              = "300"
  statistic           = "Average"
  threshold           = "5000" # 5 seconds
  alarm_description   = "Alert when Bedrock latency exceeds 5 seconds"

  dimensions = {
    Model = var.bedrock_model_id
  }

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-bedrock-latency-alarm"
  })
}

# Bedrock Model Configuration
output "bedrock_enabled" {
  value = var.enable_bedrock
}

output "bedrock_model_id" {
  value = var.bedrock_model_id
}

output "bedrock_log_group" {
  value = var.enable_bedrock ? aws_cloudwatch_log_group.bedrock[0].name : ""
}

output "backend_iam_role_arn" {
  value = var.backend_iam_role_arn
}
