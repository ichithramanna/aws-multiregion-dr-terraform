resource "aws_globalaccelerator_accelerator" "main" {
  name            = "three-tier-accelerator"
  ip_address_type = "IPV4"
  enabled         = true
  tags            = { Name = "three-tier-global-accelerator" }
}

resource "aws_globalaccelerator_listener" "https" {
  accelerator_arn = aws_globalaccelerator_accelerator.main.id
  protocol        = "TCP"
  port_range {
    from_port = 443
    to_port   = 443
  }
}

# Primary endpoint group — us-east-1
resource "aws_globalaccelerator_endpoint_group" "primary" {
  listener_arn                  = aws_globalaccelerator_listener.https.id
  endpoint_group_region         = "us-east-1"
  traffic_dial_percentage       = 100
  health_check_path             = "/health"
  health_check_protocol         = "HTTPS"
  health_check_interval_seconds = 10
  threshold_count               = 3

  endpoint_configuration {
    endpoint_id                    = aws_lb.app_alb.arn
    weight                         = 100
    client_ip_preservation_enabled = true
  }
}

# DR endpoint group — us-west-2
resource "aws_globalaccelerator_endpoint_group" "dr" {
  listener_arn                  = aws_globalaccelerator_listener.https.id
  endpoint_group_region         = "us-west-2"
  traffic_dial_percentage       = 0
  health_check_path             = "/health"
  health_check_protocol         = "HTTPS"
  health_check_interval_seconds = 10
  threshold_count               = 3

  endpoint_configuration {
    endpoint_id                    = aws_lb.dr_alb.arn
    weight                         = 100
    client_ip_preservation_enabled = true
  }
}

output "global_accelerator_dns" {
  value       = aws_globalaccelerator_accelerator.main.dns_name
  description = "Update route53.tf CNAME to point here"
}
