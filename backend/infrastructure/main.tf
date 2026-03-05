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

# get already existing ecr repository
data "aws_ecr_repository" "marketmate_repo" {
  name = "marketmate-app"
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
