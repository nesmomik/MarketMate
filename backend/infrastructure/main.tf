terraform {
  backend "s3" {
    bucket         = "marketmate-tf-state"
    key            = "marketmate/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-state-locking"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# output variables for testing
output "alb_dns_name" {
  value = aws_lb.load_balancer.dns_name
}

output "docker_host_1_private_ip" {
  value = aws_instance.docker_host_1.private_ip
}

output "docker_host_2_private_ip" {
  value = aws_instance.docker_host_2.private_ip
}

output "nat_instance_public_ip" {
  value = aws_instance.nat_instance.public_ip
}

# input variables stored in terraform.tfvars
variable "postgres_password" {
  type = string
  # hides the value in console outputs
  sensitive = true
}

variable "jwt_secret_key" {
  type      = string
  sensitive = true
}

variable "marketmate_db_user" {
  type = string
}

variable "marketmate_db_name" {
  type = string
}

# data blocks for information that already exists before executing apply 
# get account ID, region and 
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
# get latest Amazon Linux 2023 image
data "aws_ssm_parameter" "al2023_latest_kernel" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
# get public ip for restricted ssh access
data "http" "my_public_ip" {

  url = "https://checkip.amazonaws.com"
}
# create new VPC
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
    Name = "marketmate-nat-sg"
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

# local variables
locals {
  # set project root relative to the location of the main.tf file 
  project_root = abspath("${path.root}/..")
  # chomp removes trailing new lines
  my_public_ip  = chomp(data.http.my_public_ip.response_body)
  ec2_user_data = <<-EOF
    #!/bin/bash
    until curl -sS --connect-timeout 5 https://google.com > /dev/null; do
      echo "Waiting for internet connection..."
      sleep 5
    done
    yum update -y
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
    aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com
    docker pull ${aws_ecr_repository.marketmate_repo.repository_url}:latest
    docker run -d \
      --name marketmate-app \
      -p 5000:5000 \
      -e S3_BUCKET_NAME=marketmate-avatars \
      -e S3_REGION=eu-central-1 \
      -e USE_S3_STORAGE=true \
      -e POSTGRES_USER="${var.marketmate_db_user}" \
      -e POSTGRES_PASSWORD="${var.postgres_password}" \
      -e POSTGRES_DB="${var.marketmate_db_name}" \
      -e POSTGRES_HOST="${aws_db_instance.marketmate_db.address}" \
      -e POSTGRES_PORT="5432" \
      -e JWT_SECRET_KEY="${var.jwt_secret_key}" \
      "${aws_ecr_repository.marketmate_repo.repository_url}:latest"
  EOF
}

# create two ec2 instances
resource "aws_instance" "docker_host_1" {
  ami                    = data.aws_ssm_parameter.al2023_latest_kernel.value
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.docker_app_flask_sg.id]
  key_name               = "ec2-user-masterschool"
  subnet_id              = aws_subnet.private_subnet_1a.id

  # Attach the IAM Profile
  iam_instance_profile = aws_iam_instance_profile.docker_host_profile.name

  user_data = local.ec2_user_data

  tags = {
    Name = "marketmate-docker-host-1"
  }

  depends_on = [aws_instance.nat_instance]
}

resource "aws_instance" "docker_host_2" {
  ami                    = data.aws_ssm_parameter.al2023_latest_kernel.value
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.docker_app_flask_sg.id]
  key_name               = "ec2-user-masterschool"
  subnet_id              = aws_subnet.private_subnet_1b.id

  iam_instance_profile = aws_iam_instance_profile.docker_host_profile.name

  user_data = local.ec2_user_data

  tags = {
    Name = "marketmate-docker-host-1"
  }

  depends_on = [aws_instance.nat_instance]
}

# create security group for instances
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
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "marketmate_db_subnet" {
  name       = "marketmate-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1a.id, aws_subnet.private_subnet_1b.id]

  tags = {
    Name = "marketmate-db-subnet-group"
  }
}

