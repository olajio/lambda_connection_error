locals {
  account_name = [for account in local.lz_avm_outputs.accounts : account["account_name"] if account["account_id"] == local.account_id][0]
}

// context variables, can be overridden during module implementation
locals {
  app_ou_id                           = local.lz_accounts_outputs.ou_id_app
  poc_ou_id                           = local.lz_accounts_outputs.ou_id_poc
  root_id                             = local.lz_accounts_outputs.root_id
  region                              = coalesce(var.region, data.aws_region.current.name)
  region_virginia                     = coalesce(var.region_virginia, data.aws_region.current_virginia.name)
  org_account_id                      = data.aws_organizations_organization.current.master_account_id
  s3_access_logs_bucket               = local.lz_avm_account_outputs["blueprint"]["bootstrap"]["access_s3_bucket_name"]
  s3_access_logs_bucket_virginia      = local.lz_avm_account_outputs["blueprint"]["bootstrap"]["access_s3_bucket_name_dr"]
  lb_access_logs_bucket_name          = "hedgeserv-${local.environment}-infra-${local.region}-lb-access-logs"
  lb_access_logs_prefix               = "nlb"
}

locals {
  cluster_name                                = "${local.naming_prefix}-eks"
  cluster_name_virginia                       = "${local.naming_prefix_virginia}-eks"
}

locals {
  # us-east-1
  vpc_id_virginia               = data.aws_vpc.available_virginia.id
  subnet_backend_a_virginia     = local.lz_avm_account_outputs["blueprint"]["subnet_backend_a_virginia"]
  subnet_backend_b_virginia     = local.lz_avm_account_outputs["blueprint"]["subnet_backend_b_virginia"]
  subnet_backend_c_virginia     = local.lz_avm_account_outputs["blueprint"]["subnet_backend_c_virginia"]
  subnet_public_a_virginia      = local.lz_avm_account_outputs["blueprint"]["subnet_public_a_virginia"]
  subnet_public_b_virginia      = local.lz_avm_account_outputs["blueprint"]["subnet_public_b_virginia"]
  subnet_public_c_virginia      = local.lz_avm_account_outputs["blueprint"]["subnet_public_c_virginia"]
  subnet_ids_virginia           = [
    data.aws_subnet.backend_a_virginia.id,
    data.aws_subnet.backend_b_virginia.id,
    data.aws_subnet.backend_c_virginia.id]
  public_subnet_ids_virginia    = [
    data.aws_subnet.public_a_virginia.id,
    data.aws_subnet.public_b_virginia.id,
    data.aws_subnet.public_c_virginia.id]
  subnet_ids_public_virginia     = "${data.aws_subnet.public_a_virginia.id}, ${data.aws_subnet.public_b_virginia.id}, ${data.aws_subnet.public_c_virginia.id}"
  subnet_ids_non_public_virginia = "${data.aws_subnet.backend_a_virginia.id}, ${data.aws_subnet.backend_b_virginia.id}, ${data.aws_subnet.backend_c_virginia.id}"
  artifacts_s3_kms_arn_virginia  = "arn:aws:kms:${var.region_virginia}:${data.aws_caller_identity.current.account_id}:key/${local.artifacts_s3_kms_id}"

  # us-east-2
  vpc_id                = data.aws_vpc.available.id
  subnet_backend_a      = local.lz_avm_account_outputs["blueprint"]["subnet_backend_a"]
  subnet_backend_b      = local.lz_avm_account_outputs["blueprint"]["subnet_backend_b"]
  subnet_backend_c      = local.lz_avm_account_outputs["blueprint"]["subnet_backend_c"]
  subnet_public_a       = local.lz_avm_account_outputs["blueprint"]["subnet_public_a"]
  subnet_public_b       = local.lz_avm_account_outputs["blueprint"]["subnet_public_b"]
  subnet_public_c       = local.lz_avm_account_outputs["blueprint"]["subnet_public_c"]
  subnet_ids            = [
    data.aws_subnet.backend_a.id,
    data.aws_subnet.backend_b.id,
    data.aws_subnet.backend_c.id]
  public_subnet_ids     = [
    data.aws_subnet.public_a.id,
    data.aws_subnet.public_b.id,
    data.aws_subnet.public_c.id]
  subnet_ids_public     = "${data.aws_subnet.public_a.id}, ${data.aws_subnet.public_b.id}, ${data.aws_subnet.public_c.id}"
  subnet_ids_non_public = "${data.aws_subnet.backend_a.id}, ${data.aws_subnet.backend_b.id}, ${data.aws_subnet.backend_c.id}"
  subnet_cidrs          = "${data.aws_subnet.backend_a.cidr_block},${data.aws_subnet.backend_b.cidr_block}"
  artifacts_s3_kms_arn  = "arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:key/${local.artifacts_s3_kms_id}"

  artifacts_s3_name     = local.lz_avm_account_outputs["blueprint"]["artifacts_s3_bucket_name"]
  artifacts_s3_kms_id   = local.lz_avm_account_outputs["blueprint"]["artifacts_s3_kms_key_id"]
  state_s3_name         = local.lz_avm_account_outputs["blueprint"]["state_s3_bucket_name"]
  state_s3_kmsid        = local.lz_avm_account_outputs["blueprint"]["state_s3_kms_key_id"]
  codepipeline_role_arn = local.lz_avm_account_outputs["blueprint"]["codepipeline_role_arn"]
  codepipeline_role_id  = local.lz_avm_account_outputs["blueprint"]["codepipeline_role_id"]
  codepipeline_role_name = local.lz_avm_account_outputs["blueprint"]["codepipeline_role_name"]
  codebuild_role_id     = local.lz_avm_account_outputs["blueprint"]["codebuild_role_id"]
  repo_name             = local.lz_avm_account_outputs["blueprint"]["repo_name"]
  repo_owner            = local.lz_avm_account_outputs["blueprint"]["repo_owner"]
  repo_branch           = local.lz_avm_account_outputs["blueprint"]["repo_branch"]
  hosted_zone           = "${local.ou}-${local.environment}.pantheon.hedgeservx.com"
  shared_account_id     = local.lz_accounts_outputs.account_id_core_shared
  ci_codebuild_arn      = "arn:aws:iam::${local.shared_account_id}:role/${local.codebuild_role_name}"
  app_bucket_arn        = local.prepreq_outputs.application_bucket.bucket_arn
  spot_datafeed_prefix  = local.prepreq_outputs.spot_s3_datafeed_prefix
  nlb_non_ssl_tg_port   = "31089"
  nlb_ssl_tg_port       = "31090"

  lb_access_logs_bucket_name_virginia = "hedgeserv-${local.environment}-infra-${local.region_virginia}-lb-access-logs"

  shared_managed_grafana_cac_outputs = data.terraform_remote_state.shared_managed_grafana_cac.outputs

  tags = {
    Name                                              = local.cluster_name
    Environment                                       = local.environment
    Component                                         = local.component
    OU                                                = local.ou
  }

  tags_virginia = {
    Name                                                        = local.cluster_name_virginia
    Environment                                                 = local.environment
    Component                                                   = local.component
    OU                                                          = local.ou
  }

  block_device_mapping_ohio = [
    {
      device_name = "/dev/xvda"
      ebs         = {
        delete_on_termination = true
        encrypted             = true
        volume_size           = 100
        volume_type           = "gp3"
        kms_key_id            = local.shared_common_infra_outputs.ami_factory_kms_key_arn
        delete_on_termination = "true"
      }
    }
  ]

  block_device_mapping_virginia = [
    {
      device_name = "/dev/xvda"
      ebs         = {
        delete_on_termination = true
        encrypted             = true
        volume_size           = 100
        volume_type           = "gp3"
        kms_key_id            = local.shared_common_infra_outputs.ami_factory_kms_key_arn_virginia
        delete_on_termination = "true"
      }
    }
  ]

  labels = {
    Environment = local.environment
    Component   = local.component
    OU          = local.ou
  }
}

