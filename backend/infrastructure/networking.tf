# get public ip for restricted ssh access
data "http" "my_public_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  # chomp removes trailing new lines
  my_public_ip  = chomp(data.http.my_public_ip.response_body)
}

# create custom VPC
resource "aws_vpc" "marketmate_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "marketmate-vpc"
  }
}

# internet gateway for custom vpc
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.marketmate_vpc.id

  tags = {
    Name = "marketmate-igw"
  }
}

# public subnets for load balancer and nat instance
resource "aws_subnet" "public_subnet_1a" {
  vpc_id                  = aws_vpc.marketmate_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "marketmate-public-1a"
  }
}

resource "aws_subnet" "public_subnet_1b" {
  vpc_id                  = aws_vpc.marketmate_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-central-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "marketmate-public-1b"
  }
}

# private subnets for ec2 and rds
resource "aws_subnet" "private_subnet_1a" {
  vpc_id            = aws_vpc.marketmate_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "marketmate-private-1a"
  }
}

resource "aws_subnet" "private_subnet_1b" {
  vpc_id            = aws_vpc.marketmate_vpc.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "eu-central-1b"

  tags = {
    Name = "marketmate-private-1b"
  }
}

# route all outgoing traffic to the internet gateway
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.marketmate_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "marketmate-public-rt"
  }
}

# allow all traffic
resource "aws_route_table_association" "public_subnet_1a" {
  subnet_id      = aws_subnet.public_subnet_1a.id
  route_table_id = aws_route_table.public_rt.id
}

# allow all traffic
resource "aws_route_table_association" "public_subnet_1b" {
  subnet_id      = aws_subnet.public_subnet_1b.id
  route_table_id = aws_route_table.public_rt.id
}

# route all traffic all outgoing traffic to the nat instance
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.marketmate_vpc.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat_instance.primary_network_interface_id
  }

  tags = {
    Name = "marketmate-private-rt"
  }
}

# allow traffic throught nat instance
resource "aws_route_table_association" "private_subnet_1a" {
  subnet_id      = aws_subnet.private_subnet_1a.id
  route_table_id = aws_route_table.private_rt.id
}

# allow traffic throught nat instance
resource "aws_route_table_association" "private_subnet_1b" {
  subnet_id      = aws_subnet.private_subnet_1b.id
  route_table_id = aws_route_table.private_rt.id
}

