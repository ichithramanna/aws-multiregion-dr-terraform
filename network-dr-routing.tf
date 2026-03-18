# ─── Internet Gateway ───────────────────────────────────────────
resource "aws_internet_gateway" "dr" {
  provider = aws.dr
  vpc_id   = aws_vpc.dr.id

  tags = {
    Name = "dr-igw"
  }
}

# ─── Elastic IP for NAT Gateway ─────────────────────────────────
resource "aws_eip" "dr_nat" {
  provider = aws.dr
  domain   = "vpc"

  tags = {
    Name = "dr-nat-eip"
  }
}

# ─── NAT Gateway (lives in public subnet) ───────────────────────
resource "aws_nat_gateway" "dr" {
  provider      = aws.dr
  allocation_id = aws_eip.dr_nat.id
  subnet_id     = aws_subnet.dr_public_a.id

  tags = {
    Name = "dr-nat-gateway"
  }

  depends_on = [aws_internet_gateway.dr]
}

# ─── Public Route Table ──────────────────────────────────────────
# Routes all internet traffic through IGW
resource "aws_route_table" "dr_public" {
  provider = aws.dr
  vpc_id   = aws_vpc.dr.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dr.id
  }

  tags = {
    Name = "dr-public-rt"
  }
}

# Associate both public subnets with public route table
resource "aws_route_table_association" "dr_public_a" {
  provider       = aws.dr
  subnet_id      = aws_subnet.dr_public_a.id
  route_table_id = aws_route_table.dr_public.id
}

resource "aws_route_table_association" "dr_public_b" {
  provider       = aws.dr
  subnet_id      = aws_subnet.dr_public_b.id
  route_table_id = aws_route_table.dr_public.id
}

# ─── Private Route Table ─────────────────────────────────────────
# Routes outbound traffic through NAT Gateway
resource "aws_route_table" "dr_private" {
  provider = aws.dr
  vpc_id   = aws_vpc.dr.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.dr.id
  }

  tags = {
    Name = "dr-private-rt"
  }
}

# Associate app subnets with private route table
resource "aws_route_table_association" "dr_app_a" {
  provider       = aws.dr
  subnet_id      = aws_subnet.dr_app_a.id
  route_table_id = aws_route_table.dr_private.id
}

resource "aws_route_table_association" "dr_app_b" {
  provider       = aws.dr
  subnet_id      = aws_subnet.dr_app_b.id
  route_table_id = aws_route_table.dr_private.id
}
