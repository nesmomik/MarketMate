# nat instance
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

# docker host
resource "aws_security_group" "docker_app_flask_sg" {
  name   = "marketmate-app-sg"
  vpc_id = aws_vpc.marketmate_vpc.id

  # only allow inbound from the load balancer
  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer_sg.id]
  }

  # allow inbound from bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.nat_bastion_sg.id]

  }

  # cant omit egress rule in terraform 
  # needed for fetching frontend zip and docker images
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.nat_bastion_sg.id]
  }
}

# DB
resource "aws_security_group" "rds_sg" {
  name   = "marketmate-rds-sg"
  vpc_id = aws_vpc.marketmate_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.docker_app_flask_sg.id]
  }
}


# DB subnet group
resource "aws_db_subnet_group" "marketmate_db_subnet" {
  name       = "marketmate-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1a.id, aws_subnet.private_subnet_1b.id]

  tags = {
    Name = "marketmate-db-subnet-group"
  }
}

# load balancer
resource "aws_security_group" "load_balancer_sg" {
  name   = "marketmate-lb-sg"
  vpc_id = aws_vpc.marketmate_vpc.id

  # allow public HTTP (no HTTPS, because no DNS) 
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
