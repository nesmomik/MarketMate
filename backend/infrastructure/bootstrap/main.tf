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

# ecr repository
resource "aws_ecr_repository" "marketmate_repo" {
  name                 = "marketmate-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# keep only the last 4 images
resource "aws_ecr_lifecycle_policy" "cleanup" {
  repository = aws_ecr_repository.marketmate_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 0
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 4
      }
      action = {
        type = "expire"
      }
    }]
  })
}
