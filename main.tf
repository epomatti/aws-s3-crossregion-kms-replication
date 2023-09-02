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
  provider = aws.primary

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
  provider = aws.primary

  name               = "tf-s3-crossregion-replication"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "replication" {
  provider = aws.primary

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

  statement {
    effect = "Allow"

    actions = [
      "kms:*",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "replication" {
  provider = aws.primary

  name   = "tf-policy-s3-crossregion-replication"
  policy = data.aws_iam_policy_document.replication.json
}

resource "aws_iam_role_policy_attachment" "replication" {
  provider = aws.primary

  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}

locals {
  replication_filter_prefix = "replicate/"
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

    filter {
      prefix = local.replication_filter_prefix
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

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

### Notification ###

data "aws_iam_policy_document" "topic" {
  provider = aws.primary
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = ["arn:aws:sns:*:*:s3-event-notification-topic"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [module.s3_primary.bucket_arn]
    }
  }
}

resource "aws_sns_topic" "topic" {
  provider = aws.primary
  name     = "s3-event-notification-topic"
  policy   = data.aws_iam_policy_document.topic.json
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  provider = aws.primary
  bucket   = module.s3_primary.bucket_id

  topic {
    topic_arn     = aws_sns_topic.topic.arn
    events        = ["s3:Replication:*"]
    filter_prefix = local.replication_filter_prefix
  }
}

resource "aws_sns_topic_subscription" "user_updates_sqs_target" {
  provider  = aws.primary
  topic_arn = aws_sns_topic.topic.arn
  protocol  = "email"
  endpoint  = var.sns_notification_email
}
