terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws]
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  aws_region     = data.aws_region.current.name
  aws_account_id = data.aws_caller_identity.current.account_id
}

resource "aws_kms_alias" "main" {
  name          = "alias/s3replication"
  target_key_id = aws_kms_key.main.id
}

resource "aws_kms_key" "main" {
  description             = "kms-${var.affix}-key"
  deletion_window_in_days = 10
  enable_key_rotation     = true


  # NOTE: Don't know if last statement is required, need to confirm
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          "AWS" : "arn:aws:iam::${local.aws_account_id}:root"
        }
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "S3KMSAllow"
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Resource = "*"
      },
    ]
  })
}
