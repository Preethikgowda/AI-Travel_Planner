# Main Terraform Configuration for AI Travel Planner
# Production-ready infrastructure deployment

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Backend configuration - uncomment after first apply
  # backend "s3" {
  #   bucket         = "ai-travel-terraform-state"
  #   key            = "prod/terraform.tfstate"
  #   region         = "ap-south-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      var.tags,
      var.common_tags,
      {
        Environment = var.environment
        Region      = var.aws_region
      }
    )
  }
}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

# Generate secure RDS password if not provided
resource "random_password" "rds_password" {
  length      = 32
  special     = true
  min_special = 5
  min_upper   = 3
  min_lower   = 3
  min_numeric = 3
}

# Local variables for tags
locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    CostCenter  = "Engineering"
    Compliance  = "SOC2"
  }

  rds_password = var.rds_password != "" ? var.rds_password : random_password.rds_password.result
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  enable_nat_gateway = var.enable_nat_gateway
  region             = var.aws_region

  tags = local.common_tags
}

# Security Module (KMS, Secrets Manager)
module "security" {
  source = "./modules/security"

  project_name        = var.project_name
  environment         = var.environment
  groq_api_key        = var.groq_api_key
  openweather_api_key = var.openweather_api_key
  geoapify_api_key    = var.geoapify_api_key
  google_maps_api_key = var.google_maps_api_key
  jwt_secret_key      = var.jwt_secret_key
  rds_username        = var.rds_username
  rds_password        = local.rds_password
  slack_webhook_url   = var.slack_webhook_url
  enable_bedrock      = var.enable_bedrock
  bedrock_model_id    = var.bedrock_model_id

  tags = local.common_tags

  depends_on = [module.vpc]
}

# RDS Module
module "rds" {
  source = "./modules/rds"

  project_name               = var.project_name
  environment                = var.environment
  db_name                    = "ai_travel"
  db_username                = var.rds_username
  db_password                = local.rds_password
  db_subnet_group_name       = module.vpc.db_subnet_group_name
  vpc_security_group_ids     = [module.vpc.rds_security_group_id]
  instance_class             = var.rds_instance_class
  allocated_storage          = var.rds_allocated_storage
  multi_az                   = var.enable_multi_az
  backup_retention_period    = var.backup_retention_days
  kms_key_id                 = module.security.kms_key_arn
  enable_enhanced_monitoring = var.enable_enhanced_monitoring

  tags = local.common_tags

  depends_on = [module.security, module.vpc]
}

# Storage Module (S3, Backups)
module "storage" {
  source = "./modules/storage"

  project_name  = var.project_name
  environment   = var.environment
  kms_key_id    = module.security.kms_key_id
  force_destroy = var.environment == "dev" ? true : false

  tags = local.common_tags

  depends_on = [module.security]
}

# Compute Module (ALB, ASG, EC2)
module "compute" {
  source = "./modules/compute"

  project_name                 = var.project_name
  environment                  = var.environment
  vpc_id                       = module.vpc.vpc_id
  private_subnet_ids           = module.vpc.private_subnet_ids
  public_subnet_ids            = module.vpc.public_subnet_ids
  backend_security_group_id    = module.vpc.backend_security_group_id
  alb_security_group_id        = module.vpc.alb_security_group_id
  instance_type                = var.instance_type
  asg_min_size                 = var.asg_min_size
  asg_desired_capacity         = var.asg_desired_capacity
  asg_max_size                 = var.asg_max_size
  backend_iam_instance_profile = module.security.backend_iam_instance_profile
  s3_document_bucket           = module.storage.document_bucket_id
  s3_log_bucket                = module.storage.log_bucket_id
  kms_key_id                   = module.security.kms_key_id
  kms_key_arn                  = module.security.kms_key_arn
  secrets_arn                  = module.security.secrets_arn
  enable_bedrock               = var.enable_bedrock
  bedrock_model_id             = var.bedrock_model_id
  rds_endpoint                 = module.rds.rds_endpoint
  rds_username                 = var.rds_username
  rds_password                 = local.rds_password
  environment_variables = {
    ENVIRONMENT = var.environment
    # When running in production, avoid embedding secrets in the env file.
    # The application will read credentials from Secrets Manager when AWS_SECRETS_ENABLED=true.
    AWS_SECRETS_ENABLED = var.environment == "prod" ? "true" : "false"
    DB_SECRET_ARN       = module.security.secrets_arn["db_credentials"]
    API_KEYS_SECRET_ARN = module.security.secrets_arn["api_keys"]
    JWT_SECRET_ARN      = module.security.secrets_arn["jwt_secret"]
    RDS_ENDPOINT        = module.rds.rds_endpoint
    # For convenience in non-prod environments we still populate DATABASE_URL
    DATABASE_URL       = var.environment == "prod" ? "" : "postgresql+psycopg://${var.rds_username}:${local.rds_password}@${module.rds.rds_endpoint}:5432/ai_travel"
    JWT_SECRET_KEY     = var.jwt_secret_key
    ENABLE_BEDROCK     = var.enable_bedrock
    BEDROCK_MODEL_ID   = var.bedrock_model_id
    S3_DOCUMENT_BUCKET = module.storage.document_bucket_id
    S3_LOG_BUCKET      = module.storage.log_bucket_id
    S3_DOCUMENT_KMS_KEY_ID = module.security.kms_key_id
    AWS_REGION         = var.aws_region
    SNS_TOPIC_ARN      = "arn:aws:sns:us-east-1:235270183260:ai-travel-welcome-email"
    CORS_ORIGINS       = "https://${var.domain_name},https://www.${var.domain_name}"
  }

