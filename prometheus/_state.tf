terraform {
  backend "s3" {
    bucket     = "hedgeserv-<ENV>-avm-us-east-2-s3-tf-state"
    key        = "application/infra/prometheus/terraform.tfstate"
    kms_key_id = "alias/hedgeserv-<ENV>-avm-us-east-2-s3-tf-state-kms-key"
    encrypt    = true
    region     = "us-east-2"
  }
}

# Remote state for AVM apply_baseline for current account
data "terraform_remote_state" "lz_avm_account" {
  backend = "s3"
  config = {
    bucket = "hedgeserv-org-tf-us-east-2-s3-state"
    key    = "avm/accounts/${local.account_name}/terraform.tfstate"
    region = "us-east-2"
  }
}

data "terraform_remote_state" "lz_avm" {
  backend = "s3"
  config = {
    bucket = "hedgeserv-org-tf-us-east-2-s3-state"
    key    = "avm/accounts/terraform.tfstate"
    region = "us-east-2"
  }
}

data "terraform_remote_state" "lz_deployment_roles" {
  backend = "s3"
  config = {
    bucket = "hedgeserv-org-tf-us-east-2-s3-state"
    key    = "lz/ou/core/org/solutions/deployment_roles/terraform.tfstate"
    region = "us-east-2"
  }
}

data "terraform_remote_state" "prereq" {
  backend = "s3"
  config = {
    bucket = "hedgeserv-${local.environment}-avm-us-east-2-s3-tf-state"
    key    = "application/infra/prereq/terraform.tfstate"
    region = "us-east-2"
  }
}

data "terraform_remote_state" "common_infra_shd" {
  backend = "s3"
  config = {
    bucket = "hedgeserv-shd-lz-us-east-2-s3-tf-state"
    key    = "core/shd/infra/image_factories/common_infra/terraform.tfstate"
    region = "us-east-2"
  }
}

data "terraform_remote_state" "lz_accounts" {
  backend = "s3"
  config = {
    bucket = "hedgeserv-org-tf-us-east-2-s3-state"
    key    = "lz/ou/core/org/solutions/lz_accounts/terraform.tfstate"
    region = "us-east-2"
  }
}

data "terraform_remote_state" "shared_managed_grafana" {
  backend = "s3"
  config = {
    bucket     = "hedgeserv-shd-lz-us-east-2-s3-tf-state"
    key        = "core/shd/infra/managed_grafana/terraform.tfstate"
    region = "us-east-2"
  }
}

data "terraform_remote_state" "shared_managed_grafana_cac" {
  backend = "s3"
  config = {
    bucket     = "hedgeserv-shd-lz-us-east-2-s3-tf-state"
    key        = "core/shd/infra/managed_grafana_cac/terraform.tfstate"
    region = "us-east-2"
  }
}

data "aws_organizations_organization" "current" {}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "hedgeserv-${local.environment}-avm-us-east-2-s3-tf-state"
    key    = "application/infra/eks/terraform.tfstate"
    region = "us-east-2"
  }
}
