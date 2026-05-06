data "aws_region" "current" {}

data "aws_region" "current_virginia" {
  provider = aws.dr
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "available" {
  cidr_block = data.terraform_remote_state.lz_avm_account.outputs.blueprint["vpc_cidr"]
}

data "aws_vpc" "available_virginia" {
  provider   = aws.dr
  cidr_block = data.terraform_remote_state.lz_avm_account.outputs.blueprint["vpc_cidr_virginia"]
}

data "aws_subnet" "backend_a" {
  vpc_id     = data.aws_vpc.available.id
  cidr_block = local.subnet_backend_a
}

data "aws_subnet" "backend_b" {
  vpc_id     = data.aws_vpc.available.id
  cidr_block = local.subnet_backend_b
}

data "aws_subnet" "backend_c" {
  vpc_id     = data.aws_vpc.available.id
  cidr_block = local.subnet_backend_c
}

data "aws_subnet" "backend_a_virginia" {
  provider   = aws.dr
  vpc_id     = data.aws_vpc.available_virginia.id
  cidr_block = local.subnet_backend_a_virginia
}

data "aws_subnet" "backend_b_virginia" {
  provider   = aws.dr
  vpc_id     = data.aws_vpc.available_virginia.id
  cidr_block = local.subnet_backend_b_virginia
}

data "aws_subnet" "backend_c_virginia" {
  provider   = aws.dr
  vpc_id     = data.aws_vpc.available_virginia.id
  cidr_block = local.subnet_backend_c_virginia
}

data "aws_subnet" "public_a" {
  vpc_id     = data.aws_vpc.available.id
  cidr_block = local.subnet_public_a
}

data "aws_subnet" "public_b" {
  vpc_id     = data.aws_vpc.available.id
  cidr_block = local.subnet_public_b
}

data "aws_subnet" "public_c" {
  vpc_id     = data.aws_vpc.available.id
  cidr_block = local.subnet_public_c
}

data "aws_subnet" "public_a_virginia" {
  provider   = aws.dr
  vpc_id     = data.aws_vpc.available_virginia.id
  cidr_block = local.subnet_public_a_virginia
}

data "aws_subnet" "public_b_virginia" {
  provider   = aws.dr
  vpc_id     = data.aws_vpc.available_virginia.id
  cidr_block = local.subnet_public_b_virginia
}

data "aws_subnet" "public_c_virginia" {
  provider   = aws.dr
  vpc_id     = data.aws_vpc.available_virginia.id
  cidr_block = local.subnet_public_c_virginia
}

data "terraform_remote_state" "shared_common_infra" {
  backend = "s3"
  config = {
    bucket = "hedgeserv-shd-lz-us-east-2-s3-tf-state"
    key    = "core/shd/infra/image_factories/common_infra/terraform.tfstate"
    region = "us-east-2"
  }
}

data "aws_eks_cluster" "eks_cluster" {
  name = local.cluster_name
}

data "aws_eks_cluster" "eks_cluster_virginia" {
  provider = aws.dr
  name     = local.cluster_name_virginia
}

data "aws_s3_bucket_object" "app_codes" {
  bucket = data.terraform_remote_state.shared_common_infra.outputs.config_bucket_name
  key    = "devops/config/server_build/app_codes.yaml"
}

data "aws_s3_bucket_object" "scrapper_config" {
  bucket = data.terraform_remote_state.shared_common_infra.outputs.config_bucket_name
  key    = "configs/${local.environment}/eks/eks_scrapper.yaml"
}

data "aws_s3_bucket_object" "prometheus_alert_manager" {
  bucket = data.terraform_remote_state.shared_common_infra.outputs.config_bucket_name
  key    = "configs/${local.environment}/monitoring/prometheus_alert_manager.yaml"
}

data "aws_s3_bucket_object" "prometheus_k8s_alert_rules" {
  bucket = data.terraform_remote_state.shared_common_infra.outputs.config_bucket_name
  key    = "configs/${local.environment}/monitoring/prometheus_alert_rules/k8s_alert_rules.yaml"
}

data "aws_s3_bucket_object" "prometheus_links_metadata_ohio" {
  bucket = data.terraform_remote_state.shared_common_infra.outputs.config_bucket_name
  key    = "configs/${local.environment}/monitoring/prometheus_metadata_rules/external_links_metadata_ohio.yaml"
}

data "aws_s3_bucket_object" "prometheus_links_metadata_virginia" {
  bucket = data.terraform_remote_state.shared_common_infra.outputs.config_bucket_name
  key    = "configs/${local.environment}/monitoring/prometheus_metadata_rules/external_links_metadata_virginia.yaml"
}

data "aws_s3_bucket_object" "prometheus_test_alert_rules" {
  bucket = data.terraform_remote_state.shared_common_infra.outputs.config_bucket_name
  key    = "configs/${local.environment}/monitoring/prometheus_alert_rules/prometheus_alert_test.yaml"
}

data "aws_s3_bucket_object" "aws_otel_collector" {
  count  = local.environment == "rnd" ? 1 : 0
  bucket = data.terraform_remote_state.shared_common_infra.outputs.config_bucket_name
  key    = "configs/${local.environment}/monitoring/aws_otel_collector.yaml"
}