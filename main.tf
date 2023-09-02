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


### Secondary ###

module "secondary" {
  source = "./kms"
  affix  = "secondary"

  providers = {
    aws = aws.secondary
  }
}

### Primary ###

module "primary" {
  source = "./kms"
  affix  = "primary"

  providers = {
    aws = aws.primary
  }
}

