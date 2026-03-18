data "aws_acm_certificate" "frontend" {
  provider    = aws.use1
  domain      = "ichith.it"
  statuses    = ["ISSUED"]
  most_recent = true
}

# Backend certificate (ALB region: eu-north-1)
resource "aws_acm_certificate" "backend" {
  domain_name       = "api.ichith.it"
  validation_method = "DNS"

  tags = {
    Name = "api-ichith-it-cert"
  }
}

resource "aws_route53_record" "backend_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.backend.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.primary.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "backend" {
  certificate_arn = aws_acm_certificate.backend.arn
  validation_record_fqdns = [
    for r in aws_route53_record.backend_cert_validation : r.fqdn
  ]
}
