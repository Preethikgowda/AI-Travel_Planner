# Root outputs (convenience)
output "vpc_id" {
  value = try(module.vpc.vpc_id, "")
}

output "alb_dns_name" {
  value = try(module.compute.alb_dns_name, "")
}

output "rds_endpoint" {
  value = try(module.rds.rds_endpoint, "")
}

output "document_bucket" {
  value = try(module.storage.document_bucket_id, "")
}

output "secrets_arns" {
  value = try(module.security.secrets_arn, {})
}

output "cloudfront_domain_name" {
  value = try(module.cdn.cloudfront_domain_name, "")
}

output "route53_name_servers" {
  value = try(module.dns.name_servers, [])
}
