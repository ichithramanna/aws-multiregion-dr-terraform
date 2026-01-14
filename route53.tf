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

resource "aws_route53_record" "backend" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "api.ichith.it"
  type    = "A"

  alias {
    name                   = aws_lb.app_alb.dns_name
    zone_id                = aws_lb.app_alb.zone_id
    evaluate_target_health = true
  }
}

