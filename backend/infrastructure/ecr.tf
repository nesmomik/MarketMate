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
