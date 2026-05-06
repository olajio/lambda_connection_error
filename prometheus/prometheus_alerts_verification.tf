# Lambda to test the alert queries in Prometheus
data "aws_iam_policy_document" "prometheus_alert_verification_lambda_policy" {
    statement {
        effect = "Allow"

        principals {
        type        = "Service"
        identifiers = ["lambda.amazonaws.com"]
        }

        actions = ["sts:AssumeRole"]
    }
}

resource "aws_iam_role" "prometheus_alert_verification_lambda_role" {
    name               = "${local.naming_prefix}-mon-prometheus-alert-verification-lambda"
    assume_role_policy = data.aws_iam_policy_document.prometheus_alert_verification_lambda_policy.json
}

data "template_file" "prometheus_verification_policy" {
    template = file("policies/prometheus_alert_verification_policy.json")
    vars     = {
        prometheus_workspace_arn = aws_prometheus_workspace.eks_workspace.arn
    }
}

resource "aws_iam_policy" "prometheus_verification_policy" {
    name        = "${local.sa_iam_role_name}_prometheus-verification-policy-${random_id.policy.dec}"
    description = "Permissions that are required by the lambda for querying prometheus."
    policy      = data.template_file.prometheus_verification_policy.rendered
}

resource "aws_iam_role_policy_attachment" "prometheus_alert_verification_role_attach_policy" {
    policy_arn = aws_iam_policy.prometheus_verification_policy.arn
    role       = aws_iam_role.prometheus_alert_verification_lambda_role.name
}

# us-east-2
resource "aws_lambda_function" "prometheus_alert_verification_lambda" {
    image_uri        = local.prometheus_alert_image_ohio
    function_name    = "${local.naming_prefix}-mon-prometheus_alert_verification_lambda"
    package_type     = "Image"
    role             = aws_iam_role.prometheus_alert_verification_lambda_role.arn
    timeout          = 10

    image_config {
      command = ["prometheus_alerts_verification_lambda.lambda_handler"]
    }

    vpc_config {
        subnet_ids         = [data.aws_subnet.backend_a.id, data.aws_subnet.backend_b.id, data.aws_subnet.backend_c.id]
        security_group_ids = [aws_security_group.prometheus_alert.id]
    }

    environment {
        variables = {
            CLOUD_ACCOUNT_REGION  = local.region
            CLOUD_ACCOUNT_ID      = local.account_id
            CLOUD_ACCOUNT_NAME    = local.environment
            NOTIFY_EMAILS         = "monalytics_services@hedgeserv.com"
            PROMETHEUS_ENDPOINT   = aws_prometheus_workspace.eks_workspace.prometheus_endpoint
        }
    }

    depends_on = [
        aws_iam_role_policy_attachment.prometheus_alert_verification_lambda_logs,
        aws_cloudwatch_log_group.prometheus_alert_verification_lambda_log_group,
        aws_prometheus_workspace.eks_workspace,
        aws_security_group.prometheus_alert,
    ]

    tags = {
        "Name"                      = "${local.naming_prefix}-mon-prometheus_alert_verification_lambda",
        "Env"                       = local.environment,
        "Region"                    = local.region,
        "hs:std:app-code"           = "PROM",
        "hs:std:app-name"           = "Prometheus_verification",
        "hs:std:description"        = "Prometheus alert verification lambda",
        "hs:std:svc-operator"       = "ITSMA",
        "hs:std:svc-software-owner" = "ITSMA"
    }
}

resource "aws_cloudwatch_log_group" "prometheus_alert_verification_lambda_log_group" {
    name              = "/aws/lambda/${local.naming_prefix}-mon-prometheus_alert_verification_lambda"
    retention_in_days = 14
}