locals {
  account_id                = coalesce(var.account_id, data.aws_caller_identity.current.account_id)
  ou                        = local.lz_avm_account_outputs["blueprint"]["ou"]
  environment               = local.lz_avm_account_outputs["blueprint"]["environment"]
  component                 = coalesce(var.component, local.lz_avm_account_outputs["blueprint"]["component"])
  shd_codebuild_role_arn    = local.lz_deployment_roles_outputs.shared_codebuild_role_arn
  codebuild_role_arn        = local.lz_avm_account_outputs["blueprint"]["codebuild_role_arn"]
  ou_path                   = jsonencode(formatlist("${local.org_id}/${local.org_root_id}/%s/*", values(local.workload_ou_ids)))
  workload_ou_ids           = local.lz_accounts_outputs.ou_map_workload
  org_id                    = coalesce(var.org_id, data.aws_organizations_organization.current.id)
  codebuild_role_name       = local.lz_avm_account_outputs["blueprint"]["codebuild_role_name"]
  org_root_id               = local.lz_accounts_outputs.root_id
  app_codes                 = data.aws_s3_bucket_object.app_codes.body
  scrapper_config           = data.aws_s3_bucket_object.scrapper_config.body
  app_config_s3_bucket      = "hedgeserv-${local.environment}-infra-${local.region}-s3-hs-caviar-microservices"
}

