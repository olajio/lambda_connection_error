data "template_file" "scrapper_config" {
  template = local.scrapper_config
}

resource "local_file" "scrapper_config" {
  content  = data.template_file.scrapper_config.rendered
  filename = "scrapper_config.yaml"
}

resource "aws_prometheus_scraper" "eks_scrappper" {
  source {
    eks {
      cluster_arn = data.aws_eks_cluster.eks_cluster.arn
      subnet_ids  = local.subnet_ids
    }
  }

  destination {
    amp {
      workspace_arn = aws_prometheus_workspace.eks_workspace.arn
    }
  }

  scrape_configuration = local_file.scrapper_config.content
}

# Prometheus Workspace

resource "aws_cloudwatch_log_group" "eks_workspace_cloudwatch_log_group" {
  name = "${local.cluster_name}-prometheus-workspace"
}

resource "aws_prometheus_workspace" "eks_workspace" {
  alias       = "${local.cluster_name}_workspace"

  logging_configuration {
    log_group_arn = "${aws_cloudwatch_log_group.eks_workspace_cloudwatch_log_group.arn}:*"
  }
}

resource "random_id" "policy" {
  byte_length = 8

  keepers = {
    name_id = local.sa_iam_role_name
  }
}

resource "null_resource" "enable_prometheus_scraper_logs" {
  triggers = {
    always_apply = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command = <<EOT
    scraperId=$(aws amp list-scrapers --query "scrapers[*].scraperId" --output text)
    aws amp update-scraper-logging-configuration \
      --scraper-id "$scraperId" \
      --logging-destination '{"cloudWatchLogs": {"logGroupArn": "${aws_cloudwatch_log_group.eks_workspace_cloudwatch_log_group.arn}:*"}}' \
      --scraper-components '[{"type": "COLLECTOR"}, {"type": "SERVICE_DISCOVERY"}, {"type": "EXPORTER"}]' \
      --region "${local.region}"
    EOT
  }
}

# SNS topic for prometheus alerts
resource "aws_sns_topic" "prometheus_alerts_sns_topic" {
  name          = "${local.cluster_name}-prometheus-alerts-topic"
  display_name  = "${local.cluster_name}-prometheus-alerts-topic"
}

resource "aws_sns_topic_policy" "prometheus_alerts_sns_topic_policy" {
  arn         = aws_sns_topic.prometheus_alerts_sns_topic.arn
  policy      = data.template_file.prometheus_alerts_sns_topic_policy_file.rendered
  depends_on  = [aws_sns_topic.prometheus_alerts_sns_topic]
}

data "template_file" "prometheus_alerts_sns_topic_policy_file" {
  template    = file("policies/prometheus_alerts_sns_topic_policy.json")
  vars        = {
    sns_topic_arn = aws_sns_topic.prometheus_alerts_sns_topic.arn
    account_id    = local.account_id
    workspace_arn = aws_prometheus_workspace.eks_workspace.arn
  }
}

# Alert rules/manager for prometheus
# Rule file for k8s alerts
resource "aws_prometheus_rule_group_namespace" "k8s_alert_rules" {
  name         = "k8s_alert_rules"
  workspace_id = aws_prometheus_workspace.eks_workspace.id
  data         = local_file.k8s_alert_rules.content
}

data "template_file" "k8s_alert_rules" {
  template    = local.prometheus_k8s_alert_rules
  vars        = {
    cloud_account_id     = local.account_id
    cloud_account_region = local.region
    cloud_account_name   = local.full_account_name["${local.environment}"]
    grafana_link         = local.grafana_endpoint
    grafana_datasource   = local.grafana_datasource["${local.environment}"]["${local.region}"]
  }
}

resource "local_file" "k8s_alert_rules" {
  content  = data.template_file.k8s_alert_rules.rendered
  filename = "k8s_alert_rules.yaml"
}

# Rule for cluster metadata used to support external links from panels
resource "aws_prometheus_rule_group_namespace" "links_metadata_ohio" {
  name         = "external_links_metadata"
  workspace_id = aws_prometheus_workspace.eks_workspace.id
  data         = local_file.links_metadata_ohio.content
}

data "template_file" "links_metadata_ohio" {
  template    = local.prometheus_links_metadata_ohio
  vars        = {
    cloud_account_id     = local.account_id
    cloud_account_region = local.region
    cloud_account_name   = local.full_account_name["${local.environment}"]
    grafana_link         = local.grafana_endpoint
    grafana_datasource   = local.grafana_datasource["${local.environment}"]["${local.region}"]
  }
}

resource "local_file" "links_metadata_ohio" {
  content  = data.template_file.links_metadata_ohio.rendered
  filename = "links_metadata_ohio.yaml"
}

# Rule for cluster metadata used to support external links from panels - Virginia
resource "aws_prometheus_rule_group_namespace" "links_metadata_virginia" {
  provider     = aws.dr
  name         = "external_links_metadata"
  workspace_id = aws_prometheus_workspace.eks_workspace_virginia.id
  data         = local_file.links_metadata_virginia.content
}

