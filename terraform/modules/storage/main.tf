# Storage Module - S3 Buckets for Documents, Logs, Backups

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "kms_key_id" {
  type = string
}

variable "force_destroy" {
  type    = bool
  default = false
}

variable "tags" {
  type = map(string)
}

locals {
  module_tags = merge(var.tags, {
    Component = "storage"
  })
}

# S3 Bucket for Travel Documents (Private, Encrypted)
resource "aws_s3_bucket" "documents" {
  bucket_prefix = "${var.project_name}-${var.environment}-docs-"
  force_destroy = var.force_destroy

  tags = merge(local.module_tags, {
    Name               = "${var.project_name}-${var.environment}-docs"
    DataClassification = "Confidential"
  })
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    id     = "archive-old-documents"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# S3 Bucket for Logs
resource "aws_s3_bucket" "logs" {
  bucket_prefix = "${var.project_name}-${var.environment}-logs-"
  force_destroy = var.force_destroy

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-logs"
  })
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "transition-logs"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# S3 Bucket for Backups
resource "aws_s3_bucket" "backups" {
  bucket_prefix = "${var.project_name}-${var.environment}-backups-"
  force_destroy = var.force_destroy

  tags = merge(local.module_tags, {
    Name               = "${var.project_name}-${var.environment}-backups"
    DataClassification = "Confidential"
  })
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "archive-backups"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 180
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 2555 # 7 years for compliance
    }
  }
}

# S3 Bucket for Static Frontend Assets
resource "aws_s3_bucket" "frontend" {
  bucket_prefix = "${var.project_name}-${var.environment}-frontend-"
  force_destroy = var.force_destroy

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-frontend"
  })
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# CloudWatch Alarms for S3
resource "aws_cloudwatch_metric_alarm" "s3_documents_size" {
  alarm_name          = "${var.project_name}-${var.environment}-s3-docs-size"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = "86400"
  statistic           = "Average"
  threshold           = 107374182400 # 100 GB
  alarm_description   = "Alert when documents bucket exceeds 100 GB"

  dimensions = {
    BucketName  = aws_s3_bucket.documents.id
    StorageType = "StandardStorage"
  }

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-s3-docs-alarm"
  })
}

# Outputs
output "document_bucket_id" {
  value = aws_s3_bucket.documents.id
}

output "document_bucket_arn" {
  value = aws_s3_bucket.documents.arn
}

output "log_bucket_id" {
  value = aws_s3_bucket.logs.id
}

output "log_bucket_arn" {
  value = aws_s3_bucket.logs.arn
}

output "backup_bucket_id" {
  value = aws_s3_bucket.backups.id
}

output "backup_bucket_arn" {
  value = aws_s3_bucket.backups.arn
}

output "frontend_bucket_id" {
  value = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  value = aws_s3_bucket.frontend.arn
}

output "frontend_bucket_regional_domain_name" {
  value = aws_s3_bucket.frontend.bucket_regional_domain_name
}
