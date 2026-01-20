#Create the SNS Topic

resource "aws_sns_topic" "alerts" {
  name = "infra-alerts"
}

# Add Email Subscription

resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "ichithgowdar@gmail.com"
}