data "aws_iam_policy_document" "prometheus_alert_verification_lambda_logging" {
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

resource "aws_iam_policy" "prometheus_alert_verification_lambda_logging" {
    name        = "${local.naming_prefix}-mon-prometheus_alert_verification_lambda_logging"
    path        = "/"
    description = "IAM policy for logging from the prometheus alert verification lambda"
    policy      = data.aws_iam_policy_document.prometheus_alert_verification_lambda_logging.json
}

resource "aws_iam_role_policy_attachment" "prometheus_alert_verification_lambda_logs" {
    role       = aws_iam_role.prometheus_alert_verification_lambda_role.name
    policy_arn = aws_iam_policy.prometheus_alert_verification_lambda_logging.arn
}

# Define EventBridge scheduler for the lambda
resource "aws_iam_role" "prometheus_verification_scheduler_role" {
    name               = "${local.naming_prefix}-mon-prometheus-verification-scheduler"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
        {
            Effect = "Allow"
            Principal = {
            Service = ["scheduler.amazonaws.com"]
            }
            Action = "sts:AssumeRole"
        }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "prometheus_verification_scheduler" {
    policy_arn  = aws_iam_policy.prometheus_verification_scheduler_policy.arn
    role        = aws_iam_role.prometheus_verification_scheduler_role.name
}

resource "aws_iam_policy" "prometheus_verification_scheduler_policy" {
    name      = "${local.naming_prefix}-mon-prometheus-verification-scheduler-policy"
    policy    = templatefile("${path.module}/policies/prometheus_verification_scheduler_policy.json", {
        lambda_arn = aws_lambda_function.prometheus_alert_verification_lambda.arn
    })
}

resource "aws_scheduler_schedule" "prometheus_verification_scheduler" {
    name      = "prometheus_verification_scheduler"

    flexible_time_window {
        mode = "OFF"
    }

    schedule_expression = "rate(24 hours)"

    target {
        arn       = aws_lambda_function.prometheus_alert_verification_lambda.arn
        role_arn  = aws_iam_role.prometheus_verification_scheduler_role.arn
    }

    depends_on = [
        aws_lambda_function.prometheus_alert_verification_lambda,
        aws_iam_role.prometheus_verification_scheduler_role,
    ]
}

# us-east-1
data "template_file" "prometheus_verification_policy_virginia" {
    template = file("policies/prometheus_alert_verification_policy.json")
    vars     = {
        prometheus_workspace_arn = aws_prometheus_workspace.eks_workspace_virginia.arn
    }
}

resource "aws_iam_policy" "prometheus_verification_policy_virginia" {
    name        = "${local.sa_iam_role_name}_prometheus-verification-policy-virginia-${random_id.policy.dec}"
    description = "Permissions that are required by the lambda for querying prometheus."
    policy      = data.template_file.prometheus_verification_policy_virginia.rendered
}

resource "aws_iam_role_policy_attachment" "prometheus_alert_verification_role_attach_policy_virginia" {
    policy_arn = aws_iam_policy.prometheus_verification_policy_virginia.arn
    role       = aws_iam_role.prometheus_alert_verification_lambda_role.name
}

resource "aws_lambda_function" "prometheus_alert_verification_lambda_virginia" {
    provider         = aws.dr
    image_uri        = local.prometheus_alert_image_virginia
    function_name    = "${local.naming_prefix_virginia}-mon-prometheus_alert_verification_lambda"
    package_type     = "Image"
    role             = aws_iam_role.prometheus_alert_verification_lambda_role.arn
    timeout          = 10

    image_config {
      command = ["prometheus_alerts_verification_lambda.lambda_handler"]
    }

    vpc_config {
        subnet_ids         = [data.aws_subnet.backend_a_virginia.id, data.aws_subnet.backend_b_virginia.id, data.aws_subnet.backend_c_virginia.id]
        security_group_ids = [aws_security_group.prometheus_alert_virginia.id]
    }

    environment {
        variables = {
            CLOUD_ACCOUNT_REGION  = local.region_virginia
            CLOUD_ACCOUNT_ID      = local.account_id
            CLOUD_ACCOUNT_NAME    = local.environment
            NOTIFY_EMAILS         = "monalytics_services@hedgeserv.com"
            PROMETHEUS_ENDPOINT   = aws_prometheus_workspace.eks_workspace_virginia.prometheus_endpoint
        }
    }

    depends_on = [
        aws_iam_role_policy_attachment.prometheus_alert_verification_lambda_logs,
        aws_cloudwatch_log_group.prometheus_alert_verification_lambda_log_group_virginia,
        aws_prometheus_workspace.eks_workspace_virginia,
        aws_security_group.prometheus_alert_virginia,
    ]

    tags = {
        "Name"                      = "${local.naming_prefix_virginia}-mon-prometheus_alert_verification_lambda",
        "Env"                       = local.environment,
        "Region"                    = local.region_virginia,
        "hs:std:app-code"           = "PROM",
        "hs:std:app-name"           = "Prometheus_verification",
        "hs:std:description"        = "Prometheus alert verification lambda",
        "hs:std:svc-operator"       = "ITSMA",
        "hs:std:svc-software-owner" = "ITSMA"
    }
}

resource "aws_cloudwatch_log_group" "prometheus_alert_verification_lambda_log_group_virginia" {
    provider          = aws.dr
    name              = "/aws/lambda/${local.naming_prefix_virginia}-mon-prometheus_alert_verification_lambda"
    retention_in_days = 14
}

# Define EventBridge scheduler for the lambda
resource "aws_iam_role_policy_attachment" "prometheus_verification_scheduler_virginia" {
    provider    = aws.dr
    policy_arn  = aws_iam_policy.prometheus_verification_scheduler_policy_virginia.arn
    role        = aws_iam_role.prometheus_verification_scheduler_role.name
}

resource "aws_iam_policy" "prometheus_verification_scheduler_policy_virginia" {
    provider  = aws.dr
    name      = "${local.naming_prefix_virginia}-mon-prometheus-verification-scheduler-policy"
    policy    = templatefile("${path.module}/policies/prometheus_verification_scheduler_policy.json", {
        lambda_arn = aws_lambda_function.prometheus_alert_verification_lambda_virginia.arn
    })
}

resource "aws_scheduler_schedule" "prometheus_verification_scheduler_virginia" {
    provider  = aws.dr
    name      = "prometheus_verification_scheduler"

    flexible_time_window {
        mode = "OFF"
    }

    schedule_expression = "rate(24 hours)"

    target {
        arn       = aws_lambda_function.prometheus_alert_verification_lambda_virginia.arn
        role_arn  = aws_iam_role.prometheus_verification_scheduler_role.arn
    }

    depends_on = [
        aws_lambda_function.prometheus_alert_verification_lambda_virginia,
        aws_iam_role.prometheus_verification_scheduler_role,
    ]
}
