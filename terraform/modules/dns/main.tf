# DNS Module - Route53 Hosted Zone and Records

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "cloudfront_domain_name" {
  type = string
}

variable "cloudfront_hosted_zone_id" {
  type = string
}

variable "alb_dns_name" {
  type = string
}

variable "alb_hosted_zone_id" {
  type = string
}

variable "tags" {
  type = map(string)
}

locals {
  module_tags = merge(var.tags, {
    Component = "dns"
  })

  create_dns = var.domain_name != "" ? true : false
}

# Create Hosted Zone if domain is provided
# (If domain is registered elsewhere, nameservers must be pointed here)
resource "aws_route53_zone" "main" {
  count = local.create_dns ? 1 : 0
  name  = var.domain_name

  tags = merge(local.module_tags, {
    Name = "${var.project_name}-${var.environment}-zone"
  })
}

# Root Domain Record (Frontend/CloudFront)
resource "aws_route53_record" "frontend_root" {
  count   = local.create_dns ? 1 : 0
  zone_id = aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# WWW Domain Record (Frontend/CloudFront)
resource "aws_route53_record" "frontend_www" {
  count   = local.create_dns ? 1 : 0
  zone_id = aws_route53_zone.main[0].zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# API Subdomain Record (Backend/ALB)
resource "aws_route53_record" "api" {
  count   = local.create_dns ? 1 : 0
  zone_id = aws_route53_zone.main[0].zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_hosted_zone_id
    evaluate_target_health = true
  }
}

output "name_servers" {
  value = local.create_dns ? aws_route53_zone.main[0].name_servers : []
}

output "zone_id" {
  value = local.create_dns ? aws_route53_zone.main[0].zone_id : ""
}
