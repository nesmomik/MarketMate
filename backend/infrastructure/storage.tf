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
