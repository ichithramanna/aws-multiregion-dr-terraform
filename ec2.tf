#IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "ec2-app-role"

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
#Attach ECR permissions to EC2 role
resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


#Attach SSM permissions for accesing Ec2 using SSM
resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role      = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#Instance profile because EC2 cannot use roles directly
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-app-profile"
  role = aws_iam_role.ec2_role.name
}

#AMI Lookup for Amazon Linux instead of hardcoded AMI IDs
data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  owners = ["amazon"]
}

#Launch Template for EC2
resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  user_data = base64encode(<<-EOF
  #!/bin/bash
  set -e

  # Update system
  yum update -y

  # Install Docker
  amazon-linux-extras install docker -y
  systemctl start docker
  systemctl enable docker
  usermod -aG docker ec2-user

  # Install AWS CLI v2 (needed for ECR login)
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  ./aws/install

  # Login to ECR
  aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS \
  --password-stdin 002506421910.dkr.ecr.us-east-1.amazonaws.com

  # Pull backend image
  docker pull 002506421910.dkr.ecr.us-east-1.amazonaws.com/backend-app:latest

  # Run container
  docker run -d \
  --restart always \
  -p 80:80 \
  002506421910.dkr.ecr.us-east-1.amazonaws.com/backend-app:latest
  EOF
  )
}

#Auto Scaling Group
resource "aws_autoscaling_group" "app_asg" {
  desired_capacity = 1
  max_size         = 2
  min_size         = 1

  vpc_zone_identifier = [
    aws_subnet.app_a.id,
    aws_subnet.app_b.id
  ]

  target_group_arns = [
    aws_lb_target_group.app_tg.arn
  ]

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 240

  tag {
    key                 = "Name"
    value               = "app-backend"
    propagate_at_launch = true
  }
}
