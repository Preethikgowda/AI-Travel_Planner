# Backup Module - AWS Backup Vault & Plan

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "rds_arn" {
  type = string
}

variable "document_bucket_arn" {
  type = string
}

variable "tags" {
  type = map(string)
}

locals {
  module_tags = merge(var.tags, {
    Component = "backup"
  })
}

# AWS Backup Vault
resource "aws_backup_vault" "main" {
  name        = "${var.project_name}-${var.environment}-vault"
  kms_key_arn = var.kms_key_arn

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-vault"
  })
}

# AWS Backup Plan
resource "aws_backup_plan" "main" {
  name = "${var.project_name}-${var.environment}-daily-backup"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 5 ? * * *)" # 5 AM UTC
    start_window      = 60
    completion_window = 120

    lifecycle {
      delete_after = 35 # Retain backups for 35 days
    }
  }

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-backup-plan"
  })
}

# IAM Role for AWS Backup
resource "aws_iam_role" "backup" {
  name_prefix = "${var.project_name}-backup-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-backup-role"
  })
}

resource "aws_iam_role_policy_attachment" "backup_rds" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_s3" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup"
}

# Backup Selection
resource "aws_backup_selection" "main" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "${var.project_name}-${var.environment}-selection"
  plan_id      = aws_backup_plan.main.id

  # Explicitly select RDS and S3 documents
  resources = [
    var.rds_arn,
    var.document_bucket_arn
  ]

  # Also select anything tagged with BackupPolicy = Daily
  condition {
    string_equals {
      key   = "aws:ResourceTag/BackupPolicy"
      value = "Daily"
    }
  }
}

output "backup_vault_arn" {
  value = aws_backup_vault.main.arn
}
