# get account ID, region and 
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# get latest Amazon Linux 2023 image
data "aws_ssm_parameter" "al2023_latest_kernel" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# get already existing ecr repository
data "aws_ecr_repository" "marketmate_repo" {
  name = "marketmate-app"
}

# get already existing s3 bucket 
data "aws_s3_bucket" "avatars" {
  bucket = "marketmate-avatars"
}

# nat instance and jump box to provide 
# internet and ssh access to the docker hosts
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

# local variables for docker hosts
locals {
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
    docker pull ${data.aws_ecr_repository.marketmate_repo.repository_url}:latest
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
      "${data.aws_ecr_repository.marketmate_repo.repository_url}:latest"
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

# attach S3 Read/Write policy to the  
resource "aws_iam_role_policy_attachment" "s3_access_attachment" {
  role       = aws_iam_role.docker_host_role.name
  policy_arn = aws_iam_policy.s3_avatar_policy.arn
}

# create the instance profile 
resource "aws_iam_instance_profile" "docker_host_profile" {
  name = "marketmate-ec2-profile"
  role = aws_iam_role.docker_host_role.name

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
          "${data.aws_s3_bucket.avatars.arn}",
          "${data.aws_s3_bucket.avatars.arn}/*"
        ]
      }
    ]
  })
}


