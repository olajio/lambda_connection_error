# us-east-2
# K8S metrics ingestion with aws otel
# Role for the aws otel collector
resource "aws_iam_role" "aws_otel_collector_role" {
  count              = local.environment == "rnd" ? 1 : 0
  name               = "${local.aws_otel_collector_name}"
  assume_role_policy = templatefile("policies/aws_otel_collector_assume_role_policy.json", {account_id=local.account_id,oidc_endpoint=trimprefix(local.eks_outputs.oidc_url_ohio, "https://"),aws_otel_collector_service_account_name=local.aws_otel_collector_name,namespace=local.aws_otel_collector_namespace})
  description        = "AWS IAM role for the AWS OTEL collector."
}

resource "aws_iam_policy" "aws_otel_collector_iam_policy" {
  count  = local.environment == "rnd" ? 1 : 0
  name   = "${local.aws_otel_collector_name}"
  policy = templatefile("policies/aws_otel_collector_policy.json", {account_id=local.account_id})
}

resource "aws_iam_role_policy_attachment" "aws_otel_collector_role_attach_policy" {
    count      = local.environment == "rnd" ? 1 : 0
    policy_arn = aws_iam_policy.aws_otel_collector_iam_policy[0].arn
    role       = aws_iam_role.aws_otel_collector_role[0].name
}

data "template_file" "aws_otel_collector" {
  count    = local.environment == "rnd" ? 1 : 0
  template = data.aws_s3_bucket_object.aws_otel_collector[0].body
  vars = {
    app_name             = local.aws_otel_collector_name
    namespace            = local.aws_otel_collector_namespace
    aws_region           = local.region
    workspace_id         = aws_prometheus_workspace.eks_workspace.id
    image                = local.aws_otel_collector_image
    role                 = "arn:aws:iam::${local.account_id}:role/${local.aws_otel_collector_name}"
  }
}

resource "local_file" "aws_otel_collector" {
  count    = local.environment == "rnd" ? 1 : 0
  content  = data.template_file.aws_otel_collector[0].rendered
  filename = "aws_otel_collector.yaml"
}


resource "null_resource" "kubectl_apply_aws_otel_collector" {
  count      = local.environment == "rnd" ? 1 : 0
  depends_on = [local_file.aws_otel_collector[0]]
  triggers = {
    always_apply         = sha1(timestamp())
  }

  provisioner "local-exec" {
    command = <<-COMMANDS
        export KUBECONFIG=${local_file.kubeconfig.filename}
        if test -f "./aws_otel_collector.yaml" ; then kubectl apply -f ./aws_otel_collector.yaml; else echo "file aws_otel_collector.yaml does not exist! Skipping..."; fi;
    COMMANDS
  }
}

# us-east-1
# K8S metrics ingestion with aws otel
# Role for the aws otel collector in virginia
resource "aws_iam_role" "aws_otel_collector_role_virginia" {
  count              = local.environment == "rnd" ? 1 : 0
  name               = "${local.aws_otel_collector_name}-virginia"
  assume_role_policy = templatefile("policies/aws_otel_collector_assume_role_policy.json", {account_id=local.account_id,oidc_endpoint=trimprefix(local.eks_outputs.oidc_url_virginia, "https://"),aws_otel_collector_service_account_name=local.aws_otel_collector_name,namespace=local.aws_otel_collector_namespace})
  description        = "AWS IAM role for the AWS OTEL collector."
}

resource "aws_iam_policy" "aws_otel_collector_iam_policy_virginia" {
  count  = local.environment == "rnd" ? 1 : 0
  name   = "${local.aws_otel_collector_name}-virginia"
  policy = templatefile("policies/aws_otel_collector_policy.json", {account_id=local.account_id})
}

resource "aws_iam_role_policy_attachment" "aws_otel_collector_role_attach_policy_virginia" {
    count      = local.environment == "rnd" ? 1 : 0
    policy_arn = aws_iam_policy.aws_otel_collector_iam_policy_virginia[0].arn
    role       = aws_iam_role.aws_otel_collector_role_virginia[0].name
}

data "template_file" "aws_otel_collector_virginia" {
  count    = local.environment == "rnd" ? 1 : 0
  template = data.aws_s3_bucket_object.aws_otel_collector[0].body
  vars = {
    app_name             = local.aws_otel_collector_name
    namespace            = local.aws_otel_collector_namespace
    aws_region           = local.region_virginia
    workspace_id         = aws_prometheus_workspace.eks_workspace_virginia.id
    image                = local.aws_otel_collector_image_virginia
    role                 = "arn:aws:iam::${local.account_id}:role/${local.aws_otel_collector_name}-virginia"
  }
}

resource "local_file" "aws_otel_collector_virginia" {
  count    = local.environment == "rnd" ? 1 : 0
  content  = data.template_file.aws_otel_collector_virginia[0].rendered
  filename = "aws_otel_collector_virginia.yaml"
}

resource "null_resource" "kubectl_apply_aws_otel_collector_virginia" {
  count      = local.environment == "rnd" ? 1 : 0
  depends_on = [local_file.aws_otel_collector_virginia[0]]
  triggers = {
    always_apply         = sha1(timestamp())
  }

  provisioner "local-exec" {
    command = <<-COMMANDS
        set -ex
        export KUBECONFIG=${local_file.kubeconfig_virginia.filename}
        kubectl version
        if test -f "./aws_otel_collector_virginia.yaml" ; then kubectl apply -f ./aws_otel_collector_virginia.yaml; else echo "file aws_otel_collector_virginia.yaml does not exist! Skipping..."; fi;
    COMMANDS
  }
}
