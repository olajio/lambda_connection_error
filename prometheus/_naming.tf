locals {
  naming_prefix_generated               = "${local.ou}-${local.environment}-${local.component}-${local.region}"
  naming_prefix_generated_virginia            = "${local.ou}-${local.environment}-${local.component}-${local.region_virginia}"
  naming_prefix                               = coalesce(var.naming_prefix, local.naming_prefix_generated)
  naming_prefix_virginia                      = coalesce(var.naming_prefix_virginia, local.naming_prefix_generated_virginia)
  service_linked_role_sufix_name        = "prometheus"
  kms_grant_policy_name                 = "${local.naming_prefix}-prometheus-kms-grant"
  kms_grant_name                        = "${local.naming_prefix}-prometheus-grant"
  kms_key_name                          = "${local.naming_prefix}-prometheus-kms-key"
  prometheus_access_policy_name         = "${local.naming_prefix}-prometheus-iam-policy"
  prometheus_iam_role_name              = "${local.naming_prefix}-prometheus-iam-role"
  prometheus_sg_name                    = "${local.naming_prefix}-sg-prometheus"
  prometheus_release_group              = "prometheus"
  sa_iam_role_name                      = "eks-sa-role"
}
