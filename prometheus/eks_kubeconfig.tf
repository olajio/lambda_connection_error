# us-east-2
data "aws_ssm_parameter" "kubeconfig" {
  name = local.eks_outputs.kubeconfig_parameter_name
}

resource "local_file" "kubeconfig" {
  filename = "kubeconfig"
  sensitive_content = data.aws_ssm_parameter.kubeconfig.value
}

# us-east-1
data "aws_ssm_parameter" "kubeconfig_virginia" {
  provider = aws.dr
  name = local.eks_outputs.kubeconfig_parameter_name_virginia
}

resource "local_file" "kubeconfig_virginia" {
  filename = "kubeconfig_virginia"
  sensitive_content = data.aws_ssm_parameter.kubeconfig_virginia.value
}