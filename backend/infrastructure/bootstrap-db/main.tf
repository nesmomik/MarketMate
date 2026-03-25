terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

## handle secrets
variable "marketmate_db_pass" {
  type      = string
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

## create database and seed it with initial test data

# create temporary network for database creation

# get AZs in selected regions
data "aws_availability_zones" "available" { state = "available" }

# create custom vpc
resource "aws_vpc" "bootstrap_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "marketmate-bootstrap-vpc" }
}

# need at least two subnets for db subnet group
resource "aws_subnet" "bootstrap_subnets" {
  # using count creates two instances of this resource
  count  = 2
  vpc_id = aws_vpc.bootstrap_vpc.id
  # generate cidr blocks 
  cidr_block        = cidrsubnet(aws_vpc.bootstrap_vpc.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

# create db subnet group
resource "aws_db_subnet_group" "bootstrap_db_subnet_group" {
  name       = "marketmate-bootstrap-subnet-group"
  subnet_ids = aws_subnet.bootstrap_subnets[*].id
}

# security group to connect lambda and rds
resource "aws_security_group" "db_and_lambda_sg" {
  name   = "bootstrap-db-lambda-sg"
  vpc_id = aws_vpc.bootstrap_vpc.id

  ingress {
    from_port = 5432
    to_port   = 5432
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

## create temporary rds instance to create the snapshot

resource "aws_db_instance" "bootstrap_db" {
  identifier        = "marketmate-bootstrap-db"
  engine            = "postgres"
  engine_version    = "17.6"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  db_name           = var.marketmate_db_name
  username          = var.marketmate_db_user
  password          = var.marketmate_db_pass

  db_subnet_group_name   = aws_db_subnet_group.bootstrap_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_and_lambda_sg.id]

  # create snapshot on 'terraform destroy'
  skip_final_snapshot       = false
  final_snapshot_identifier = "marketmate-seed-snapshot-final"
}

## lambda seeder script setup

# create role to allow 
resource "aws_iam_role" "lambda_exec_role" {
  name = "bootstrap_lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# attach policy to role
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# make script accessible in terraform
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_task/build"
  output_path = "${path.module}/lambda_function.zip"
}

# create lambda runner
resource "aws_lambda_function" "db_seeder" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "bootstrap-db-seeder"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 90

  vpc_config {
    subnet_ids         = aws_subnet.bootstrap_subnets[*].id
    security_group_ids = [aws_security_group.db_and_lambda_sg.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_db_instance.bootstrap_db.address
      APP_DB_NAME = var.marketmate_db_name
      APP_DB_USER = var.marketmate_db_user
      APP_DB_PASS = var.marketmate_db_pass
    }
  }
}

# execute lambda script
resource "aws_lambda_invocation" "run_seeder" {
  function_name = aws_lambda_function.db_seeder.function_name
  input         = jsonencode({ "action" : "seed_database" })

  depends_on = [
    aws_db_instance.bootstrap_db,
    aws_iam_role_policy_attachment.lambda_vpc_access
  ]
}
