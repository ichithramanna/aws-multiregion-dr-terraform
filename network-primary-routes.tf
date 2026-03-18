#Route table attached to Internet gateway

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.three_tier_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.three_tier_igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

#Route table association to public subnets
resource "aws_route_table_association" "public_a_assoc" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_b_assoc" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}


#Route table attached to NAT gateway
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.three_tier_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "private-route-table"
  }
}

#Route table association to private subnet
resource "aws_route_table_association" "app_a_assoc" {
  subnet_id      = aws_subnet.app_a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "app_b_assoc" {
  subnet_id      = aws_subnet.app_b.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "db_a_assoc" {
  subnet_id      = aws_subnet.db_a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "db_b_assoc" {
  subnet_id      = aws_subnet.db_b.id
  route_table_id = aws_route_table.private_rt.id
}
