terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}
