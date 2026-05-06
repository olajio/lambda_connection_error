# Lambda to ingest the alerts in Elastic
data "aws_iam_policy_document" "prometheus_alert_lambda_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "prometheus_alert_lambda_role" {
  name               = "${local.naming_prefix}-mon-prometheus-alert-lambda"
  assume_role_policy = data.aws_iam_policy_document.prometheus_alert_lambda_policy.json
}

data "template_file" "prometheus_alert_lambda_secretsmanager_policy" {
  template = file("policies/prometheus_alert_lambda_policy.json")
  vars     = {
    account_id = local.account_id
  }
}

resource "aws_iam_policy" "prometheus_alert_lambda_secretsmanager_policy" {
  name        = "${local.sa_iam_role_name}_prometheus-alert-lambda-policy-${random_id.policy.dec}"
  description = "Permissions that are required by the lambda for secret retrieval."
  policy      = data.template_file.prometheus_alert_lambda_secretsmanager_policy.rendered
}

resource "aws_iam_role_policy_attachment" "prometheus_alert_lambda_role_attach_policy" {
  policy_arn = aws_iam_policy.prometheus_alert_lambda_secretsmanager_policy.arn
  role       = aws_iam_role.prometheus_alert_lambda_role.name
}

# us-east-2
resource "aws_lambda_permission" "prometheus_alert_lambda_with_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.prometheus_alert_lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.prometheus_alerts_sns_topic.arn
}

resource "aws_sns_topic_subscription" "prometheus_alert_lambda" {
  topic_arn = aws_sns_topic.prometheus_alerts_sns_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.prometheus_alert_lambda.arn
}


resource "aws_lambda_function" "prometheus_alert_lambda" {
  image_uri        = local.prometheus_alert_image_ohio
  function_name    = "${local.naming_prefix}-mon-prometheus_alert_lambda"
  package_type     = "Image"
  role             = aws_iam_role.prometheus_alert_lambda_role.arn
  timeout          = 10

  image_config {
    command = ["prometheus_alert_lambda.lambda_handler"]
  }

  vpc_config {
    subnet_ids         = [data.aws_subnet.backend_a.id, data.aws_subnet.backend_b.id, data.aws_subnet.backend_c.id]
    security_group_ids = [aws_security_group.prometheus_alert.id]
  }

  environment {
    variables = {
      ELK_INDEX             = "mt-alerts"
      CLOUD_ACCOUNT_REGION  = local.region
      CLOUD_ACCOUNT_ID      = local.account_id
      CLOUD_ACCOUNT_NAME    = local.full_account_name["${local.environment}"]
      ELK_SECRET_NAME       = "elastic/prometheus/api_key"
      NOTIFY_EMAILS         = "monalytics_services@hedgeserv.com"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.prometheus_alert_lambda_logs,
    aws_cloudwatch_log_group.prometheus_alert_lambda_log_group,
  ]

  tags = {
    "Name"                      = "${local.naming_prefix}-mon-prometheus_alert_lambda",
    "Env"                       = local.environment,
    "Region"                    = local.region,
    "hs:std:app-code"           = "PROM",
    "hs:std:app-name"           = "Prometheus_alerting",
    "hs:std:description"        = "prometheus alerting lambda",
    "hs:std:svc-operator"       = "ITSMA",
    "hs:std:svc-software-owner" = "ITSMA"
  }
}

resource "aws_cloudwatch_log_group" "prometheus_alert_lambda_log_group" {
  name              = "/aws/lambda/${local.naming_prefix}-mon-prometheus_alert_lambda"
  retention_in_days = 14
}

data "aws_iam_policy_document" "prometheus_alert_lambda_logging" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_policy" "prometheus_alert_lambda_logging" {
  name        = "${local.naming_prefix}-mon-prometheus_alert_lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a prometheus alert lambda"
  policy      = data.aws_iam_policy_document.prometheus_alert_lambda_logging.json
}

resource "aws_iam_role_policy_attachment" "prometheus_alert_lambda_logs" {
  role       = aws_iam_role.prometheus_alert_lambda_role.name
  policy_arn = aws_iam_policy.prometheus_alert_lambda_logging.arn
}

resource "aws_security_group" "prometheus_alert" {
  name        = "${local.naming_prefix}-mon-prometheus-alert-sg"
  description = "Allow access to the internet in order to send logs to elastic"
  vpc_id      = local.vpc_id
}

resource "aws_security_group_rule" "prometheus_alert" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.prometheus_alert.id
}

# us-east-1
resource "aws_lambda_permission" "prometheus_alert_lambda_with_sns_virginia" {
  provider      = aws.dr
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.prometheus_alert_lambda_virginia.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.prometheus_alerts_sns_topic_virginia.arn
}

resource "aws_sns_topic_subscription" "prometheus_alert_lambda_virginia" {
  provider  = aws.dr
  topic_arn = aws_sns_topic.prometheus_alerts_sns_topic_virginia.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.prometheus_alert_lambda_virginia.arn
}

resource "aws_lambda_function" "prometheus_alert_lambda_virginia" {
  provider         = aws.dr
  image_uri        = local.prometheus_alert_image_virginia
  function_name    = "${local.naming_prefix_virginia}-mon-prometheus_alert_lambda"
  package_type     = "Image"
  role             = aws_iam_role.prometheus_alert_lambda_role.arn
  timeout          = 10

  image_config {
    command = ["prometheus_alert_lambda.lambda_handler"]
  }

  vpc_config {
    subnet_ids         = [data.aws_subnet.backend_a_virginia.id, data.aws_subnet.backend_b_virginia.id, data.aws_subnet.backend_c_virginia.id]
    security_group_ids = [aws_security_group.prometheus_alert_virginia.id]
  }

  environment {
    variables = {
      ELK_INDEX             = "mt-alerts"
      CLOUD_ACCOUNT_REGION  = local.region_virginia
      CLOUD_ACCOUNT_ID      = local.account_id
      CLOUD_ACCOUNT_NAME    = local.full_account_name["${local.environment}"]
      ELK_SECRET_NAME       = "elastic/prometheus/api_key"
      NOTIFY_EMAILS         = "monalytics_services@hedgeserv.com"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.prometheus_alert_lambda_logs,
    aws_cloudwatch_log_group.prometheus_alert_lambda_log_group_virginia,
  ]

  tags = {
    "Name"                      = "${local.naming_prefix_virginia}-mon-prometheus_alert_lambda",
    "Env"                       = local.environment,
    "Region"                    = local.region_virginia,
    "hs:std:app-code"           = "PROM",
    "hs:std:app-name"           = "Prometheus_alerting",
    "hs:std:description"        = "prometheus alerting lambda",
    "hs:std:svc-operator"       = "ITSMA",
    "hs:std:svc-software-owner" = "ITSMA"
  }
}

resource "aws_cloudwatch_log_group" "prometheus_alert_lambda_log_group_virginia" {
  provider          = aws.dr
  name              = "/aws/lambda/${local.naming_prefix_virginia}-mon-prometheus_alert_lambda"
  retention_in_days = 14
}

resource "aws_security_group" "prometheus_alert_virginia" {
  provider    = aws.dr
  name        = "${local.naming_prefix_virginia}-mon-prometheus-alert-sg"
  description = "Allow access to the internet in order to send logs to elastic"
  vpc_id      = local.vpc_id_virginia
}

resource "aws_security_group_rule" "prometheus_alert_virginia" {
  provider          = aws.dr
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.prometheus_alert_virginia.id
}
