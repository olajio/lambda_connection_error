output "iam_role_prometheus-grafana-shd-crossaccount" {
  value = aws_iam_role.prometheus_crossaccount_assume_role.arn
}

# us-east-2
output "prometheus_ws_id" {
  value = aws_prometheus_workspace.eks_workspace.id
}

# us-east-1
output "prometheus_ws_id_virginia" {
  value = aws_prometheus_workspace.eks_workspace_virginia.id
}
