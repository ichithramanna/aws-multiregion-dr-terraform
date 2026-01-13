# Public Subnets

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.three_tier_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.three_tier_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-b"
  }
}


# Private App Subnets

resource "aws_subnet" "app_a" {
  vpc_id            = aws_vpc.three_tier_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "app-subnet-a"
  }
}

resource "aws_subnet" "app_b" {
  vpc_id            = aws_vpc.three_tier_vpc.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "app-subnet-b"
  }
}


# Private DB Subnets

resource "aws_subnet" "db_a" {
  vpc_id            = aws_vpc.three_tier_vpc.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "db-subnet-a"
  }
}

resource "aws_subnet" "db_b" {
  vpc_id            = aws_vpc.three_tier_vpc.id
  cidr_block        = "10.0.22.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "db-subnet-b"
  }
}