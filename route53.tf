data "aws_route53_zone" "primary" {
  name = "ichith.it."
}

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

# ─── PRIMARY Backend Record ──────────────────────────────────────
# REPLACES your simple backend record
# failover_routing_policy = PRIMARY means this is used when healthy
resource "aws_route53_record" "backend" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "api.ichith.it"
  type    = "A"

  failover_routing_policy {
    type = "PRIMARY"
  }

  # Links to health check — Route 53 monitors primary ALB
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary_alb.id

  alias {
    name                   = aws_lb.app_alb.dns_name
    zone_id                = aws_lb.app_alb.zone_id
    evaluate_target_health = true
  }
}

# ─── DR (SECONDARY) Backend Record ───────────────────────────────
# Only activated when primary health check fails
# No health_check_id needed — secondary is always assumed healthy
resource "aws_route53_record" "backend_dr" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "api.ichith.it"
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier = "dr"

  alias {
    name                   = aws_lb.dr_alb.dns_name
    zone_id                = aws_lb.dr_alb.zone_id
    evaluate_target_health = true
  }
}

# ─── Health Check for Primary ALB ────────────────────────────────
# Route 53 pings this endpoint every 30 seconds
# If 3 consecutive failures → marks primary UNHEALTHY → failover triggers
resource "aws_route53_health_check" "primary_alb" {
  fqdn              = aws_lb.app_alb.dns_name  # primary ALB DNS
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"                # same path as your target group
  failure_threshold = 3                        # 3 failures = unhealthy
  request_interval  = 30                       # check every 30 seconds

  tags = {
    Name = "primary-alb-health-check"
  }
}
