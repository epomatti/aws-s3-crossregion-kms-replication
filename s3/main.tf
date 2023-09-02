resource "random_string" "bucket" {
  length    = 3
  min_lower = 3
  special   = false
}

resource "aws_s3_bucket" "main" {
  bucket = "bucket-${var.affix}-${random_string.bucket.result}"

  force_destroy = true
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}
