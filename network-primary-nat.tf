#Allocate elastic ip
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "nat-eip"
  }
}

#Create NAT gateway and assign the elastic ip to it 

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_a.id

  tags = {
    Name = "three-tier-nat-gateway"
  }

  depends_on = [aws_internet_gateway.three_tier_igw]
}
