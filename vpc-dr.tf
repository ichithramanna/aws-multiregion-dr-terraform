# DR VPC - us-west-2
# Mirrors primary VPC structure with different CIDR (10.1.x.x vs 10.0.x.x)
resource "aws_vpc" "dr" {
  provider   = aws.dr
  cidr_block = "10.1.0.0/16"
  
  enable_dns_support   = true
  enable_dns_hostnames = true
  
  tags = {
    Name = "dr-vpc"
  }
}
