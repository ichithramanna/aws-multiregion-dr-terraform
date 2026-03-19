terraform {
  backend "s3" {
    bucket  = "my-tf-state-bucket"      # S3 bucket name
    key     = "multiregion-dr/terraform.tfstate"   # path inside bucket
    region  = "us-east-1"
    encrypt = true
  }
}