  tags = local.common_tags

  depends_on = [module.vpc, module.security, module.storage, module.rds]
}

# Monitoring Module (CloudWatch, SNS, EventBridge, Lambda)
module "monitoring" {
  source = "./modules/monitoring"

  project_name         = var.project_name
  environment          = var.environment
  alert_email          = var.alert_email
  slack_webhook_url    = var.slack_webhook_url
  log_retention_days   = var.log_retention_days
  alb_name             = module.compute.alb_name
  alb_arn              = module.compute.alb_arn
  alb_target_group_arn = module.compute.target_group_arn
  asg_name             = module.compute.asg_name
  rds_instance_id      = module.rds.rds_instance_id
  kms_key_id           = module.security.kms_key_arn
  s3_document_bucket   = module.storage.document_bucket_id
  s3_log_bucket        = module.storage.log_bucket_id
  rds_endpoint         = module.rds.rds_endpoint
  rds_username         = var.rds_username
  rds_password         = local.rds_password

  tags = local.common_tags

  depends_on = [module.compute, module.rds, module.storage, module.security]
}

# AI Module (Bedrock, SageMaker if needed)
module "ai" {
  source = "./modules/ai"

  project_name         = var.project_name
  environment          = var.environment
  enable_bedrock       = var.enable_bedrock
  bedrock_model_id     = var.bedrock_model_id
  kms_key_id           = module.security.kms_key_arn
  backend_iam_role_arn = module.security.backend_iam_role_arn

  tags = local.common_tags

  depends_on = [module.security]
}

# WAF Module
module "waf" {
  source = "./modules/waf"

  project_name = var.project_name
  environment  = var.environment
  alb_arn      = module.compute.alb_arn
  tags         = local.common_tags

  depends_on = [module.compute]
}

# CloudTrail Module
module "cloudtrail" {
  source = "./modules/cloudtrail"

  project_name  = var.project_name
  environment   = var.environment
  s3_log_bucket = module.storage.log_bucket_id
  kms_key_id    = module.security.kms_key_arn
  tags          = local.common_tags

  depends_on = [module.storage, module.security]
}

# Backup Module
module "backup" {
  source = "./modules/backup"

  project_name        = var.project_name
  environment         = var.environment
  kms_key_arn         = module.security.kms_key_arn
  rds_arn             = module.rds.rds_arn
  document_bucket_arn = module.storage.document_bucket_arn
  tags                = local.common_tags

  depends_on = [module.security, module.rds, module.storage]
}

# Compliance Module (AWS Config)
module "compliance" {
  source = "./modules/compliance"

  project_name  = var.project_name
  environment   = var.environment
  s3_log_bucket = module.storage.log_bucket_id
  tags          = local.common_tags

  depends_on = [module.storage]
}

# CDN Module (CloudFront)
module "cdn" {
  source = "./modules/cdn"

  project_name                         = var.project_name
  environment                          = var.environment
  frontend_bucket_id                   = module.storage.frontend_bucket_id
  frontend_bucket_arn                  = module.storage.frontend_bucket_arn
  frontend_bucket_regional_domain_name = module.storage.frontend_bucket_regional_domain_name
  domain_name                          = var.domain_name
  acm_certificate_arn                  = var.acm_certificate_arn
  alb_dns_name                         = module.compute.alb_dns_name
  tags                                 = local.common_tags

  depends_on = [module.storage, module.compute]
}

# DNS Module (Route53)
module "dns" {
  source = "./modules/dns"

  project_name              = var.project_name
  environment               = var.environment
  domain_name               = var.domain_name
  cloudfront_domain_name    = module.cdn.cloudfront_domain_name
  cloudfront_hosted_zone_id = module.cdn.cloudfront_hosted_zone_id
  alb_dns_name              = module.compute.alb_dns_name
  alb_hosted_zone_id        = module.compute.alb_zone_id
  tags                      = local.common_tags

  depends_on = [module.cdn, module.compute]
}

# Outputs for reference
output "deployment_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    region                 = var.aws_region
    environment            = var.environment
    vpc_id                 = module.vpc.vpc_id
    alb_dns_name           = module.compute.alb_dns_name
    cloudfront_domain_name = module.cdn.cloudfront_domain_name
    rds_endpoint           = module.rds.rds_endpoint
    s3_document_bucket     = module.storage.document_bucket_id
    s3_log_bucket          = module.storage.log_bucket_id
    backend_iam_role       = module.security.backend_iam_role_name
    kms_key_id             = module.security.kms_key_id
    bedrock_enabled        = var.enable_bedrock
    sns_topic_arn          = module.monitoring.sns_topic_arn
    waf_enabled            = true
  }
}