data "template_file" "links_metadata_virginia" {
  template    = local.prometheus_links_metadata_virginia
  vars        = {
    cloud_account_id     = local.account_id
    cloud_account_region = local.region_virginia
    cloud_account_name   = local.full_account_name["${local.environment}"]
    grafana_link         = local.grafana_endpoint
    grafana_datasource   = local.grafana_datasource["${local.environment}"]["${local.region_virginia}"]
  }
}

resource "local_file" "links_metadata_virginia" {
  content  = data.template_file.links_metadata_virginia.rendered
  filename = "links_metadata_virginia.yaml"
}

# Test alert rule
resource "aws_prometheus_rule_group_namespace" "prometheus_test_alert_rules" {
  name         = "prometheus_test_alert_rules"
  workspace_id = aws_prometheus_workspace.eks_workspace.id
  data         = local_file.prometheus_test_alert_rules.content
}

data "template_file" "prometheus_test_alert_rules" {
  template    = local.prometheus_test_alert_rules
  vars        = {
    cloud_account_id     = local.account_id
    cloud_account_region = local.region
    cloud_account_name   = local.full_account_name["${local.environment}"]
    grafana_link         = local.grafana_endpoint
  }
}

resource "local_file" "prometheus_test_alert_rules" {
  content  = data.template_file.prometheus_test_alert_rules.rendered
  filename = "prometheus_test_alert_rules.yaml"
}

resource "aws_prometheus_alert_manager_definition" "prometheus_alert_manager" {
  workspace_id = aws_prometheus_workspace.eks_workspace.id
  definition   = local_file.prometheus_alert_manager.content
}

data "template_file" "prometheus_alert_manager" {
  template    = local.prometheus_alert_manager
  vars        = {
    sns_topic_arn = aws_sns_topic.prometheus_alerts_sns_topic.arn
  }
}

resource "local_file" "prometheus_alert_manager" {
  content  = data.template_file.prometheus_alert_manager.rendered
  filename = "prometheus_alert_manager.yaml"
}


data "template_file" "managed_grafana_role_policy" {
  template = file("policies/grafana_2_prometheus.json")
}

resource "aws_iam_policy" "managed_grafana_role_policy" {
  name        = "${local.sa_iam_role_name}_managed_grafana-policy-${random_id.policy.dec}"
  description = "Permissions that are required by managed grafana to connect to managed prometheus"
  policy      = data.template_file.managed_grafana_role_policy.rendered
}

# us-east-1

resource "aws_prometheus_scraper" "eks_scrappper_virginia" {
  provider  = aws.dr
  source {
    eks {
      cluster_arn = data.aws_eks_cluster.eks_cluster_virginia.arn
      subnet_ids  = local.subnet_ids_virginia
    }
  }

  destination {
    amp {
      workspace_arn = aws_prometheus_workspace.eks_workspace_virginia.arn
    }
  }

  scrape_configuration = local_file.scrapper_config.content
}

# Prometheus Workspace

resource "aws_cloudwatch_log_group" "eks_workspace_cloudwatch_log_group_virginia" {
  provider  = aws.dr
  name      = "${local.cluster_name_virginia}-prometheus-workspace"
}

resource "aws_prometheus_workspace" "eks_workspace_virginia" {
  provider    = aws.dr
  alias       = "${local.cluster_name_virginia}_workspace"

  logging_configuration {
    log_group_arn = "${aws_cloudwatch_log_group.eks_workspace_cloudwatch_log_group_virginia.arn}:*"
  }
}

resource "null_resource" "enable_prometheus_scraper_logs_virginia" {
  triggers = {
    always_apply = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command = <<EOT
    scraperId=$(aws amp list-scrapers --region "${local.region_virginia}" --query "scrapers[*].scraperId" --output text)
    aws amp update-scraper-logging-configuration \
      --scraper-id "$scraperId" \
      --logging-destination '{"cloudWatchLogs": {"logGroupArn": "${aws_cloudwatch_log_group.eks_workspace_cloudwatch_log_group_virginia.arn}:*"}}' \
      --scraper-components '[{"type": "COLLECTOR"}, {"type": "SERVICE_DISCOVERY"}, {"type": "EXPORTER"}]' \
      --region "${local.region_virginia}"
    EOT
  }
}

# SNS topic for prometheus alerts
resource "aws_sns_topic" "prometheus_alerts_sns_topic_virginia" {
  provider      = aws.dr
  name          = "${local.cluster_name_virginia}-prometheus-alerts-topic"
  display_name  = "${local.cluster_name_virginia}-prometheus-alerts-topic"
}

resource "aws_sns_topic_policy" "prometheus_alerts_sns_topic_policy_virginia" {
  provider    = aws.dr
  arn         = aws_sns_topic.prometheus_alerts_sns_topic_virginia.arn
  policy      = data.template_file.prometheus_alerts_sns_topic_policy_file_virginia.rendered
  depends_on  = [aws_sns_topic.prometheus_alerts_sns_topic_virginia]
}

