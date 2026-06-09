terraform {
  backend "s3" {
    bucket         = "ai-travel-prod-tfstate-235270183260"
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "ai-travel-prod-tf-locks-235270183260"
  }
}
