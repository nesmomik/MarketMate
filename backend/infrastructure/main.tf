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

variable "postgres_password" {
  type = string
  # hides the value in console outputs
  sensitive = true
}

variable "jwt_secret_key" {
  type      = string
  sensitive = true
}

variable "app_db_user" {
  type = string
}

variable "app_db_name" {
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
# reference default vpc and subnet
data "aws_vpc" "default_vpc" {
  default = true
}
data "aws_subnets" "default_subnet" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default_vpc.id]
  }
}

# local variables
locals {
  # set project root relative to the location of the main.tf file 
  project_root = abspath("${path.root}/..")
   # chomp removes trailing new lines
  my_public_ip  = chomp(data.http.my_public_ip.response_body)
  ec2_user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
    aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com
    docker pull ${aws_ecr_repository.app_repo.repository_url}:latest
    docker run -d \
      --name marketmate-app \
      -p 5000:5000 \
      -e S3_BUCKET_NAME=marketmate-avatars \
      -e S3_REGION=eu-central-1 \
      -e USE_S3_STORAGE=true \
      -e POSTGRES_USER="${var.app_db_user}" \
      -e POSTGRES_PASSWORD="${var.postgres_password}" \
      -e POSTGRES_DB="${var.app_db_name}" \
      -e POSTGRES_HOST="${aws_db_instance.marketmate_tf_db.address}" \
      -e POSTGRES_PORT="5432" \
      -e JWT_SECRET_KEY="${var.jwt_secret_key}" \
      "${aws_ecr_repository.app_repo.repository_url}:latest"
  EOF
}

# create two ec2 instances
resource "aws_instance" "docker_host_1" {
  ami             = data.aws_ssm_parameter.al2023_latest_kernel.value
  instance_type   = "t3.micro"
  security_groups = [aws_security_group.docker_app_flask_sg.name]
  key_name        = "ec2-user-masterschool"

  # Attach the IAM Profile
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  user_data = local.ec2_user_data
}

resource "aws_instance" "docker_host_2" {
  ami             = data.aws_ssm_parameter.al2023_latest_kernel.value
  instance_type   = "t3.micro"
  security_groups = [aws_security_group.docker_app_flask_sg.name]
  key_name        = "ec2-user-masterschool"

  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  user_data = local.ec2_user_data
}

# create security group for instances
resource "aws_security_group" "docker_app_flask_sg" {
  name        = "marketmate-dev-app-sg"
  description = "Security group for MarketMate dev Docker hosts"
  vpc_id      = data.aws_vpc.default_vpc.id

  # only allow inbound from the load balancer
  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer_sg.id]
  }

  # allow inbound from my ip
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${local.my_public_ip}/32"]

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

resource "aws_db_instance" "marketmate_tf_db" {
  identifier             = "marketmate-tf-db"
  instance_class         = "db.t3.micro"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  snapshot_identifier = "marketmate-tf-db-snapshot-pre-destroy"

  # prevents deletion via console or API
  deletion_protection = false

  # snapshot management
  skip_final_snapshot       = false
  final_snapshot_identifier = "marketmate-db-pre-destroy-snapshot"

  # prevents 'terraform destroy'
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "marketmate-dev-rds-sg"
  description = "Security group for MarketMate dev RDS instance"
  vpc_id      = data.aws_vpc.default_vpc.id

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
    Name        = "marketmate-avatars"
  }
}

resource "aws_s3_object" "logo" {
  bucket = aws_s3_bucket.avatars.id
  key    = "avatars/user_default.png"
  source = "${local.project_root}/avatar/user_default.png"
  # check if file changed
  etag   = filemd5("${local.project_root}/avatar/user_default.png")
}

# set up load balancer
resource "aws_lb" "load_balancer" {
  name               = "web-app-lb"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default_subnet.ids
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
      values = [
        "*.php*",
        "*/vendor/*",
        "*/.env*",
        "*/.git*",
        "/wp-admin*"
      ]
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
      values = [
        "/wp-login*",
        "*/config.php",
        "/cgi-bin/*",
        "*/.aws/*",
        "*/.ssh/*"
      ]
    }
  }
}

resource "aws_lb_listener_rule" "global_block_list" {
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
      values = [
        "*.php*",       
        "*/vendor/*",   
        "*/.env*",      
        "*/.git*",      
        "/wp-admin*",   
        "/wp-login*",   
        "*/config.php", 
        "/cgi-bin/*",   
        "*/.aws/*",     
        "*/.ssh/*"      
      ]
    }
  }
}

resource "aws_lb_target_group" "web_app_tg" {
  name_prefix = "webapp"  
  port     = 5000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default_vpc.id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
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
  name        = "marketmate-dev-lb-sg"
  description = "Security group for MarketMate dev load balancer"
  vpc_id      = data.aws_vpc.default_vpc.id

  # Allow public HTTP (or your demo port)
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

# output for testing
output "alb_dns_name" {
  value = aws_lb.load_balancer.dns_name
}

output "docker_host_1_public_ip" {
  value = aws_instance.docker_host_1.public_ip
}

output "docker_host_2_public_ip" {
  value = aws_instance.docker_host_2.public_ip
}

# ecr repository
resource "aws_ecr_repository" "app_repo" {
  name                 = "marketmate-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# keep only the last 5 images
resource "aws_ecr_lifecycle_policy" "cleanup" {
  repository = aws_ecr_repository.app_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
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
  name        = "marketmate-s3-avatar-policy"
  description = "Allows EC2 instances to read and write avatars"

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

resource "aws_iam_role_policy_attachment" "s3_access_attachment" {
  role       = aws_iam_role.marketmate_app_role.name
  policy_arn = aws_iam_policy.s3_avatar_policy.arn
}

# create iam role for the instances to fetch the container from ecr
resource "aws_iam_role" "marketmate_app_role" {
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
  role       = aws_iam_role.marketmate_app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# attach the SSM managed core policy for ssh access
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.marketmate_app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# create the instance profile 
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "marketmate-ec2-profile"
  role = aws_iam_role.marketmate_app_role.name
}
