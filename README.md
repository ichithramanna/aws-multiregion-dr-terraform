THREE-TIER AWS ARCHITECTURE WITH TERRAFORM (DOCKERIZED BACKEND)

==================================================

OVERVIEW
--------
This project implements a **production-style three-tier AWS architecture**
using **Terraform**, with a **Dockerized backend application** deployed on
EC2 instances managed by an **Auto Scaling Group (ASG)** behind an
**Application Load Balancer (ALB)**.

The goal of this project is to demonstrate:
- Real-world AWS architecture design
- Infrastructure as Code (IaC) using Terraform
- Containerized backend deployment
- Load balancing, auto scaling, and health checks
- CI validation using GitHub Actions

This repository is designed for **portfolio use, interviews, and learning**.


ARCHITECTURE (LOGICAL VIEW)
--------------------------
User
├── app.<domain>
│ └── CloudFront
│ └── S3 (Static Frontend)
│
└── api.<domain>
└── Route 53
└── Application Load Balancer (HTTP → HTTPS)
└── Target Group (Health Checks)
└── EC2 Auto Scaling Group
└── Dockerized Backend (Flask + Gunicorn)


KEY FEATURES
------------
FRONTEND
- Static website hosted on Amazon S3
- Delivered via Amazon CloudFront
- HTTPS using ACM (us-east-1 for CloudFront)
- Secure S3 access using Origin Access Control (OAC)

BACKEND
- Dockerized backend application (Flask + Gunicorn)
- Application Load Balancer with health checks
- EC2 Auto Scaling Group for resilience
- Backend exposed only through ALB (no public EC2 access)
- IAM Role attached to EC2 for AWS access (ECR, SSM, future CI/CD)

NETWORKING
- Custom VPC with CIDR isolation
- Public subnets for ALB
- Private subnets for backend EC2 instances
- Internet Gateway and NAT Gateway

DNS & SECURITY
- Route 53 for DNS management
- Separate subdomains for frontend and backend
- Least-privilege Security Groups
- No SSH access (SSM-ready)

INFRASTRUCTURE AS CODE
- Fully managed using Terraform
- Modular, readable resource layout
- Multi-region support for ACM and CloudFront
- Designed to be reproducible and auditable


PROJECT STRUCTURE
-----------------
three-tier-aws-terraform/
├── providers.tf
├── variables.tf
├── outputs.tf
├── vpc.tf
├── subnets.tf
├── igw.tf
├── nat.tf
├── security-groups.tf
├── alb.tf
├── ec2.tf
├── asg.tf
├── frontend_s3.tf
├── cloudfront.tf
├── route53.tf
├── acm.tf
├── terraform-ci.yml
├── README.txt
└── backend/
    ├── Dockerfile
    └── app.py


BACKEND (DOCKER)
----------------
- Backend application is built as a Docker image
- Image is pushed to Amazon ECR
- EC2 instances pull and run the image
- Container listens on port 80
- ALB health checks expect HTTP 200 responses

This setup mirrors real-world containerized workloads
without requiring ECS/Fargate.


CI / GITHUB ACTIONS
-------------------
A Terraform CI pipeline runs on every push and PR:

- terraform init
- terraform validate
- terraform plan

This ensures infrastructure changes are syntactically
correct before deployment.


DEPLOYMENT
----------
Prerequisites:
- AWS account
- AWS CLI configured
- Terraform installed

Commands:
terraform init
terraform validate
terraform plan
terraform apply

After deployment:
- Frontend available via CloudFront domain
- Backend available via ALB / API subdomain


COST NOTES
----------
- NAT Gateway is the highest recurring cost
- ASG runs minimum 1 instance
- No RDS included by default to reduce costs


DESIGN DECISIONS
----------------
- Docker on EC2 instead of ECS:
  Keeps architecture simple while demonstrating containers

- No database:
  Focuses on infrastructure fundamentals and avoids cost

- ALB + ASG:
  Demonstrates real production traffic flow and scaling


FUTURE IMPROVEMENTS
-------------------
- CI/CD deployment pipeline
- ECS or Fargate migration
- RDS or DynamoDB integration
- AWS WAF
- CloudWatch alarms and dashboards


AUTHOR
------
Built by Ichith


LICENSE
-------
MIT License
