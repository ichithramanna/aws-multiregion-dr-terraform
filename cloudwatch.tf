# ─── General Monitoring Alarms ───────────────────────────────────

# HTTPCode_Target_5XX_Count alarm
resource "aws_cloudwatch_metric_alarm" "alb_5xx_alarm" {
  alarm_name          = "alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alarm when ALB target returns 5XX errors"

  dimensions = {
    LoadBalancer = aws_lb.app_alb.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# TargetResponseTime alarm
resource "aws_cloudwatch_metric_alarm" "alb_latency_alarm" {
  alarm_name          = "alb-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 2
  alarm_description   = "Alarm when ALB latency exceeds 2 seconds"

  dimensions = {
    LoadBalancer = aws_lb.app_alb.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# EC2 CPU Alarm
resource "aws_cloudwatch_metric_alarm" "asg_high_cpu" {
  alarm_name          = "asg-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale out when average CPU exceeds 70%"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}


# ==================== DISASTER RECOVERY ALARMS ====================

# ─── Alarm 1: Detects FAILURE (5XX errors) ───────────────────────
# Fires when: Primary ALB ELB-level returns 10+ errors in 60s
# Action: alarm_actions → SNS aurora_failover → Lambda promotes DR
resource "aws_cloudwatch_metric_alarm" "primary_5xx_errors" {
  alarm_name          = "primary-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_description   = "Triggers DB failover when ALB returns 5XX errors (backend failure)"

  dimensions = {
    LoadBalancer = aws_lb.app_alb.arn_suffix
  }

  alarm_actions = [aws_sns_topic.aurora_failover.arn]
  tags          = { Name = "primary-5xx-alarm" }
}
