variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
}
variable "db_password" {
  description = "Aurora database master password"
  type        = string
  sensitive   = true
}