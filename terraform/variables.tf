# Global Variables for AI Travel Planner Infrastructure
# This file contains all configurable variables across environments

variable "aws_region" {
  description = "AWS Region for deployment"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "ai-travel"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "invest-iq.online"
}

variable "acm_certificate_arn" {
  description = "ACM Certificate ARN for CloudFront (must be in us-east-1)"
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Email for SNS alerts and notifications"
  type        = string
  default     = "preethikgowda26@gmail.com"
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_repo" {
  description = "GitHub repository URL for CI/CD"
  type        = string
  default     = "https://github.com/Preethikgowda/AI-Travel_Planner"
}

variable "enable_bedrock" {
  description = "Enable AWS Bedrock for AI responses"
  type        = bool
  default     = true
}

variable "bedrock_model_id" {
  description = "Bedrock model ID to use"
  type        = string
  default     = "meta.llama2-13b-chat-v1"
}

variable "groq_api_key" {
  description = "Groq API Key (keep for fallback)"
  type        = string
  sensitive   = true
}

variable "openweather_api_key" {
  description = "OpenWeather API Key"
  type        = string
  sensitive   = true
}

variable "geoapify_api_key" {
  description = "Geoapify API Key"
  type        = string
  sensitive   = true
}

variable "google_maps_api_key" {
  description = "Google Maps API Key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "jwt_secret_key" {
  description = "JWT Secret Key for authentication"
  type        = string
  sensitive   = true
}

variable "rds_username" {
  description = "RDS Master Username"
  type        = string
  default     = "ai_travel_admin"
  sensitive   = true
}

variable "rds_password" {
  description = "RDS Master Password (auto-generated if empty)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "EC2 instance type for backend"
  type        = string
  default     = "t3.medium"
}

variable "asg_min_size" {
  description = "Auto Scaling Group minimum size"
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "Auto Scaling Group desired capacity"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Auto Scaling Group maximum size"
  type        = number
  default     = 10
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.small"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 100
}

variable "enable_multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "RDS backup retention period in days"
  type        = number
  default     = 30
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for RDS"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project    = "AI Travel Planner"
    ManagedBy  = "Terraform"
    Owner      = "DevOps Team"
    CostCenter = "Engineering"
  }
}

variable "common_tags" {
  description = "Environment-specific tags"
  type        = map(string)
  default     = {}
}
