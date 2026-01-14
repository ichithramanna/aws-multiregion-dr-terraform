# Three-Tier AWS Architecture with Terraform

## Overview

This project implements a **production‑grade three‑tier AWS architecture** using **Terraform**. It demonstrates how to design, deploy, secure, and operate a modern web application infrastructure using Infrastructure as Code (IaC).

The architecture separates concerns into **frontend**, **backend**, and **infrastructure layers**, following AWS and DevOps best practices.

This repository is intended for:

* Learning real‑world AWS architecture
* Demonstrating Terraform and DevOps skills
* Portfolio and interview discussion

---

## Architecture Diagram (Logical)

```
User
 ├── app.ichith.it  → CloudFront → S3 (Static Frontend)
 └── api.ichith.it  → Route53 → Application Load Balancer (HTTPS)
                           ↓
                      Target Group
                           ↓
                 EC2 Auto Scaling Group
                           ↓
                    (Optional RDS)
```

---

## Key Features

### Frontend

* Static HTML frontend hosted on **Amazon S3**
* Delivered globally using **Amazon CloudFront**
* Custom domain with HTTPS using **ACM (us‑east‑1)**
* Secure access using **Origin Access Control (OAC)**

### Backend

* **Application Load Balancer (ALB)** with HTTP → HTTPS redirect
* **Auto Scaling Group** running Amazon Linux EC2 instances
* Health‑checked backend targets
* HTTPS using **ACM certificate in ALB region**

### Networking

* Custom **VPC** with CIDR isolation
* Public subnets for ALB
* Private subnets for application instances
* Internet Gateway and NAT Gateway

### DNS & Security

* **Route 53** for DNS management
* Separate domains for frontend and backend
* Least‑privilege **Security Groups**
* No public access to EC2 instances

### Infrastructure as Code

* Fully managed using **Terraform**
* Multi‑region provider configuration
* Clean resource separation across files

---

## AWS Services Used

* Amazon VPC
* Amazon EC2
* Auto Scaling Group
* Application Load Balancer
* Amazon S3
* Amazon CloudFront
* Amazon Route 53
* AWS Certificate Manager (ACM)
* IAM
* Terraform

---

## Project Structure

```
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
├── asg.tf
├── s3.tf
├── cloudfront.tf
├── route53.tf
├── acm.tf
├── README.md
```

---

## Deployment Instructions

### Prerequisites

* AWS account
* AWS CLI configured
* Terraform installed

### Steps

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

After deployment:

* Frontend: `https://app.ichith.it`
* Backend: `https://api.ichith.it`

---

## Cost Considerations

* NAT Gateway is the highest recurring cost
* Auto Scaling Group runs with minimum instances
* No RDS used by default to keep costs low

This design balances **realism** with **cost efficiency**.

---

## Design Decisions

### Why no RDS?

* Not required for demonstrating architecture
* Avoids unnecessary cost and complexity
* Can be added later without redesign

### Why CloudFront + S3?

* Best practice for static content
* High performance and low cost
* Secure origin access

### Why Terraform?

* Reproducible infrastructure

* Version controlled deployments

* Industry‑standard IaC tool

* Real‑world AWS architecture design

* TLS, DNS, and certificate management

* Debugging real infrastructure issues

* Terraform best practices

* DevOps mindset and cloud responsibility

---

## Future Enhancements

* CI/CD using GitHub Actions
* Backend containerization (ECS/Fargate)
* Optional RDS integration
* AWS WAF for security hardening
* Monitoring and alerting

---

## Author

Built and maintained by **Ichith**

---

## License

MIT License
