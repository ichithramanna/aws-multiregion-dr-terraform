# Three-Tier AWS Multi-Region Disaster Recovery

A production-style three-tier AWS architecture with **automated multi-region disaster recovery**, built entirely with Terraform.

> ⚠️ **Infrastructure is destroyed after demo to avoid AWS costs.**  
> To run this yourself, follow the deployment steps below.

---

## Architecture

```text
                     ┌─────────────────────────────────────┐
                     │           GLOBAL LAYER               │
                     │  Route 53 → CloudFront (app.*)       │
                     │  Route 53 → Global Accelerator (api.*)│
                     └────────────┬────────────────────────┘
                                  │
           ┌──────────────────────┴──────────────────────┐
           │                                             │
  PRIMARY (us-east-1)                          DR (us-west-2)
           │                                             │
S3 + CloudFront (Frontend)         S3 + CloudFront (standby)
           │                                             │
ALB → ASG → EC2 (Flask)              ALB → ASG → EC2 (Flask)
           │                                             │
Aurora MySQL (Writer)  ←── Global Replication ──→  Aurora MySQL (Reader)
           │
    SQS (write buffer during DR promotion)
           │
    Lambda (automated failover + failback)
           │
    CloudWatch Alarms (trigger on 5XX errors)
```

---

## Key Features

### Frontend
- Static HTML/JS hosted on S3, delivered via CloudFront
- HTTPS with ACM certificate, secure S3 access via OAC
- Live region display, Aurora write/read demo buttons

### Backend
- Dockerized Flask + Gunicorn app on EC2 (Auto Scaling Group)
- ALB with HTTPS listener, HTTP→HTTPS redirect
- Endpoints: `/health`, `/region`, `/write`, `/read`
- CORS enabled for frontend domain

### Database
- Aurora Global Database (MySQL 8.0) spanning us-east-1 and us-west-2
- Primary writer in us-east-1, read replica in us-west-2
- Sub-1-second replication lag at storage layer

### Disaster Recovery — Warm Standby (Active-Passive)
- **RPO:** < 1 second | **RTO:** 1–2 minutes
- **Global Accelerator** routes traffic to healthiest region using static anycast IPs
- **CloudWatch** detects primary ALB 5XX errors → triggers failover chain
- **Lambda** automates Aurora Global Database cluster promotion
- **SQS** buffers write requests during Aurora promotion window (~60–90 seconds)
- **Failback** is manual (deliberate) — automated failback available as future improvement

---

## File Structure

```
three-tier-aws-terraform/
├── backend/
│   ├── app.py               # Flask app (region, health, write, read endpoints)
│   ├── Dockerfile
│   └── requirements.txt
│
├── docs/
│   └── dr-strategy.md       # Full DR strategy document
│
├── automation-cloudwatch.tf      # CloudWatch alarms for DR trigger
├── automation-lambda-failover.tf # Lambda for Aurora failover/failback
├── automation-sns.tf             # SNS alert topics
├── automation-sqs.tf             # SQS write buffer queue
│
├── compute-primary-alb.tf        # ALB (us-east-1)
├── compute-primary-ec2.tf        # Launch template + ASG (us-east-1)
├── compute-dr-alb.tf             # ALB (us-west-2)
├── compute-dr-asg.tf             # Launch template + ASG (us-west-2)
│
├── database-primary-aurora.tf    # Aurora cluster (us-east-1)
├── database-dr-aurora.tf         # Aurora replica cluster (us-west-2)
│
├── frontend-s3.tf                # S3 bucket + index.html
├── frontend-cloudfront.tf        # CloudFront distribution
│
├── global-accelerator.tf         # Global Accelerator + endpoint groups
├── global-route53.tf             # DNS records
├── global-acm-primary.tf         # ACM cert (us-east-1)
├── global-acm-dr.tf              # ACM cert (us-west-2)
│
├── network-primary-vpc.tf        # VPC (us-east-1)
├── network-primary-subnets.tf
├── network-primary-igw.tf
├── network-primary-nat.tf
├── network-primary-routes.tf
├── network-primary-sg.tf
├── network-dr-vpc.tf             # VPC (us-west-2)
├── network-dr-subnets.tf
├── network-dr-routing.tf
├── network-dr-sg.tf
│
├── provider.tf
├── variables.tf
├── outputs.tf
└── terraform.tfvars
```

---

## Deployment

**Prerequisites:** AWS CLI configured, Terraform installed, Docker image pushed to ECR.

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

After apply:
- Frontend available at your CloudFront domain
- Backend health: `https://<your-api-domain>/health`
- Backend region: `https://<your-api-domain>/region`


---

## DR Failover Flow

1. Primary ALB begins returning 5XX errors
2. CloudWatch alarm fires → SNS → Lambda
3. Lambda calls `rds:FailoverGlobalCluster()` — DR cluster promoted to writer
4. Global Accelerator detects unhealthy primary → shifts 100% traffic to DR ALB
5. SQS drains buffered writes into newly promoted Aurora writer
6. **System fully operational in DR region within ~1–2 minutes**

Full strategy document: [docs/dr-strategy.md](docs/dr-strategy.md)

---

## Author

Built by Ichith — [github.com/ichithramanna](https://github.com/ichithramanna)

## License

MIT