resource "aws_db_instance" "marketmate_db" {
  identifier             = "marketmate-db"
  instance_class         = "db.t3.micro"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.marketmate_db_subnet.name
  availability_zone      = "eu-central-1a"

  snapshot_identifier = "marketmate-db-pre-destroy-snapshot"

  # prevents deletion via console or API
  deletion_protection = false

  # snapshot management
  skip_final_snapshot       = true
  final_snapshot_identifier = "marketmate-db-pre-destroy-snapshot"

  # prevents 'terraform destroy'
  lifecycle {
    prevent_destroy = false
  }
}

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

# create S3 bucket
resource "aws_s3_bucket" "avatars" {
  bucket = "marketmate-avatars"

  tags = {
    Name = "marketmate-avatars"
  }
}

resource "aws_s3_object" "avatars_bucket" {
  bucket = aws_s3_bucket.avatars.id
  key    = "avatars/user_default.png"
  source = "${local.project_root}/avatar/user_default.png"
  # check if file changed
  etag = filemd5("${local.project_root}/avatar/user_default.png")
}

# set up load balancer
# the load balancer is the entry point
# - looks at the request path and decides what to do with the incoming traffic
#   according to matching listener rules and their priority

resource "aws_lb" "load_balancer" {
  name               = "marketmate-app-lb"
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_subnet_1a.id, aws_subnet.public_subnet_1b.id]
  security_groups    = [aws_security_group.load_balancer_sg.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = 80
  protocol          = "HTTP"
  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_lb_listener_rule" "instances" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100
  condition {
    path_pattern {
      values = ["*"]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_app_tg.arn
  }
}

# block list part 1
resource "aws_lb_listener_rule" "block_list_1" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  condition {
    path_pattern {
      values = ["*.php", "/vendor/*", "/.env*", "/.git*", "/wp-admin*"]
    }
  }
}

# block list part 2
resource "aws_lb_listener_rule" "block_list_2" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 2

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  condition {
    path_pattern {
      values = ["/wp-login*", "/config.php*", "/cgi-bin/*", "/.aws/*", "/.ssh/*"]
    }
  }
}

resource "aws_lb_target_group" "web_app_tg" {
  name     = "marketmate-app-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.marketmate_vpc.id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 60
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group_attachment" "docker_host_1" {
  target_group_arn = aws_lb_target_group.web_app_tg.arn
  target_id        = aws_instance.docker_host_1.id
  port             = 5000
}

resource "aws_lb_target_group_attachment" "docker_host_2" {
  target_group_arn = aws_lb_target_group.web_app_tg.arn
  target_id        = aws_instance.docker_host_2.id
  port             = 5000
}

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

# ecr repository
resource "aws_ecr_repository" "marketmate_repo" {
  name                 = "marketmate-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# keep only the last 5 images
resource "aws_ecr_lifecycle_policy" "cleanup" {
  repository = aws_ecr_repository.marketmate_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# create iam role for the instances for S3 Read/Write
resource "aws_iam_policy" "s3_avatar_policy" {
  name = "marketmate-s3-avatar-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.avatars.arn}",
          "${aws_s3_bucket.avatars.arn}/*"
        ]
      }
    ]
  })
}

# attach S3 Read/Write policy to the  
resource "aws_iam_role_policy_attachment" "s3_access_attachment" {
  role       = aws_iam_role.docker_host_role.name
  policy_arn = aws_iam_policy.s3_avatar_policy.arn
}

# create iam role for the instances to fetch the container from ecr
resource "aws_iam_role" "docker_host_role" {
  name = "marketmate-ec2-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# attach the standard ReadOnly policy
resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.docker_host_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# attach the SSM managed core policy for ssh access
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.docker_host_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# create the instance profile 
resource "aws_iam_instance_profile" "docker_host_profile" {
  name = "marketmate-ec2-profile"
  role = aws_iam_role.docker_host_role.name
  
}
