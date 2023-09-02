terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  alias  = "primary"
  region = var.primary_aws_region
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_aws_region
}

### Primary ###

module "kms_primary" {
  source = "./kms"
  affix  = "primary"

  providers = {
    aws = aws.primary
  }
}

module "s3_primary" {
  source      = "./s3"
  affix       = "primary"
  kms_key_arn = module.kms_primary.kms_key_arn

  providers = {
    aws = aws.primary
  }
}

### Secondary ###

module "kms_secondary" {
  source = "./kms"
  affix  = "secondary"

  providers = {
    aws = aws.secondary
  }
}

module "s3_secondary" {
  source      = "./s3"
  affix       = "secondary"
  kms_key_arn = module.kms_secondary.kms_key_arn

  providers = {
    aws = aws.secondary
  }
}

### Replication ###

data "aws_iam_policy_document" "assume_role" {
  provider = aws.secondary

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "replication" {
  provider = aws.secondary

  name               = "tf-s3-crossregion-replication"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "replication" {
  provider = aws.secondary

  statement {
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]

    resources = [module.s3_primary.bucket_arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]

    resources = ["${module.s3_primary.bucket_arn}/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]

    resources = ["${module.s3_secondary.bucket_arn}/*"]
  }
}

resource "aws_iam_policy" "replication" {
  provider = aws.secondary

  name   = "tf-policy-s3-crossregion-replication"
  policy = data.aws_iam_policy_document.replication.json
}

resource "aws_iam_role_policy_attachment" "replication" {
  provider = aws.secondary

  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}

resource "aws_s3_bucket_replication_configuration" "replication" {
  provider = aws.primary

  # Must have bucket versioning enabled first
  depends_on = [module.s3_primary]

  role   = aws_iam_role.replication.arn
  bucket = module.s3_primary.bucket_id

  rule {
    id     = "crossregion"
    status = "Enabled"

    destination {
      bucket        = module.s3_secondary.bucket_arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = module.kms_secondary.kms_key_arn
      }

      # Additional replication options
      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }

      metrics {
        event_threshold {
          minutes = 15
        }
        status = "Enabled"
      }
    }

    # Additional replication options
    delete_marker_replication {
      status = "Enabled"
    }
  }
}
