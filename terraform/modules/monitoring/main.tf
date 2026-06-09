# Monitoring Module - CloudWatch, SNS, EventBridge, Lambda

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alert_email" {
  type = string
}

variable "slack_webhook_url" {
  type      = string
  sensitive = true
}

variable "log_retention_days" {
  type = number
}

variable "alb_name" {
  type = string
}

variable "alb_arn" {
  type = string
}

variable "alb_target_group_arn" {
  type = string
}

variable "asg_name" {
  type = string
}

variable "rds_instance_id" {
  type = string
}

variable "kms_key_id" {
  type = string
}

variable "s3_document_bucket" {
  type = string
}

variable "s3_log_bucket" {
  type = string
}

variable "rds_endpoint" {
  type = string
}

variable "rds_username" {
  type      = string
  sensitive = true
}

variable "rds_password" {
  type      = string
  sensitive = true
}

variable "enable_backup_lambda" {
  type    = bool
  default = false
}

variable "tags" {
  type = map(string)
}

locals {
  module_tags = merge(var.tags, {
    Component = "monitoring"
  })
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name              = "${var.project_name}-${var.environment}-alerts"
  kms_master_key_id = var.kms_key_id

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-alerts"
  })
}

# SNS Email Subscription
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# SNS Slack Subscription (if webhook provided)
resource "aws_sns_topic_subscription" "slack" {
  count     = var.slack_webhook_url != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
}

# CloudWatch Log Group for Application Logs
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/aws/ec2/${var.project_name}-${var.environment}-backend"
  retention_in_days = var.log_retention_days

  kms_key_id = var.kms_key_id

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-backend-logs"
  })
}

# CloudWatch Log Group for ALB
resource "aws_cloudwatch_log_group" "alb" {
  name              = "/aws/alb/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  kms_key_id = var.kms_key_id

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-alb-logs"
  })
}

# CloudWatch Metric Alarm for Application Errors
resource "aws_cloudwatch_metric_alarm" "app_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-app-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Alert when 5xx errors exceed threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.alb_arn
  }

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-app-errors-alarm"
  })
}

# EventBridge Rule for Daily Database Backup (Custom Lambda)
resource "aws_cloudwatch_event_rule" "daily_backup" {
  name                = "${var.project_name}-${var.environment}-daily-backup"
  description         = "Trigger daily RDS backup"
  schedule_expression = "cron(0 2 * * ? *)" # 2 AM UTC daily
  is_enabled          = var.enable_backup_lambda

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-daily-backup-rule"
  })
}

# Lambda IAM Role for Backup
resource "aws_iam_role" "lambda_backup" {
  count       = var.enable_backup_lambda ? 1 : 0
  name_prefix = "${var.project_name}-lambda-backup-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_backup_basic" {
  count      = var.enable_backup_lambda ? 1 : 0
  role       = aws_iam_role.lambda_backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Note: In production, the AWS Backup module handles automated backups.
# This Lambda is retained for custom manual backups to S3 if needed.

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", { stat = "Average" }],
            [".", "RequestCount", { stat = "Sum" }],
            [".", "HTTPCode_Target_5XX_Count", { stat = "Sum" }],
            ["AWS/EC2", "CPUUtilization", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = "ap-south-1"
          title  = "Application Performance"
        }
      }
    ]
  })
}

# Outputs
output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "cloudwatch_log_group_backend" {
  value = aws_cloudwatch_log_group.backend.name
}

output "cloudwatch_log_group_alb" {
  value = aws_cloudwatch_log_group.alb.name
}
