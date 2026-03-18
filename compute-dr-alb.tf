# ─── DR Application Load Balancer ────────────────────────────────
# Public-facing ALB in DR region (us-west-2)
# Sits in public subnets, routes traffic to DR EC2 instances
resource "aws_lb" "dr_alb" {
  provider           = aws.dr
  name               = "three-tier-dr-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.dr_alb_sg.id]
  subnets = [
    aws_subnet.dr_public_a.id,
    aws_subnet.dr_public_b.id
  ]

  tags = {
    Name = "three-tier-dr-alb"
  }
}

# ─── DR Target Group ─────────────────────────────────────────────
# Mirrors primary target group exactly
# EC2 instances in DR region register here
resource "aws_lb_target_group" "dr_app_tg" {
  provider = aws.dr
  name     = "dr-app-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.dr.id

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "dr-app-target-group"
  }
}

# ─── DR HTTP Listener ────────────────────────────────────────────
# HTTP 80 → redirect to HTTPS 443 (matches primary behavior)
resource "aws_lb_listener" "dr_http_listener" {
  provider          = aws.dr
  load_balancer_arn = aws_lb.dr_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ─── DR HTTPS Listener ───────────────────────────────────────────
# HTTPS 443 → forward to DR target group
# Uses DR ACM certificate (us-west-2 region certificate)
resource "aws_lb_listener" "dr_https_listener" {
  provider          = aws.dr
  load_balancer_arn = aws_lb.dr_alb.arn
  port              = 443
  protocol          = "HTTPS"

  certificate_arn = aws_acm_certificate_validation.dr_backend.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dr_app_tg.arn
  }
}
