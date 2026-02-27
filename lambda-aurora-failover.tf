# ─── Shared IAM Role (both Lambdas reuse this) ───────────────────
resource "aws_iam_role" "aurora_failover_lambda" {
  name = "aurora-failover-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "aurora_failover_lambda" {
  name = "aurora-failover-lambda-policy"
  role = aws_iam_role.aurora_failover_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["rds:FailoverGlobalCluster", "rds:DescribeGlobalClusters", "rds:DescribeDBClusters"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ─── FAILOVER Lambda (primary dies → promote DR) ─────────────────
data "archive_file" "aurora_failover" {
  type        = "zip"
  output_path = "${path.module}/aurora_failover.zip"
  source {
    filename = "handler.py"
    content  = <<-PYTHON
import boto3, os, json, logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

GLOBAL_CLUSTER_ID = os.environ["GLOBAL_CLUSTER_ID"]
TARGET_DB_CLUSTER = os.environ["TARGET_DB_CLUSTER_ARN"]

def handler(event, context):
    logger.info("Failover triggered")
    client = boto3.client("rds", region_name="us-east-1")

    clusters = client.describe_global_clusters(
        GlobalClusterIdentifier=GLOBAL_CLUSTER_ID
    )["GlobalClusters"]
    if not clusters:
        return {"status": "skipped", "reason": "not found"}

    writers = [m for m in clusters[0]["GlobalClusterMembers"] if m["IsWriter"]]
    if not writers:
        return {"status": "skipped", "reason": "no writer"}

    if "us-west-2" in writers[0]["DBClusterArn"]:
        logger.info("DR already writer — skipping")
        return {"status": "skipped", "reason": "already failed over"}

    resp = client.failover_global_cluster(
        GlobalClusterIdentifier=GLOBAL_CLUSTER_ID,
        TargetDbClusterIdentifier=TARGET_DB_CLUSTER
    )
    logger.info("Failover initiated: %s", json.dumps(resp, default=str))
    return {"status": "initiated"}
PYTHON
  }
}

resource "aws_lambda_function" "aurora_failover" {
  function_name    = "aurora-global-db-failover"
  role             = aws_iam_role.aurora_failover_lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.aurora_failover.output_path
  source_code_hash = data.archive_file.aurora_failover.output_base64sha256
  timeout          = 60
  environment {
    variables = {
      GLOBAL_CLUSTER_ID     = aws_rds_global_cluster.main.id
      TARGET_DB_CLUSTER_ARN = aws_rds_cluster.dr.arn   # promote DR
    }
  }
  tags = { Name = "aurora-failover-lambda" }
}

# ─── FAILBACK Lambda (primary recovers → promote primary back) ────
data "archive_file" "aurora_failback" {
  type        = "zip"
  output_path = "${path.module}/aurora_failback.zip"
  source {
    filename = "handler.py"
    content  = <<-PYTHON
import boto3, os, json, logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

GLOBAL_CLUSTER_ID = os.environ["GLOBAL_CLUSTER_ID"]
TARGET_DB_CLUSTER = os.environ["TARGET_DB_CLUSTER_ARN"]

def handler(event, context):
    logger.info("Failback triggered")
    client = boto3.client("rds", region_name="us-east-1")

    clusters = client.describe_global_clusters(
        GlobalClusterIdentifier=GLOBAL_CLUSTER_ID
    )["GlobalClusters"]
    if not clusters:
        return {"status": "skipped", "reason": "not found"}

    writers = [m for m in clusters[0]["GlobalClusterMembers"] if m["IsWriter"]]
    if not writers:
        return {"status": "skipped", "reason": "no writer"}

    if "us-east-1" in writers[0]["DBClusterArn"]:
        logger.info("Primary already writer — skipping")
        return {"status": "skipped", "reason": "already primary"}

    # Guard: primary cluster must be available before failback
    primary_id = TARGET_DB_CLUSTER.split(":")[-1]
    info = client.describe_db_clusters(DBClusterIdentifier=primary_id)
    status = info["DBClusters"][0]["Status"]
    if status != "available":
        logger.warning("Primary status: %s — not ready", status)
        return {"status": "skipped", "reason": f"primary not available: {status}"}

    resp = client.failover_global_cluster(
        GlobalClusterIdentifier=GLOBAL_CLUSTER_ID,
        TargetDbClusterIdentifier=TARGET_DB_CLUSTER
    )
    logger.info("Failback initiated: %s", json.dumps(resp, default=str))
    return {"status": "initiated"}
PYTHON
  }
}

resource "aws_lambda_function" "aurora_failback" {
  function_name    = "aurora-global-db-failback"
  role             = aws_iam_role.aurora_failover_lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.aurora_failback.output_path
  source_code_hash = data.archive_file.aurora_failback.output_base64sha256
  timeout          = 60
  environment {
    variables = {
      GLOBAL_CLUSTER_ID     = aws_rds_global_cluster.main.id
      TARGET_DB_CLUSTER_ARN = aws_rds_cluster.primary.arn  # promote PRIMARY back
    }
  }
  tags = { Name = "aurora-failback-lambda" }
}

# ─── SNS: Failover (alarm fires this) ────────────────────────────
resource "aws_sns_topic" "aurora_failover" {
  name = "aurora-failover-trigger"
}
resource "aws_sns_topic_subscription" "aurora_failover_lambda" {
  topic_arn = aws_sns_topic.aurora_failover.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.aurora_failover.arn
}
resource "aws_lambda_permission" "aurora_failover_sns" {
  statement_id  = "AllowSNSInvokeFailover"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aurora_failover.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.aurora_failover.arn
}

# ─── SNS: Failback (alarm OK fires this) ─────────────────────────
resource "aws_sns_topic" "aurora_failback" {
  name = "aurora-failback-trigger"
}
resource "aws_sns_topic_subscription" "aurora_failback_lambda" {
  topic_arn = aws_sns_topic.aurora_failback.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.aurora_failback.arn
}
resource "aws_lambda_permission" "aurora_failback_sns" {
  statement_id  = "AllowSNSInvokeFailback"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aurora_failback.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.aurora_failback.arn
}

# ─── CloudWatch Alarm: Primary ALB health ────────────────────────
# period=10, evaluation_periods=3 → fires after 30s
# alarm_actions = failover SNS (primary dead → promote DR)
# ok_actions    = failback SNS (primary recovered → promote back)
resource "aws_cloudwatch_metric_alarm" "primary_alb_db_failover" {
  alarm_name          = "primary-alb-unhealthy-trigger-db-failover"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 10
  statistic           = "Minimum"
  threshold           = 0

  dimensions = {
    LoadBalancer = aws_lb.app_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.app_tg.arn_suffix
  }

  alarm_actions = [aws_sns_topic.aurora_failover.arn]
  ok_actions    = [aws_sns_topic.aurora_failback.arn]
  tags          = { Name = "primary-alb-db-failover-alarm" }
}
