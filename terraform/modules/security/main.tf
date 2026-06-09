# Security Module - KMS, Secrets Manager, IAM Roles, SSM

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "groq_api_key" {
  type      = string
  sensitive = true
}

variable "openweather_api_key" {
  type      = string
  sensitive = true
}

variable "geoapify_api_key" {
  type      = string
  sensitive = true
}

variable "google_maps_api_key" {
  type      = string
  sensitive = true
}

variable "jwt_secret_key" {
  type      = string
  sensitive = true
}

variable "rds_username" {
  type      = string
  sensitive = true
}

variable "rds_password" {
  type      = string
  sensitive = true
}

variable "slack_webhook_url" {
  type      = string
  sensitive = true
  default   = ""
}

variable "enable_bedrock" {
  type = bool
}

variable "bedrock_model_id" {
  type = string
}

variable "tags" {
  type = map(string)
}

locals {
  module_tags = merge(var.tags, {
    Component = "security"
  })
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ──────────────────────────────────────────────────────────────────────────────
# KMS
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_kms_key" "main" {
  description             = "${var.project_name}-${var.environment} master encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn": "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"
          }
        }
      },
      {
        Sid    = "Allow CloudTrail KMS Access"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-${var.environment}-trail"
          }
        }
      }
    ]
  })

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-kms-key"
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-${var.environment}"
  target_key_id = aws_kms_key.main.key_id
}

# ──────────────────────────────────────────────────────────────────────────────
# Secrets Manager
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "api_keys" {
  name_prefix             = "${var.project_name}/${var.environment}/api-keys-"
  description             = "External API keys for ${var.project_name}"
  recovery_window_in_days = var.environment == "prod" ? 7 : 0
  kms_key_id              = aws_kms_key.main.id

  tags = merge(local.module_tags, {
    Name               = "${var.project_name}-${var.environment}-api-keys"
    DataClassification = "Confidential"
  })
}

resource "aws_secretsmanager_secret_version" "api_keys" {
  secret_id = aws_secretsmanager_secret.api_keys.id
  secret_string = jsonencode({
    groq_api_key        = var.groq_api_key
    openweather_api_key = var.openweather_api_key
    geoapify_api_key    = var.geoapify_api_key
    google_maps_api_key = var.google_maps_api_key
    slack_webhook_url   = var.slack_webhook_url
  })
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name_prefix             = "${var.project_name}/${var.environment}/db-credentials-"
  description             = "RDS database credentials"
  recovery_window_in_days = var.environment == "prod" ? 7 : 0
  kms_key_id              = aws_kms_key.main.id

  tags = merge(local.module_tags, {
    Name               = "${var.project_name}-${var.environment}-db-credentials"
    DataClassification = "Restricted"
  })
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.rds_username
    password = var.rds_password
  })
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name_prefix             = "${var.project_name}/${var.environment}/jwt-secret-"
  description             = "JWT secret key for authentication"
  recovery_window_in_days = var.environment == "prod" ? 7 : 0
  kms_key_id              = aws_kms_key.main.id

  tags = merge(local.module_tags, {
    Name               = "${var.project_name}-${var.environment}-jwt-secret"
    DataClassification = "Restricted"
  })
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = var.jwt_secret_key
}

# ──────────────────────────────────────────────────────────────────────────────
# IAM Role for Backend EC2
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "backend" {
  name_prefix = "${var.project_name}-backend-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-backend-role"
  })
}

# SSM Session Manager — replaces SSH bastion
resource "aws_iam_role_policy_attachment" "backend_ssm" {
  role       = aws_iam_role.backend.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# S3 Access
resource "aws_iam_role_policy" "backend_s3" {
  name_prefix = "${var.project_name}-backend-s3-"
  role        = aws_iam_role.backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DocumentBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-${var.environment}-docs-*/*",
          "arn:aws:s3:::${var.project_name}-${var.environment}-docs-*"
        ]
      },
      {
        Sid    = "LogBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-${var.environment}-logs-*/*",
          "arn:aws:s3:::${var.project_name}-${var.environment}-logs-*"
        ]
      },
      {
        Sid    = "SNSPublishWelcomeEmails"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })
}

# Secrets Manager Access
resource "aws_iam_role_policy" "backend_secrets" {
  name_prefix = "${var.project_name}-backend-secrets-"
  role        = aws_iam_role.backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadSecrets"
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = [
        aws_secretsmanager_secret.api_keys.arn,
        aws_secretsmanager_secret.db_credentials.arn,
        aws_secretsmanager_secret.jwt_secret.arn
      ]
    }]
  })
}

# KMS Access
resource "aws_iam_role_policy" "backend_kms" {
  name_prefix = "${var.project_name}-backend-kms-"
  role        = aws_iam_role.backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "KMSDecrypt"
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey"
      ]
      Resource = aws_kms_key.main.arn
    }]
  })
}

# CloudWatch Logs
resource "aws_iam_role_policy" "backend_logs" {
  name_prefix = "${var.project_name}-backend-logs-"
  role        = aws_iam_role.backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CloudWatchLogs"
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

# CloudWatch Metrics (for custom metrics from CW agent)
resource "aws_iam_role_policy_attachment" "backend_cloudwatch_agent" {
  role       = aws_iam_role.backend.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Bedrock Access (Converse API)
resource "aws_iam_role_policy" "backend_bedrock" {
  count       = var.enable_bedrock ? 1 : 0
  name_prefix = "${var.project_name}-backend-bedrock-"
  role        = aws_iam_role.backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:*:*:foundation-model/${var.bedrock_model_id}"
      },
      {
        Sid    = "BedrockConverse"
        Effect = "Allow"
        Action = [
          "bedrock:Converse",
          "bedrock:ConverseStream"
        ]
        Resource = "arn:aws:bedrock:*:*:foundation-model/${var.bedrock_model_id}"
      },
      {
        Sid    = "BedrockList"
        Effect = "Allow"
        Action = [
          "bedrock:ListFoundationModels",
          "bedrock:GetFoundationModel"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "backend" {
  name_prefix = "${var.project_name}-backend-"
  role        = aws_iam_role.backend.name
}

# ──────────────────────────────────────────────────────────────────────────────
# Lambda Execution Role (for backup lambda, etc.)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_execution" {
  name_prefix = "${var.project_name}-lambda-"

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

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-lambda-role"
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3_rds" {
  name_prefix = "${var.project_name}-lambda-s3-rds-"
  role        = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BackupBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-${var.environment}-backups-*/*",
          "arn:aws:s3:::${var.project_name}-${var.environment}-backups-*"
        ]
      },
      {
        Sid      = "RDSConnect"
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = "arn:aws:rds-db:*:*:dbuser:*/*"
      }
    ]
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# Outputs
# ──────────────────────────────────────────────────────────────────────────────

output "kms_key_id" {
  value = aws_kms_key.main.id
}

output "kms_key_arn" {
  value = aws_kms_key.main.arn
}

output "backend_iam_role_arn" {
  value = aws_iam_role.backend.arn
}

output "backend_iam_role_name" {
  value = aws_iam_role.backend.name
}

output "backend_iam_instance_profile" {
  value = aws_iam_instance_profile.backend.name
}

output "lambda_iam_role_arn" {
  value = aws_iam_role.lambda_execution.arn
}

output "secrets_arn" {
  value = {
    api_keys       = aws_secretsmanager_secret.api_keys.arn
    db_credentials = aws_secretsmanager_secret.db_credentials.arn
    jwt_secret     = aws_secretsmanager_secret.jwt_secret.arn
  }
}
