variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "ai-travel"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "tags" {
  type = map(string)
  default = {
    Project    = "AI Travel Planner"
    ManagedBy  = "Terraform"
    Owner      = "DevOps Team"
    CostCenter = "Engineering"
  }
}
