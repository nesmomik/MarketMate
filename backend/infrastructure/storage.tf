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
