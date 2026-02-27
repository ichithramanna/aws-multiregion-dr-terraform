# ─── Hosted Zone Lookup ──────────────────────────────────────────
# Looks up your existing ichith.it hosted zone by name
# We use data source (not resource) because the zone already exists
data "aws_route53_zone" "primary" {
  name = "ichith.it."
}

# ─── Frontend Record (unchanged) ─────────────────────────────────
# Still points app.ichith.it → CloudFront — nothing changes here
resource "aws_route53_record" "frontend" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "app.ichith.it"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

# ─── Backend API Record ──────────────────────────────────────────
# Single CNAME pointing api.ichith.it → Global Accelerator DNS name
# Global Accelerator owns all failover logic now — Route53 just resolves the name
# TTL=60 is fine because the GA static IPs never change
#
# REMOVED: aws_route53_record.backend (failover PRIMARY)
# REMOVED: aws_route53_record.backend_dr (failover SECONDARY)
# REMOVED: aws_route53_health_check.primary_alb
# All replaced by Global Accelerator endpoint groups in global-accelerator.tf
resource "aws_route53_record" "backend" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "api.ichith.it"
  type    = "CNAME"
  ttl     = 60
  records = [aws_globalaccelerator_accelerator.main.dns_name]
}
