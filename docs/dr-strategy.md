# Disaster Recovery Strategy

**Project:** Three-Tier AWS Architecture — Multi-Region Active/Passive  
**Repository:** [three-tier-aws-terraform](https://github.com/ichithramanna/three-tier-aws-terraform/tree/feature/disaster-recovery)  
**Primary Region:** us-east-1 (N. Virginia)  
**DR Region:** us-west-2 (Oregon)  
**DR Pattern:** Warm Standby (Active-Passive)  
**Author:** Ichith Ramanna  
**Date:** March 2026

---

## 1. Problem Statement

Modern applications cannot afford extended downtime. A single-region AWS deployment has a single point of failure — if us-east-1 suffers a regional outage, the application becomes completely unavailable with no automatic recovery path.

This document describes the Disaster Recovery strategy designed and implemented to survive a full AWS regional failure automatically, with near-zero data loss, without any manual intervention, and with recovery completed within 1–2 minutes.

---

## 2. Recovery Objectives

| Objective | Target | How Achieved |
|---|---|---|
| **RPO** (max data loss) | < 1 second | Aurora Global Database storage-level replication. Typical lag under 1 second. |
| **RTO** (max downtime) | 1–2 minutes | Lambda automation + Global Accelerator instant traffic shift. Aurora promotion takes 60–90 seconds. |

---

## 3. DR Pattern Selection — Why Warm Standby

AWS defines four disaster recovery patterns in the [Well-Architected Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/plan-for-disaster-recovery-dr.html):

| Pattern | RTO | RPO | Cost | Decision |
|---|---|---|---|---|
| Backup & Restore | Hours | Hours | $ | ❌ Too slow |
| Pilot Light | 10–30 min | Minutes | $$ | ❌ DB not pre-warmed |
| **Warm Standby** | **1–2 min** | **< 1 sec** | **$$$** | **✅ CHOSEN** |
| Multi-Site Active/Active | Near zero | Near zero | $$$$ | ❌ Excessive cost/complexity |

Warm Standby was selected because the DR region runs a full mirror of the primary at all times — VPC, subnets, ALB, Auto Scaling Group, EC2 instances, and an Aurora read replica — but receives zero traffic under normal conditions. When the primary fails, everything is already warm and ready.

> Reference: [AWS Guidance for Disaster Recovery Using Amazon Aurora](https://aws.amazon.com/solutions/guidance/disaster-recovery-using-amazon-aurora/)

---

## 4. Architecture Overview

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
ALB → ASG → EC2 (Flask)              ALB → ASG → EC2 (Flask)
           │                                             │
Aurora MySQL (Writer)  ←── Global Replication ──→  Aurora MySQL (Reader)

Failover chain:
CloudWatch Alarm → SNS → Lambda → rds:FailoverGlobalCluster()
→ DR cluster promoted to Writer → Global Accelerator shifts traffic
```

All traffic enters through AWS Global Accelerator, which holds two static anycast IP addresses that never change.

- **Normal:** 100% of traffic → primary ALB in us-east-1. DR endpoint in us-west-2 receives 0% — running and healthy but idle.
- **Primary stack:** Route 53 → Global Accelerator → ALB → ASG → EC2 (Dockerized Flask) → Aurora MySQL Writer
- **DR stack:** ALB → ASG → EC2 (same Dockerized app) → Aurora MySQL Reader (sub-1-second lag)

---

## 5. Component Breakdown

### 5.1 Aurora Global Database

**File:** [`database-primary-aurora.tf`](https://github.com/ichithramanna/three-tier-aws-terraform/blob/feature/disaster-recovery/database-primary-aurora.tf) · [`database-dr-aurora.tf`](https://github.com/ichithramanna/three-tier-aws-terraform/blob/feature/disaster-recovery/database-dr-aurora.tf)

A single Aurora Global Database cluster named `three-tier-global-db` spans both regions. The primary cluster in us-east-1 is the writer. The secondary cluster in us-west-2 is a reader, continuously receiving storage-level replication.

- Engine: Aurora MySQL 8.0 (`aurora-mysql 8.0.mysql_aurora.3.08.2`)
- Instance class: `db.r6g.large` in both regions
- Both clusters in private DB subnets — no public internet exposure
- DR cluster uses a Terraform aliased provider (`aws.dr`) pointing to us-west-2
- `depends_on` ensures primary is created before DR cluster

> ⚠️ Aurora Global Database replicates automatically but does **NOT** auto-promote the secondary to writer on primary failure. That promotion is automated by Lambda in this project.

> Reference: [Aurora Global Database docs](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html)

---

### 5.2 Lambda Failover and Failback Automation

**File:** [`automation-lambda-failover.tf`](https://github.com/ichithramanna/three-tier-aws-terraform/blob/feature/disaster-recovery/automation-lambda-failover.tf)

Two Python 3.12 Lambda functions handle the complete failover lifecycle.

**Function 1 — `aurora-global-db-failover` (promotes DR cluster to writer):**
1. Calls `describe_global_clusters` to check the current writer
2. If DR cluster (us-west-2) is already writer → skips (idempotent)
3. Calls `rds:FailoverGlobalCluster()` targeting the DR cluster ARN
4. us-west-2 cluster promoted from reader to writer

**Function 2 — `aurora-global-db-failback` (restores primary to writer):**
1. Checks current writer
2. If primary (us-east-1) is already writer → skips
3. Calls `describe_db_clusters` to confirm primary status is `available` — will NOT proceed if primary is still degraded
4. Calls `rds:FailoverGlobalCluster()` targeting the primary cluster ARN

Both functions share a single least-privilege IAM role:  
`rds:FailoverGlobalCluster`, `rds:DescribeGlobalClusters`, `rds:DescribeDBClusters`, CloudWatch Logs write.  
Both have 60-second timeout and are packaged inline as zip archives via `archive_file`.

---

### 5.3 CloudWatch Alarms — Automated Failure Detection

**File:** [`automation-cloudwatch.tf`](https://github.com/ichithramanna/three-tier-aws-terraform/blob/feature/disaster-recovery/automation-cloudwatch.tf)

**Alarm 1 — `primary-alb-5xx-errors` (detects failure):**
- Metric: `HTTPCode_ELB_5XX_Count` on the primary ALB
- Threshold: > 10 errors in a 60-second window
- Action: Publishes to SNS topic `aurora-failover-trigger` → invokes failover Lambda
- `treat_missing_data = notBreaching` — avoids false triggers during quiet periods

---

### 5.4 SNS Topics — Event Bus

**File:** [`automation-sns.tf`](https://github.com/ichithramanna/three-tier-aws-terraform/blob/feature/disaster-recovery/automation-sns.tf)

SNS topics decouple detection from response:
- `aurora-failover-trigger` — subscribed by the failover Lambda

This event-driven architecture (CloudWatch → SNS → Lambda) is the AWS-recommended pattern for automated DR. It is fully serverless, requires no polling infrastructure, and is resilient to partial control plane degradation in the primary region.

> Reference: [AWS Event-Driven Multi-Region DR](https://aws.amazon.com/blogs/architecture/implementing-multi-region-disaster-recovery-using-event-driven-architecture/)

---

### 5.5 AWS Global Accelerator — Traffic Routing

**File:** [`global-accelerator.tf`](https://github.com/ichithramanna/three-tier-aws-terraform/blob/feature/disaster-recovery/global-accelerator.tf)

Two static anycast IPs that never change regardless of failover.

- Primary endpoint group (us-east-1): `traffic_dial_percentage = 100`
- DR endpoint group (us-west-2): `traffic_dial_percentage = 0` — warm but idle

**Health check configuration:**
- Path: `/health` over HTTPS
- Interval: every 10 seconds
- Failover threshold: 3 consecutive failures (~30 seconds to detect)

**Why Global Accelerator over Route 53 failover?**  
Route 53 DNS failover is TTL-dependent. Even at 60 seconds, some clients cache longer. Global Accelerator routes at the network layer using static anycast IPs — traffic shift is immediate regardless of client DNS behaviour. Critical for sub-2-minute RTO.

> Reference: [AWS Global Accelerator](https://aws.amazon.com/global-accelerator/)

---

### 5.6 DR Region Networking

**Files:** [`network-dr-vpc.tf`](https://github.com/ichithramanna/three-tier-aws-terraform/blob/feature/disaster-recovery/network-dr-vpc.tf) · [`network-dr-subnets.tf`](https://github.com/ichithramanna/three-tier-aws-terraform/blob/feature/disaster-recovery/network-dr-subnets.tf) · [`network-dr-routing.tf`](https://github.com/ichithramanna/three-tier-aws-terraform/blob/feature/disaster-recovery/network-dr-routing.tf) · [`network-dr-sg.tf`](https://github.com/ichithramanna/three-tier-aws-terraform/blob/feature/disaster-recovery/network-dr-sg.tf)

The DR region in us-west-2 is a full network mirror of the primary:
- Dedicated VPC with isolated CIDR block
- Public subnets for the DR ALB
- Private subnets for DR EC2 instances (no public access)
- Private DB subnets for the Aurora DR cluster
- Internet Gateway and NAT Gateway for outbound traffic
- Route tables for public and private subnets
- Security groups mirroring primary region rules (ALB, EC2, RDS tiers)

---

### 5.7 DR Compute Layer

**Files:** [`compute-dr-alb.tf`](https://github.com/ichithramanna/three-tier-aws-terraform/blob/feature/disaster-recovery/compute-dr-alb.tf) · [`compute-dr-asg.tf`](https://github.com/ichithramanna/three-tier-aws-terraform/blob/feature/disaster-recovery/compute-dr-asg.tf)

The DR region runs a fully warm compute stack at all times:
- ALB in DR public subnets with `/health` health checks
- Auto Scaling Group with minimum 1 EC2 instance running the same Dockerized Flask + Gunicorn backend
- Instances are healthy and passing ALB health checks continuously

When Global Accelerator shifts traffic to DR, EC2 instances are already running — no cold start, no provisioning delay.

---

## 6. Complete Failover Flow

### Normal State
```
User → Global Accelerator (us-east-1, 100%) → Primary ALB → EC2 → Aurora Writer (us-east-1)
Aurora Writer → continuously replicates → Aurora Reader (us-west-2) [sub-1-second lag]
```

### Failure Event
1. Primary ALB begins returning 5XX errors
2. CloudWatch alarm `primary-alb-5xx-errors` fires (> 10 errors in 60 seconds)
3. Alarm publishes to SNS topic `aurora-failover-trigger`
4. SNS invokes Lambda `aurora-global-db-failover`
5. Lambda confirms failover is needed → calls `rds:FailoverGlobalCluster()`
6. Aurora promotes us-west-2 from reader to writer (60–90 seconds)
7. In parallel: Global Accelerator detects 3 consecutive health check failures (~30 seconds) → shifts 100% traffic to DR ALB
8. **Application fully operational in DR region. Total elapsed time: ~1–2 minutes.**

### Failback

Failback is currently **manual** — after confirming the primary region is 100% stable, failback is initiated deliberately. Customers continue to be served from DR without interruption until then.

Automated failback flow (can be enabled):
1. Primary EC2 instances become healthy, pass ALB health checks
2. CloudWatch alarm `primary-alb-has-healthy-targets` transitions to OK after 2 consecutive minutes
3. OK action publishes to SNS topic `aurora-failback-trigger`
4. Lambda `aurora-global-db-failback` is invoked
5. Lambda confirms primary cluster status is `available`
6. Lambda calls `rds:FailoverGlobalCluster()` — us-east-1 promoted back to writer
7. Global Accelerator `traffic_dial` for us-east-1 reset to 100% (currently manual)
8. System fully restored to normal state

---

## 7. Industry Adoption — Who Uses This Pattern

This is the standard AWS-recommended architecture for production DR with Aurora.

### AWS Official Guidance (March 2026)
AWS published dedicated solution guidance — *"Guidance for Disaster Recovery Using Amazon Aurora"* — recommending this exact Warm Standby + Aurora Global Database architecture as the reference implementation.  
→ [AWS Aurora DR Guidance](https://aws.amazon.com/solutions/guidance/disaster-recovery-using-amazon-aurora/)

### AWS Financial Services Case Study
A large AWS financial customer implemented Aurora Global Database with Lambda-based automated failover, achieving sub-5-minute RTO for cross-region failover using the same pattern.  
→ [AWS Financial Services DR Case Study](https://aws.amazon.com/blogs/database/how-a-large-financial-aws-customer-implemented-ha-and-dr-for-amazon-aurora-postgresql-using-an-event-driven-serverless-architecture/)

### AWS Architecture Blog — Event-Driven Multi-Region DR
AWS explicitly recommends the CloudWatch → SNS → Lambda chain for automated multi-region DR.  
→ [Event-Driven DR Blog](https://aws.amazon.com/blogs/architecture/implementing-multi-region-disaster-recovery-using-event-driven-architecture/)

### AWS Well-Architected Reliability Pillar
Multi-region active/passive DR with automated failover is a defined best practice for workloads with strict RTO/RPO requirements.  
→ [Well-Architected DR](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/plan-for-disaster-recovery-dr.html)

### Real Companies Using This Pattern

**Netflix** — Built multi-region resilience starting from the same active/passive warm standby model. Warm standby was the deliberate first step before evolving to active/active.  
→ [Netflix Tech Blog — Active-Active for Multi-Regional Resiliency](http://techblog.netflix.com/2013/12/active-active-for-multi-regional.html)

**Airbnb** — Runs production databases on Amazon RDS with cross-region replication. Aurora Global Database is the next-generation evolution of this pattern with sub-1-second storage-layer replication.  
→ [Airbnb AWS Case Study](https://aws.amazon.com/solutions/case-studies/airbnb-case-study/)

**Uber** — Implemented multi-region DR with continuous cross-region replication and fully automated region-level failover — the same core principles, achieved here using AWS-native managed services.  
→ [Uber Engineering Blog](https://www.uber.com/blog/kafka/) · [InfoQ — Uber Multi-Region DR](https://www.infoq.com/news/2021/01/uber-multi-region-kafka/)

---

## 8. Key Design Decisions

| Decision | Rationale |
|---|---|
| **Global Accelerator over Route 53** | Route 53 failover is TTL-dependent. Global Accelerator uses static anycast IPs — traffic shift is instant at the network layer. |
| **Aurora Global Database over RDS cross-region replica** | Storage-layer replication gives sub-1-second RPO. Standard RDS cross-region replicas replicate over the network with higher lag. |
| **Lambda automation over manual failover** | Aurora does not auto-promote secondary clusters. Lambda closes this gap with an idempotent, event-driven solution. |
| **Event-driven over cron/polling** | CloudWatch → SNS → Lambda responds in real time. Polling adds delay and requires always-on compute. |
| **Terraform over manual deployment** | Entire dual-region infrastructure is code — reproducible, auditable, rebuildable in minutes. |
| **Warm Standby over Active-Active** | Active-Active requires distributed write handling and conflict resolution at significantly higher cost. Warm Standby meets RTO/RPO targets at a fraction of the cost. |

---

## 9. Known Limitations and Future Improvements

- **Global Accelerator failback not yet automated.** After failback, `traffic_dial_percentage` for us-east-1 must be manually reset to 100. Can be automated by extending the failback Lambda to call the Global Accelerator API.
- **`skip_final_snapshot = true`** is set for easier teardown during development. In production this must be `false` to ensure a final snapshot before any cluster deletion.
