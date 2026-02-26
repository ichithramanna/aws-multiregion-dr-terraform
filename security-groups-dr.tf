# ─── DR Security Groups ──────────────────────────────────────────

resource "aws_security_group" "dr_alb_sg" {
  provider    = aws.dr
  name        = "dr-alb-sg"
  description = "Security group for DR ALB"
  vpc_id      = aws_vpc.dr.id

  tags = {
    Name = "dr-alb-security-group"
  }
}

resource "aws_security_group" "dr_ec2_sg" {
  provider    = aws.dr
  name        = "dr-ec2-sg"
  description = "Security group for DR EC2 backend"
  vpc_id      = aws_vpc.dr.id

  tags = {
    Name = "dr-ec2-security-group"
  }
}

resource "aws_security_group" "dr_rds_sg" {
  provider    = aws.dr
  name        = "dr-rds-sg"
  description = "Security group for DR RDS"
  vpc_id      = aws_vpc.dr.id

  tags = {
    Name = "dr-rds-security-group"
  }
}

# ─── DR Ingress Rules ────────────────────────────────────────────

# DR ALB: HTTPS from internet
resource "aws_vpc_security_group_ingress_rule" "dr_alb_https" {
  provider          = aws.dr
  security_group_id = aws_security_group.dr_alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS from internet"
}

# DR ALB: HTTP from internet (redirect to HTTPS)
resource "aws_vpc_security_group_ingress_rule" "dr_alb_http" {
  provider          = aws.dr
  security_group_id = aws_security_group.dr_alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP from internet"
}

# DR EC2: Allow traffic only from DR ALB
resource "aws_vpc_security_group_ingress_rule" "dr_ec2_from_alb" {
  provider                     = aws.dr
  security_group_id            = aws_security_group.dr_ec2_sg.id
  referenced_security_group_id = aws_security_group.dr_alb_sg.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  description                  = "HTTP from DR ALB"
}

# DR RDS: Allow traffic only from DR EC2
resource "aws_vpc_security_group_ingress_rule" "dr_rds_from_ec2" {
  provider                     = aws.dr
  security_group_id            = aws_security_group.dr_rds_sg.id
  referenced_security_group_id = aws_security_group.dr_ec2_sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  description                  = "MySQL from DR EC2"
}

# ─── DR Egress Rules ─────────────────────────────────────────────

# DR ALB: All outbound
resource "aws_vpc_security_group_egress_rule" "dr_alb_all_out" {
  provider          = aws.dr
  security_group_id = aws_security_group.dr_alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# DR EC2: All outbound
resource "aws_vpc_security_group_egress_rule" "dr_ec2_all_out" {
  provider          = aws.dr
  security_group_id = aws_security_group.dr_ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
