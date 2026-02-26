# DR Public Subnets -ALB
resource "aws_subnet" "dr_public_a" {
  provider                = aws.dr
  vpc_id                  = aws_vpc.dr.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "dr-public-subnet-a"
  }
}

resource "aws_subnet" "dr_public_b" {
  provider                = aws.dr
  vpc_id                  = aws_vpc.dr.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "us-west-2b"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "dr-public-subnet-b"
  }
}

# DR App Subnets - EC2 
resource "aws_subnet" "dr_app_a" {
  provider          = aws.dr
  vpc_id            = aws_vpc.dr.id
  cidr_block        = "10.1.11.0/24"
  availability_zone = "us-west-2a"
  
  tags = {
    Name = "dr-app-subnet-a"
  }
}

resource "aws_subnet" "dr_app_b" {
  provider          = aws.dr
  vpc_id            = aws_vpc.dr.id
  cidr_block        = "10.1.12.0/24"
  availability_zone = "us-west-2b"
  
  tags = {
    Name = "dr-app-subnet-b"
  }
}

# DR DB Subnets - Aurora
resource "aws_subnet" "dr_db_a" {
  provider          = aws.dr
  vpc_id            = aws_vpc.dr.id
  cidr_block        = "10.1.21.0/24"
  availability_zone = "us-west-2a"
  
  tags = {
    Name = "dr-db-subnet-a"
  }
}

resource "aws_subnet" "dr_db_b" {
  provider          = aws.dr
  vpc_id            = aws_vpc.dr.id
  cidr_block        = "10.1.22.0/24"
  availability_zone = "us-west-2b"
  
  tags = {
    Name = "dr-db-subnet-b"
  }
}
