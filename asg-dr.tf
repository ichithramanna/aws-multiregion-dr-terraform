# ─── DR AMI Lookup ───────────────────────────────────────────────
# Must use aws.dr provider — AMI IDs are REGION SPECIFIC
# Same Amazon Linux 2 filter as primary but resolves to us-west-2 AMI
data "aws_ami" "amazon_linux_dr" {
  provider    = aws.dr
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  owners = ["amazon"]
}

# ─── DR IAM Role ─────────────────────────────────────────────────
# IAM is GLOBAL but roles cannot be reused across provider aliases
# DR EC2 needs its own role + profile referencing same policies
resource "aws_iam_role" "dr_ec2_role" {
  name = "dr-ec2-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}
# SQS permission — DR EC2 needs to send/receive/delete from write buffer
resource "aws_iam_role_policy" "dr_sqs_access" {
  name = "dr-sqs-access-policy"
  role = aws_iam_role.dr_ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource = aws_sqs_queue.dr_write_buffer.arn
    }]
  })
}

# RDS permission — DR EC2 app thread calls describe_global_clusters
resource "aws_iam_role_policy" "dr_rds_describe" {
  name = "dr-rds-describe-policy"
  role = aws_iam_role.dr_ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rds:DescribeGlobalClusters"]
      Resource = "*"
    }]
  })
}

# ECR read access — DR EC2 pulls from us-east-1 ECR cross-region
resource "aws_iam_role_policy_attachment" "dr_ecr_read" {
  role       = aws_iam_role.dr_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# SSM access —  SSH into DR EC2 without key pairs
resource "aws_iam_role_policy_attachment" "dr_ssm_attach" {
  role       = aws_iam_role.dr_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile — EC2 cannot use IAM roles directly, needs profile
resource "aws_iam_instance_profile" "dr_ec2_profile" {
  name = "dr-ec2-app-profile"
  role = aws_iam_role.dr_ec2_role.name
}

# ─── DR Launch Template ──────────────────────────────────────────
resource "aws_launch_template" "dr_app_lt" {
  provider      = aws.dr
  name_prefix   = "dr-app-lt-"
  image_id      = data.aws_ami.amazon_linux_dr.id  # us-west-2 AMI
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.dr_ec2_profile.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.dr_ec2_sg.id]
  }

  # User data mirrors primary exactly
  # ECR is in us-east-1 — DR EC2 pulls cross-region (works fine)
  # Only change: login region stays us-east-1 (where ECR lives)
  user_data = base64encode(<<-EOF
  #!/bin/bash
  set -e

  yum update -y
  amazon-linux-extras install docker -y
  systemctl start docker
  systemctl enable docker
  usermod -aG docker ec2-user

  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  ./aws/install

  aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS \
  --password-stdin 002506421910.dkr.ecr.us-east-1.amazonaws.com

  docker pull 002506421910.dkr.ecr.us-east-1.amazonaws.com/backend-app:latest

  docker run -d \
  --restart always \
  -p 80:80 \
  -e DB_HOST="${aws_rds_cluster.dr.endpoint}" \
  -e DB_PASSWORD="${var.db_password}" \
  -e SQS_QUEUE_URL="${aws_sqs_queue.dr_write_buffer.url}" \
  -e GLOBAL_CLUSTER_ID="three-tier-global-db" \
  -e TARGET_CLUSTER_ARN="${aws_rds_cluster.dr.arn}" \
  -e AWS_REGION="us-west-2" \
  002506421910.dkr.ecr.us-east-1.amazonaws.com/backend-app:latest
  EOF
  )
}

# ─── DR Auto Scaling Group ───────────────────────────────────────
# Mirrors primary ASG — min 1, max 2, desired 1
# Registers instances with DR target group (not primary)
resource "aws_autoscaling_group" "dr_app_asg" {
  provider         = aws.dr
  desired_capacity = 1
  max_size         = 2
  min_size         = 1

  vpc_zone_identifier = [
    aws_subnet.dr_app_a.id,
    aws_subnet.dr_app_b.id
  ]

  target_group_arns = [
    aws_lb_target_group.dr_app_tg.arn
  ]

  launch_template {
    id      = aws_launch_template.dr_app_lt.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 240

  tag {
    key                 = "Name"
    value               = "dr-app-backend"
    propagate_at_launch = true
  }
}
