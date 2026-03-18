# ─── IAM Role  ───────────────────
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
        Action   = ["globalaccelerator:UpdateEndpointGroup", "globalaccelerator:DescribeEndpointGroup"]
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


# ─── FAILOVER Lambda (primary dies → promote DR + lock traffic) ──
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
PRIMARY_ENDPOINT_GROUP_ARN = os.environ["PRIMARY_ENDPOINT_GROUP_ARN"]
DR_ENDPOINT_GROUP_ARN = os.environ["DR_ENDPOINT_GROUP_ARN"]
PRIMARY_ALB_ARN = os.environ["PRIMARY_ALB_ARN"]
DR_ALB_ARN = os.environ["DR_ALB_ARN"]

def handler(event, context):
    logger.info("Failover triggered")
    rds_client = boto3.client("rds", region_name="us-east-1")
    
    clusters = rds_client.describe_global_clusters(
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
    
    logger.info("Promoting DR database to writer")
    resp = rds_client.failover_global_cluster(
        GlobalClusterIdentifier=GLOBAL_CLUSTER_ID,
        TargetDbClusterIdentifier=TARGET_DB_CLUSTER
    )
    logger.info("Database failover initiated: %s", json.dumps(resp, default=str))
    
    logger.info("Updating Global Accelerator weights")
    ga_client = boto3.client("globalaccelerator", region_name="us-west-2")
    
    ga_client.update_endpoint_group(
        EndpointGroupArn=PRIMARY_ENDPOINT_GROUP_ARN,
        EndpointConfigurations=[{
            'EndpointId': PRIMARY_ALB_ARN,
            'Weight': 0,
            'ClientIPPreservationEnabled': True
        }]
    )
    logger.info("Primary weight set to 0")
    
    ga_client.update_endpoint_group(
        EndpointGroupArn=DR_ENDPOINT_GROUP_ARN,
        EndpointConfigurations=[{
            'EndpointId': DR_ALB_ARN,
            'Weight': 100,
            'ClientIPPreservationEnabled': True
        }]
    )
    logger.info("DR weight set to 100")
    
    return {"status": "initiated", "traffic_locked": "DR"}
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
      GLOBAL_CLUSTER_ID          = aws_rds_global_cluster.main.id
      TARGET_DB_CLUSTER_ARN      = aws_rds_cluster.dr.arn
      PRIMARY_ENDPOINT_GROUP_ARN = aws_globalaccelerator_endpoint_group.primary.arn
      DR_ENDPOINT_GROUP_ARN      = aws_globalaccelerator_endpoint_group.dr.arn
      PRIMARY_ALB_ARN            = aws_lb.app_alb.arn
      DR_ALB_ARN                 = aws_lb.dr_alb.arn
    }
  }
  
  tags = { Name = "aurora-failover-lambda" }
}




# ─── SNS: Failover ───────────────────────────────────────────────
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
