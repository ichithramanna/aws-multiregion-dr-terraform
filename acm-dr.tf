# ─── DR ACM Certificate ──────────────────────────────────────────
# Same domain as primary (api.ichith.it) but issued in us-west-2
# ACM certificates are REGION LOCKED — cannot share across regions
resource "aws_acm_certificate" "dr_backend" {
  provider          = aws.dr
  domain_name       = "api.ichith.it"
  validation_method = "DNS"

  tags = {
    Name = "dr-api-ichith-it-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─── DNS Validation Records ──────────────────────────────────────
# Route 53 is GLOBAL — same hosted zone validates both regions
# AWS is smart enough to reuse existing DNS validation records
# if primary cert already validated api.ichith.it
resource "aws_route53_record" "dr_backend_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.dr_backend.domain_validation_options :
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

  # Prevents conflict if primary validation record already exists
  allow_overwrite = true
}

# ─── DR Certificate Validation ───────────────────────────────────
# Waits until ACM confirms DNS validation is complete
# Uses same Route 53 zone as primary — no extra DNS config needed
resource "aws_acm_certificate_validation" "dr_backend" {
  provider                = aws.dr
  certificate_arn         = aws_acm_certificate.dr_backend.arn
  validation_record_fqdns = [
    for r in aws_route53_record.dr_backend_cert_validation : r.fqdn
  ]
}
