provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "dr"
  region = "us-east-1"
}

provider "aws" {
  alias  = "shd"
  region = var.region
  assume_role {
    role_arn     = local.shd_codebuild_role_arn
  }
}

provider "aws" {
  alias  = "shd_dr"
  region = var.region_virginia
  assume_role {
    role_arn     = local.shd_codebuild_role_arn
  }
}
