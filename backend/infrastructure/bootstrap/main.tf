# this configuration file bootstraps the remote statefile management
# - creates a versioned and encrypted S3 bucket
# - creates a dynamodb table with on key-value pair

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

# input variables stored in terraform.tfvars
variable "marketmate_db_pass" {
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

## setup S3 for statefile management and avatar storage

# needed for copying of avatar default image
locals {
  project_root = abspath("${path.root}/../..")
}

# resource type: aws_s3_bucket
# local resource name: terraform_state
resource "aws_s3_bucket" "terraform_state" {
  bucket        = "marketmate-tf-state"
  force_destroy = true
}

# this is resource linking vs attributes
# references by the exported attribute from the main resource terraform_state
resource "aws_s3_bucket_versioning" "terraform_bucket_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# resource linking to terraform_state
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_crypto_conf" {
  bucket = aws_s3_bucket.terraform_state.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
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

## lockfile stored in dynamodb table

# terraform backend looks for LockID of type string
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-state-locking"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

## create ecr repository for app images
resource "aws_ecr_repository" "marketmate_repo" {
  name                 = "marketmate-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = false

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


