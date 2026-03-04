# create custom VPC
resource "aws_vpc" "marketmate_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "marketmate-vpc"
  }
}

# public subnets for load balancer
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

# internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.marketmate_vpc.id

  tags = {
    Name = "marketmate-igw"
  }
}

# nat instance and jump box to provide 
# internet and ssh access to the docker hosts
resource "aws_security_group" "nat_bastion_sg" {
  name   = "marketmate-nat-sg"
  vpc_id = aws_vpc.marketmate_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.marketmate_vpc.cidr_block]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${local.my_public_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "marketmate-nat-bastion-sg"
  }
}

resource "aws_instance" "nat_instance" {
  ami                    = data.aws_ssm_parameter.al2023_latest_kernel.value
  instance_type          = "t3.micro"
  key_name               = "ec2-user-masterschool"
  subnet_id              = aws_subnet.public_subnet_1a.id
  vpc_security_group_ids = [aws_security_group.nat_bastion_sg.id]
  source_dest_check      = false

  user_data = <<-EOF
    #!/bin/bash
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
    yum install iptables-services -y
    systemctl enable iptables
    systemctl start iptables
    iptables -F FORWARD
    iptables -I FORWARD 1 -j ACCEPT
    ETH_IFACE=$(ip route show default | awk '/default/ {print $5}')
    iptables -t nat -A POSTROUTING -o $ETH_IFACE -j MASQUERADE
    iptables-save > /etc/sysconfig/iptables
  EOF

  tags = {
    Name = "marketmate-nat-instance"
  }

  depends_on = [aws_internet_gateway.igw]
}

# route tables
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

resource "aws_route_table_association" "public_subnet_1a" {
  subnet_id      = aws_subnet.public_subnet_1a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_subnet_1b" {
  subnet_id      = aws_subnet.public_subnet_1b.id
  route_table_id = aws_route_table.public_rt.id
}

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

resource "aws_route_table_association" "private_subnet_1a" {
  subnet_id      = aws_subnet.private_subnet_1a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_subnet_1b" {
  subnet_id      = aws_subnet.private_subnet_1b.id
  route_table_id = aws_route_table.private_rt.id
}