locals {
   lz_avm_outputs = data.terraform_remote_state.lz_avm.outputs
   shared_common_infra_outputs = data.terraform_remote_state.shared_common_infra.outputs
   lz_avm_account_outputs = data.terraform_remote_state.lz_avm_account.outputs
   lz_deployment_roles_outputs = data.terraform_remote_state.lz_deployment_roles.outputs
   lz_accounts_outputs = data.terraform_remote_state.lz_accounts.outputs
   common_infra_shd_outputs = data.terraform_remote_state.common_infra_shd.outputs
   prepreq_outputs = data.terraform_remote_state.prereq.outputs
   shared_managed_grafana_outputs = data.terraform_remote_state.shared_managed_grafana.outputs
}

locals {
  prometheus_alert_manager     = data.aws_s3_bucket_object.prometheus_alert_manager.body
  prometheus_k8s_alert_rules   = data.aws_s3_bucket_object.prometheus_k8s_alert_rules.body
  prometheus_links_metadata_ohio      = data.aws_s3_bucket_object.prometheus_links_metadata_ohio.body
  prometheus_links_metadata_virginia  = data.aws_s3_bucket_object.prometheus_links_metadata_virginia.body
  prometheus_test_alert_rules  = data.aws_s3_bucket_object.prometheus_test_alert_rules.body
  prometheus_alert_image_ohio     = "469620122115.dkr.ecr.us-east-2.amazonaws.com/core-shd-ci-us-east-2-ecr-monitoring:1.17.2"
  prometheus_alert_image_virginia = "469620122115.dkr.ecr.us-east-1.amazonaws.com/core-shd-ci-us-east-1-ecr-monitoring:1.17.2"
  grafana_endpoint             = coalesce("https://${local.shared_managed_grafana_outputs.grafana_ws_endpoint}", "GrafanaLinkMissing")
  grafana_datasource           = {
    "rnd" = {
      "us-east-1" = coalesce(local.shared_managed_grafana_cac_outputs.data_source_id_rnd_1, "MissingPrometheusDatasource")
      "us-east-2" = coalesce(local.shared_managed_grafana_cac_outputs.data_source_id_rnd_2, "MissingPrometheusDatasource")
    }
    "qa"  = {
      "us-east-1" = coalesce(local.shared_managed_grafana_cac_outputs.data_source_id_qa_1, "MissingPrometheusDatasource")
      "us-east-2" = coalesce(local.shared_managed_grafana_cac_outputs.data_source_id_qa_2, "MissingPrometheusDatasource")
    }
    "uat" = {
      "us-east-1" = coalesce(local.shared_managed_grafana_cac_outputs.data_source_id_uat_1, "MissingPrometheusDatasource")
      "us-east-2" = coalesce(local.shared_managed_grafana_cac_outputs.data_source_id_uat_2, "MissingPrometheusDatasource")
    }
    "tst" = {
      "us-east-1" = coalesce(local.shared_managed_grafana_cac_outputs.data_source_id_tst_1, "MissingPrometheusDatasource")
      "us-east-2" = coalesce(local.shared_managed_grafana_cac_outputs.data_source_id_tst_2, "MissingPrometheusDatasource")
    }
    "prd" = {
      "us-east-1" = coalesce(local.shared_managed_grafana_cac_outputs.data_source_id_prd_1, "MissingPrometheusDatasource")
      "us-east-2" = coalesce(local.shared_managed_grafana_cac_outputs.data_source_id_prd_2, "MissingPrometheusDatasource")
    }
  }
}

locals {
  sdp_connection_arn    = lookup(local.lz_avm_account_outputs["blueprint"], "eventbridge_connection_sdp_arn", "Missing")
  sdp_connection_arn_dr = lookup(local.lz_avm_account_outputs["blueprint"], "eventbridge_connection_sdp_arn_dr", "Missing")
}

locals {
  full_account_name = {
    "rnd" = "hedgeserv-poc-rnd"
    "qa"  = "hedgeserv-app-qa"
    "uat" = "hedgeserv-app-uat"
    "tst" = "hedgeserv-app-tst"
    "prd" = "hedgeserv-app-prd"
  }
}

locals {
  aws_otel_collector_name                 = "aws-otel-col"
  aws_otel_collector_namespace            = "aws-otel-collector"
  aws_otel_collector_image                = "469620122115.dkr.ecr.us-east-2.amazonaws.com/aws-otel-collector:v0.47.0"
  aws_otel_collector_image_virginia       = "469620122115.dkr.ecr.us-east-1.amazonaws.com/aws-otel-collector:v0.47.0"
  eks_outputs                             = data.terraform_remote_state.eks.outputs
}