data "template_file" "prometheus_alerts_sns_topic_policy_file_virginia" {
  template    = file("policies/prometheus_alerts_sns_topic_policy.json")
  vars        = {
    sns_topic_arn = aws_sns_topic.prometheus_alerts_sns_topic_virginia.arn
    account_id    = local.account_id
    workspace_arn = aws_prometheus_workspace.eks_workspace_virginia.arn
  }
}

# Alert rules/manager for prometheus
# Rule file for k8s alerts
resource "aws_prometheus_rule_group_namespace" "k8s_alert_rules_virginia" {
  provider     = aws.dr
  name         = "k8s_alert_rules"
  workspace_id = aws_prometheus_workspace.eks_workspace_virginia.id
  data         = local_file.k8s_alert_rules_virginia.content
}

data "template_file" "k8s_alert_rules_virginia" {
  template    = local.prometheus_k8s_alert_rules
  vars        = {
    cloud_account_id     = local.account_id
    cloud_account_region = local.region_virginia
    cloud_account_name   = local.full_account_name["${local.environment}"]
    grafana_link         = local.grafana_endpoint
    grafana_datasource   = local.grafana_datasource["${local.environment}"]["${local.region_virginia}"]
  }
}

resource "local_file" "k8s_alert_rules_virginia" {
  content  = data.template_file.k8s_alert_rules_virginia.rendered
  filename = "k8s_alert_rules_virginia.yaml"
}

# Test alert rule virginia
resource "aws_prometheus_rule_group_namespace" "prometheus_test_alert_rules_virginia" {
  provider     = aws.dr
  name         = "prometheus_test_alert_rules_virginia"
  workspace_id = aws_prometheus_workspace.eks_workspace_virginia.id
  data         = local_file.prometheus_test_alert_rules_virginia.content
}

data "template_file" "prometheus_test_alert_rules_virginia" {
  template    = local.prometheus_test_alert_rules
  vars        = {
    cloud_account_id     = local.account_id
    cloud_account_region = local.region_virginia
    cloud_account_name   = local.full_account_name["${local.environment}"]
    grafana_link         = local.grafana_endpoint
  }
}

resource "local_file" "prometheus_test_alert_rules_virginia" {
  content  = data.template_file.prometheus_test_alert_rules_virginia.rendered
  filename = "prometheus_test_alert_rules_virginia.yaml"
}

resource "aws_prometheus_alert_manager_definition" "prometheus_alert_manager_virginia" {
  provider     = aws.dr
  workspace_id = aws_prometheus_workspace.eks_workspace_virginia.id
  definition   = local_file.prometheus_alert_manager_virginia.content
}

data "template_file" "prometheus_alert_manager_virginia" {
  template    = local.prometheus_alert_manager
  vars        = {
    sns_topic_arn = aws_sns_topic.prometheus_alerts_sns_topic_virginia.arn
  }
}

resource "local_file" "prometheus_alert_manager_virginia" {
  content  = data.template_file.prometheus_alert_manager_virginia.rendered
  filename = "prometheus_alert_manager_virginia.yaml"
}

# Global IAM role and policy for cross-accounting

resource "aws_iam_role" "prometheus_crossaccount_assume_role" {
  name               = "prometheus-grafana-shd-crossaccount"
  assume_role_policy = templatefile("policies/prometheus_crossaccount.json", {prometheus_workspace=aws_prometheus_workspace.eks_workspace.arn,prometheus_workspace_virginia=aws_prometheus_workspace.eks_workspace_virginia.arn,shd_managed_grafana_role_arn=local.shared_managed_grafana_outputs.grafana_iam_role_arn})
  description        = "AWS IAM role allowing managed grafana in shd to access prometheus in app accounts "
}

resource "aws_iam_role_policy_attachment" "prometheus_crossaccount_attach" {
  policy_arn = aws_iam_policy.managed_grafana_role_policy.arn
  role       = aws_iam_role.prometheus_crossaccount_assume_role.name
}

# Recording rules for node-to-instance mapping (persists EC2 instance ID after node termination)
# IO-41470: Enables correlation of BidEvict events to EKS nodes in Grafana
resource "aws_prometheus_rule_group_namespace" "node_instance_mapping" {
  name         = "node_instance_mapping"
  workspace_id = aws_prometheus_workspace.eks_workspace.id
  data         = <<-EOF
groups:
  - name: node-instance-mapping
    interval: 60s
    rules:
      - record: node:ec2_instance:info
        expr: |
          label_replace(
            kube_node_info,
            "instance_id", "$1", "provider_id", "aws:///.*/(.+)"
          )
EOF
}

resource "aws_prometheus_rule_group_namespace" "node_instance_mapping_virginia" {
  provider     = aws.dr
  name         = "node_instance_mapping"
  workspace_id = aws_prometheus_workspace.eks_workspace_virginia.id
  data         = <<-EOF
groups:
  - name: node-instance-mapping
    interval: 60s
    rules:
      - record: node:ec2_instance:info
        expr: |
          label_replace(
            kube_node_info,
            "instance_id", "$1", "provider_id", "aws:///.*/(.+)"
          )
EOF
}
