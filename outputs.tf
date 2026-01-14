output "frontend_url" {
  description = "Public URL of the frontend application"
  value       = "https://app.ichith.it"
}

output "backend_url" {
  description = "Public URL of the backend API"
  value       = "https://api.ichith.it"
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = aws_lb.app_alb.dns_name
}

output "vpc_id" {
  description = "VPC ID where the application is deployed"
  value       = aws_vpc.three_tier_vpc.id
}
