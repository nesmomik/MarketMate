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
