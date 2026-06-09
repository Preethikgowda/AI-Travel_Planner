# RDS Module - PostgreSQL Database with Multi-AZ

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_subnet_group_name" {
  type = string
}

variable "vpc_security_group_ids" {
  type = list(string)
}

variable "instance_class" {
  type = string
}

variable "allocated_storage" {
  type = number
}

variable "multi_az" {
  type = bool
}

variable "backup_retention_period" {
  type = number
}

variable "kms_key_id" {
  description = "KMS key ARN for encryption"
  type        = string
}

variable "enable_enhanced_monitoring" {
  type = bool
}

variable "tags" {
  type = map(string)
}

locals {
  module_tags = merge(var.tags, {
    Component          = "database"
    DataClassification = "Confidential"
    BackupPolicy       = "Daily"
  })
}

# RDS Enhanced Monitoring Role
resource "aws_iam_role" "rds_monitoring" {
  count       = var.enable_enhanced_monitoring ? 1 : 0
  name_prefix = "${var.project_name}-rds-mon-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-rds-monitoring-role"
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count      = var.enable_enhanced_monitoring ? 1 : 0
  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Database Parameter Group
resource "aws_db_parameter_group" "main" {
  name_prefix = "${var.project_name}-${var.environment}-"
  family      = "postgres16"
  description = "Custom parameter group for ${var.project_name} ${var.environment}"

  parameter {
    name  = "log_statement"
    value = var.environment == "prod" ? "ddl" : "all"
  }

  parameter {
    name  = "log_duration"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = var.environment == "prod" ? "1000" : "500"
  }

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-db-parameter-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier            = "${var.project_name}-${var.environment}-db"
  engine                = "postgres"
  engine_version        = "16.14"
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_id

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Attach parameter group (was orphaned before)
  parameter_group_name = aws_db_parameter_group.main.name

  # Networking
  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = var.vpc_security_group_ids
  publicly_accessible    = false

  # Backup and Recovery
  backup_retention_period   = var.backup_retention_period
  backup_window             = "03:00-04:00"
  maintenance_window        = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.environment == "dev" ? true : false
  final_snapshot_identifier = var.environment == "dev" ? null : "${var.project_name}-${var.environment}-final-snapshot"

  # High Availability
  multi_az                   = var.multi_az
  auto_minor_version_upgrade = true
  deletion_protection        = var.environment == "prod" ? true : false

  # Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql"]
  monitoring_interval             = var.enable_enhanced_monitoring ? 60 : 0
  monitoring_role_arn             = var.enable_enhanced_monitoring ? aws_iam_role.rds_monitoring[0].arn : null

  # Performance
  performance_insights_enabled          = var.environment == "prod" ? true : false
  performance_insights_retention_period = 7

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-rds"
  })

  depends_on = [aws_iam_role_policy_attachment.rds_monitoring]
}

# CloudWatch Alarms for RDS
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "Alert when RDS CPU exceeds 75%"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-rds-cpu-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = 10737418240 # 10 GB
  alarm_description   = "Alert when free storage is less than 10 GB"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-rds-storage-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alert when database connections exceed 80"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-rds-connections-alarm"
  })
}

# Outputs
output "rds_endpoint" {
  value       = aws_db_instance.main.endpoint
  description = "RDS endpoint for backend connection"
}

output "rds_instance_id" {
  value = aws_db_instance.main.id
}

output "rds_resource_id" {
  value = aws_db_instance.main.resource_id
}

output "rds_address" {
  value = aws_db_instance.main.address
}

output "rds_arn" {
  value = aws_db_instance.main.arn
}

output "rds_monitoring_role_arn" {
  value = var.enable_enhanced_monitoring ? aws_iam_role.rds_monitoring[0].arn : ""
}
