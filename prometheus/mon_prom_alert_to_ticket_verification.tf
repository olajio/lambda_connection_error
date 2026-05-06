#IAM ROLE for step function

resource "aws_iam_role" "step_function_alarm_verification_role" {
  count       = local.sdp_connection_arn != "Missing" ? 1 : 0
  name = "StepFunctionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Effect = "Allow"
        Sid = ""
      },
    ]
  })
}

resource "aws_iam_policy" "cloudwatch_policy" {
  count       = local.sdp_connection_arn != "Missing" ? 1 : 0
  name   = "CloudWatchPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms",
          "cloudwatch:SetAlarmState",
          "cloudwatch:PutMetricAlarm"
        ]
        Resource = "arn:aws:cloudwatch:*:${local.account_id}:alarm:*"
      },
      {
			"Sid": "VisualEditor0",
			"Effect": "Allow",
			"Action": [
				"secretsmanager:GetSecretValue",
				"secretsmanager:DescribeSecret"
			],
			"Resource": "arn:aws:secretsmanager:*:${local.account_id}:*"
		},
		{
			"Sid": "Statement2",
			"Effect": "Allow",
			"Action": [
				"events:RetrieveConnectionCredentials"
			],
			"Resource": "arn:aws:events:*:${local.account_id}:*"
		},
		{
			"Sid": "VisualEditor1",
			"Effect": "Allow",
			"Action": "states:InvokeHTTPEndpoint",
			"Resource": "*"
		}
    ]
  })
}

resource "aws_iam_policy_attachment" "step_function_policy_attachment" {
  count       = local.sdp_connection_arn != "Missing" ? 1 : 0
  name       = "attach_cloudwatch_policy"
  roles      = [aws_iam_role.step_function_alarm_verification_role[0].name]
  policy_arn = aws_iam_policy.cloudwatch_policy[0].arn
}


# Define SNS topic
resource "aws_sns_topic" "mon_prom_alert_verification_sns" {
  count               = local.sdp_connection_arn != "Missing" ? 1 : 0
  name                = "${local.naming_prefix}-mon_prom_alert_verification_sns"
  kms_master_key_id   = var.sns_kms_master_key_id
}

resource "aws_sns_topic_policy" "mon_prom_alert_verification_sns_policy" {
  count      = local.sdp_connection_arn != "Missing" ? 1 : 0
  arn        = aws_sns_topic.mon_prom_alert_verification_sns[0].arn
  policy     = data.template_file.mon_prom_alert_verification_sns_policy[0].rendered
  depends_on = [aws_sns_topic.mon_prom_alert_verification_sns[0]]
}



data "template_file" "mon_prom_alert_verification_sns_policy" {
  count    = local.sdp_connection_arn != "Missing" ? 1 : 0
  template = file("${path.module}/policies/mon_alarm_verification_sns_policy.json")
  vars     = {
    sns_topic_arn = aws_sns_topic.mon_prom_alert_verification_sns[0].arn
    role_arn      = aws_iam_role.step_function_alarm_verification_role[0].arn
    account_id    = local.account_id
    topic_name    = "${local.naming_prefix}-mon_prom_alert_verification_sns"
  }
}

resource "aws_sns_topic_subscription" "mon_prom_alert_verification_email-target" {
  count     = local.sdp_connection_arn != "Missing" ? 1 : 0
  topic_arn = aws_sns_topic.mon_prom_alert_verification_sns[0].arn
  protocol  = "email"
  endpoint  = "monalytics_services@hedgeserv.com"
}

# Create the step function
resource "aws_sfn_state_machine" "prom_alert_to_ticket_verification" {
  count       = local.sdp_connection_arn != "Missing" ? 1 : 0
  name        = "${local.naming_prefix}-mon-prom_alert_to_ticket_verification"
  role_arn    = aws_iam_role.step_function_alarm_verification_role[0].arn

  definition = jsonencode({
  "Comment": "Tests the flow of events from prometheus alert to SDP ticket creation",
  "QueryLanguage": "JSONata",
  "StartAt": "SDP request params",
  "States": {
    "Call SDP - Search for test ticket": {
      "Arguments": {
        "ApiEndpoint": "https://elk-support.hedgeserv.com/api/v3/requests",
        "Headers": {
          "Content-Type": "application/x-www-form-urlencoded"
        },
        "InvocationConfig": {
          "ConnectionArn": "${local.sdp_connection_arn}"
        },
        "Method": "GET",
        "QueryParameters": {
          "input_data": "{% $string($sdp_search_ticket) %}"
        },
        "Transform": {
          "RequestBodyEncoding": "URL_ENCODED",
          "RequestEncodingOptions": {
            "ArrayFormat": "INDICES"
          }
        }
      },
      "Assign": {
        "sdp_found_ticket_num": "{% $states.result.ResponseBody.requests[0].id ? $string($states.result.ResponseBody.requests[0].id) : 'Ticket not found' %}",
        "sdp_response": "{% $states.result.ResponseBody.requests %}"
      },
      "Next": "Choice",
      "Resource": "arn:aws:states:::http:invoke",
      "Retry": [
        {
          "BackoffRate": 2,
          "ErrorEquals": [
            "States.ALL"
          ],
          "IntervalSeconds": 1,
          "JitterStrategy": "FULL",
          "MaxAttempts": 3
        }
      ],
      "Type": "Task"
    },
    "Choice": {
      "Choices": [
        {
          "Condition": "{% $count($sdp_response) > 0 %}",
          "Next": "Map"
        },
        {
          "Condition": "{% $count($sdp_response) < 1 %}",
          "Next": "Sent Email"
        }
      ],
      "Type": "Choice"
    },
    "Map": {
      "Type": "Map",
      "ItemProcessor": {
        "ProcessorConfig": {
          "Mode": "INLINE"
        },
        "StartAt": "Call SDP - Add resolution to test ticket",
        "States": {
          "Call SDP - Add resolution to test ticket": {
            "Arguments": {
              "ApiEndpoint": "{% 'https://elk-support.hedgeserv.com/api/v3/requests/'& $states.input.id &'/resolutions' %}",
              "Headers": {
                "Content-Type": "application/x-www-form-urlencoded"
              },
              "InvocationConfig": {
                "ConnectionArn": "${local.sdp_connection_arn}"
              },
              "Method": "POST",
              "QueryParameters": {
                "input_data": "{% $string($sdp_resolution_ticket) %}"
              },
              "Transform": {
                "RequestBodyEncoding": "URL_ENCODED",
                "RequestEncodingOptions": {
                  "ArrayFormat": "INDICES"
                }
              }
            },
            "Assign": {
              "sdp_resolution_response": "{% $states.result %}",
              "sdp_ticket_num": "{% $states.input.id %}"
            },
            "Resource": "arn:aws:states:::http:invoke",
            "Retry": [
              {
                "BackoffRate": 2,
                "ErrorEquals": [
                  "States.ALL"
                ],
                "IntervalSeconds": 1,
                "JitterStrategy": "FULL",
                "MaxAttempts": 3
              }
            ],
            "Type": "Task",
            "Next": "Call SDP - Add technician"
          },
          "Call SDP - Add technician": {
            "Arguments": {
              "ApiEndpoint": "{% 'https://elk-support.hedgeserv.com/api/v3/requests/'& $sdp_ticket_num &'/assign' %}",
              "InvocationConfig": {
                "ConnectionArn": "${local.sdp_connection_arn}"
              },
              "Method": "PUT",
              "QueryParameters": {
                "input_data": "{% $string($sdp_technician) %}"
              }
            },
            "Resource": "arn:aws:states:::http:invoke",
            "Retry": [
              {
                "BackoffRate": 2,
                "ErrorEquals": [
                  "States.ALL"
                ],
                "IntervalSeconds": 1,
                "JitterStrategy": "FULL",
                "MaxAttempts": 3
              }
            ],
            "Type": "Task",
            "Next": "Call SDP - Close test ticket"
          },
          "Call SDP - Close test ticket": {
            "Arguments": {
              "ApiEndpoint": "{% 'https://elk-support.hedgeserv.com/api/v3/requests/'& $sdp_ticket_num &'/close' %}",
              "Headers": {
                "Content-Type": "application/x-www-form-urlencoded"
              },
              "InvocationConfig": {
                "ConnectionArn": "${local.sdp_connection_arn}"
              },
              "Method": "PUT",
              "QueryParameters": {
                "input_data": "{% $string($sdp_close_ticket) %}"
              },
              "Transform": {
                "RequestBodyEncoding": "URL_ENCODED",
                "RequestEncodingOptions": {
                  "ArrayFormat": "INDICES"
                }
              }
            },
            "Assign": {
              "sdp_close_response": "{% $states.result %}"
            },
            "Resource": "arn:aws:states:::http:invoke",
            "Retry": [
              {
                "BackoffRate": 2,
                "ErrorEquals": [
                  "States.ALL"
                ],
                "IntervalSeconds": 1,
                "JitterStrategy": "FULL",
                "MaxAttempts": 3
              }
            ],
            "Type": "Task",
            "End": true
          }
        }
      },
      "Next": "Ticket found",
      "Items": "{% $states.input.ResponseBody.requests %}"
    },
    "SDP request params": {
      "Assign": {
        "sdp_close_ticket": {
          "request": {
            "closure_info": {
              "closure_code": {
                "name": "success"
              },
              "requester_ack_resolution": true
            }
          }
        },
        "sdp_resolution_ticket": {
          "resolution": {
            "content": "Close testing ticket for prometheus alarm flow."
          }
        },
        "sdp_search_ticket": {
          "list_info": {
            "fields_required": [
              "id",
              "status.name",
              "group.name",
              "subject",
              "created_time",
              "priority.name",
              "category.name",
              "has_notes",
              "udf_fields.udf_sline_49805",
              "subcategory.name"
            ],
            "get_total_count": "true",
            "row_count": 100,
            "search_criteria": [
              {
                "condition": "is",
                "field": "status.name",
                "values": [
                  "Onhold"
                ]
              },
              {
                "condition": "is",
                "field": "udf_fields.udf_sline_49805",
                "logical_operator": "and",
                "values": [
                  "mt_30013_${local.full_account_name[local.environment]}_${local.region}_PrometheusTest"
                ]
              },
              {
                "condition": "is",
                "field": "group.name",
                "logical_operator": "and",
                "value": "Monitoring and Analytics - Testing"
              }
            ],
            "sort_field": "id",
            "sort_order": "asc"
          }
        },
        "sdp_technician": {
          "request": {
            "technician": {
              "name": "ELK SDP-RECON"
            }
          }
        }
      },
      "Next": "Call SDP - Search for test ticket",
      "Type": "Pass"
    },
    "Sent Email": {
      "Arguments": {
        "Message": {
          "message": "{% 'Step function has failed!!! Ticket Count found in SDP: '& $count($sdp_response) &'; Execution ID: '& $states.context.Execution.Id %}"
        },
        "TopicArn": "${aws_sns_topic.mon_prom_alert_verification_sns[0].arn}"
      },
      "Next": "Ticket not found",
      "Resource": "arn:aws:states:::sns:publish",
      "Type": "Task"
    },
    "Ticket found": {
      "Type": "Succeed"
    },
    "Ticket not found": {
      "Type": "Fail"
    }
  }
})

  tags = {
    Name        = "${local.naming_prefix}-mon-prom_alert_to_ticket_verification"
  }
}

# Define EventBridge scheduler for the step function
resource "aws_iam_role" "mon_prom_alert_verification_scheduler_role" {
  count              = local.sdp_connection_arn != "Missing" ? 1 : 0
  name               = "${local.naming_prefix}-mon-prom-alert-scheduler"
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

resource "aws_iam_role_policy_attachment" "mon_prom_alert_verification_scheduler" {
  count       = local.sdp_connection_arn != "Missing" ? 1 : 0
  policy_arn  = aws_iam_policy.mon_prom_alert_verification_scheduler_policy[0].arn
  role        = aws_iam_role.mon_prom_alert_verification_scheduler_role[0].name
}

resource "aws_iam_policy" "mon_prom_alert_verification_scheduler_policy" {
  count   = local.sdp_connection_arn != "Missing" ? 1 : 0
  name    = "${local.naming_prefix}-mon-prom-alert-verification-scheduler-policy"
  policy  = templatefile("${path.module}/policies/mon_prom_alert_scheduler_policy.json", {
    state_machine_arn = aws_sfn_state_machine.prom_alert_to_ticket_verification[0].arn
  })
}

resource "aws_scheduler_schedule" "mon_prom_alert_verification_scheduler" {
  count = local.sdp_connection_arn != "Missing" ? 1 : 0
  name  = "${local.naming_prefix}-mon_prom_alert_verification_scheduler"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(1 hours)"

  target {
    arn       = aws_sfn_state_machine.prom_alert_to_ticket_verification[0].arn
    role_arn  = aws_iam_role.mon_prom_alert_verification_scheduler_role[0].arn
  }
}

# Deploy to Virginia
# Define SNS topic
resource "aws_sns_topic" "mon_prom_alert_verification_sns_virginia" {
  count               = local.sdp_connection_arn_dr != "Missing" ? 1 : 0
  provider            = aws.dr
  name                = "${local.naming_prefix_virginia }-mon_prom_alert_verification_sns"
  kms_master_key_id   = var.sns_kms_master_key_id
}

resource "aws_sns_topic_policy" "mon_prom_alert_verification_sns_policy_virginia" {
  count      = local.sdp_connection_arn_dr != "Missing" ? 1 : 0
  provider   = aws.dr
  arn        = aws_sns_topic.mon_prom_alert_verification_sns_virginia[0].arn
  policy     = data.template_file.mon_prom_alert_verification_sns_policy_virginia[0].rendered
  depends_on = [aws_sns_topic.mon_prom_alert_verification_sns_virginia[0]]
}

data "template_file" "mon_prom_alert_verification_sns_policy_virginia" {
  count    = local.sdp_connection_arn_dr != "Missing" ? 1 : 0
  template = file("${path.module}/policies/mon_alarm_verification_sns_policy.json")
  vars     = {
    sns_topic_arn = aws_sns_topic.mon_prom_alert_verification_sns_virginia[0].arn
    role_arn      = aws_iam_role.step_function_alarm_verification_role[0].arn
    account_id    = local.account_id
    topic_name    = "${local.naming_prefix_virginia }-mon_prom_alert_verification_sns"
  }
}

resource "aws_sns_topic_subscription" "mon_prom_alert_verification_email-target_virginia" {
  count     = local.sdp_connection_arn_dr != "Missing" ? 1 : 0
  provider  = aws.dr
  topic_arn = aws_sns_topic.mon_prom_alert_verification_sns_virginia[0].arn
  protocol  = "email"
  endpoint  = "monalytics_services@hedgeserv.com"
}

# Create the step function
resource "aws_sfn_state_machine" "prom_alert_to_ticket_verification_virginia" {
  count       = local.sdp_connection_arn_dr != "Missing" ? 1 : 0
  provider    = aws.dr
  name        = "${local.naming_prefix_virginia }-mon-prom_alert_to_ticket_verification"
  role_arn    = aws_iam_role.step_function_alarm_verification_role[0].arn

  definition = jsonencode({
  "Comment": "Tests the flow of events from prometheus alert to SDP ticket creation",
  "QueryLanguage": "JSONata",
  "StartAt": "SDP request params",
  "States": {
    "Call SDP - Search for test ticket": {
      "Arguments": {
        "ApiEndpoint": "https://elk-support.hedgeserv.com/api/v3/requests",
        "Headers": {
          "Content-Type": "application/x-www-form-urlencoded"
        },
        "InvocationConfig": {
          "ConnectionArn": "${local.sdp_connection_arn_dr}"
        },
        "Method": "GET",
        "QueryParameters": {
          "input_data": "{% $string($sdp_search_ticket) %}"
        },
        "Transform": {
          "RequestBodyEncoding": "URL_ENCODED",
          "RequestEncodingOptions": {
            "ArrayFormat": "INDICES"
          }
        }
      },
      "Assign": {
        "sdp_found_ticket_num": "{% $states.result.ResponseBody.requests[0].id ? $string($states.result.ResponseBody.requests[0].id) : 'Ticket not found' %}",
        "sdp_response": "{% $states.result.ResponseBody.requests %}"
      },
      "Next": "Choice",
      "Resource": "arn:aws:states:::http:invoke",
      "Retry": [
        {
          "BackoffRate": 2,
          "ErrorEquals": [
            "States.ALL"
          ],
          "IntervalSeconds": 1,
          "JitterStrategy": "FULL",
          "MaxAttempts": 3
        }
      ],
      "Type": "Task"
    },
    "Choice": {
      "Choices": [
        {
          "Condition": "{% $count($sdp_response) > 0 %}",
          "Next": "Map"
        },
        {
          "Condition": "{% $count($sdp_response) < 1 %}",
          "Next": "Sent Email"
        }
      ],
      "Type": "Choice"
    },
    "Map": {
      "Type": "Map",
      "ItemProcessor": {
        "ProcessorConfig": {
          "Mode": "INLINE"
        },
        "StartAt": "Call SDP - Add resolution to test ticket",
        "States": {
          "Call SDP - Add resolution to test ticket": {
            "Arguments": {
              "ApiEndpoint": "{% 'https://elk-support.hedgeserv.com/api/v3/requests/'& $states.input.id &'/resolutions' %}",
              "Headers": {
                "Content-Type": "application/x-www-form-urlencoded"
              },
              "InvocationConfig": {
                "ConnectionArn": "${local.sdp_connection_arn_dr}"
              },
              "Method": "POST",
              "QueryParameters": {
                "input_data": "{% $string($sdp_resolution_ticket) %}"
              },
              "Transform": {
                "RequestBodyEncoding": "URL_ENCODED",
                "RequestEncodingOptions": {
                  "ArrayFormat": "INDICES"
                }
              }
            },
            "Assign": {
              "sdp_resolution_response": "{% $states.result %}",
              "sdp_ticket_num": "{% $states.input.id %}"
            },
            "Resource": "arn:aws:states:::http:invoke",
            "Retry": [
              {
                "BackoffRate": 2,
                "ErrorEquals": [
                  "States.ALL"
                ],
                "IntervalSeconds": 1,
                "JitterStrategy": "FULL",
                "MaxAttempts": 3
              }
            ],
            "Type": "Task",
            "Next": "Call SDP - Add technician"
          },
          "Call SDP - Add technician": {
            "Arguments": {
              "ApiEndpoint": "{% 'https://elk-support.hedgeserv.com/api/v3/requests/'& $sdp_ticket_num &'/assign' %}",
              "InvocationConfig": {
                "ConnectionArn": "${local.sdp_connection_arn_dr}"
              },
              "Method": "PUT",
              "QueryParameters": {
                "input_data": "{% $string($sdp_technician) %}"
              }
            },
            "Resource": "arn:aws:states:::http:invoke",
            "Retry": [
              {
                "BackoffRate": 2,
                "ErrorEquals": [
                  "States.ALL"
                ],
                "IntervalSeconds": 1,
                "JitterStrategy": "FULL",
                "MaxAttempts": 3
              }
            ],
            "Type": "Task",
            "Next": "Call SDP - Close test ticket"
          },
          "Call SDP - Close test ticket": {
            "Arguments": {
              "ApiEndpoint": "{% 'https://elk-support.hedgeserv.com/api/v3/requests/'& $sdp_ticket_num &'/close' %}",
              "Headers": {
                "Content-Type": "application/x-www-form-urlencoded"
              },
              "InvocationConfig": {
                "ConnectionArn": "${local.sdp_connection_arn_dr}"
              },
              "Method": "PUT",
              "QueryParameters": {
                "input_data": "{% $string($sdp_close_ticket) %}"
              },
              "Transform": {
                "RequestBodyEncoding": "URL_ENCODED",
                "RequestEncodingOptions": {
                  "ArrayFormat": "INDICES"
                }
              }
            },
            "Assign": {
              "sdp_close_response": "{% $states.result %}"
            },
            "Resource": "arn:aws:states:::http:invoke",
            "Retry": [
              {
                "BackoffRate": 2,
                "ErrorEquals": [
                  "States.ALL"
                ],
                "IntervalSeconds": 1,
                "JitterStrategy": "FULL",
                "MaxAttempts": 3
              }
            ],
            "Type": "Task",
            "End": true
          }
        }
      },
      "Next": "Ticket found",
      "Items": "{% $states.input.ResponseBody.requests %}"
    },
    "SDP request params": {
      "Assign": {
        "sdp_close_ticket": {
          "request": {
            "closure_info": {
              "closure_code": {
                "name": "success"
              },
              "requester_ack_resolution": true
            }
          }
        },
        "sdp_resolution_ticket": {
          "resolution": {
            "content": "Close testing ticket for prometheus alarm flow."
          }
        },
        "sdp_search_ticket": {
          "list_info": {
            "fields_required": [
              "id",
              "status.name",
              "group.name",
              "subject",
              "created_time",
              "priority.name",
              "category.name",
              "has_notes",
              "udf_fields.udf_sline_49805",
              "subcategory.name"
            ],
            "get_total_count": "true",
            "row_count": 100,
            "search_criteria": [
              {
                "condition": "is",
                "field": "status.name",
                "values": [
                  "Onhold"
                ]
              },
              {
                "condition": "is",
                "field": "udf_fields.udf_sline_49805",
                "logical_operator": "and",
                "values": [
                  "mt_30013_${local.full_account_name[local.environment]}_${local.region_virginia}_PrometheusTest"
                ]
              },
              {
                "condition": "is",
                "field": "group.name",
                "logical_operator": "and",
                "value": "Monitoring and Analytics - Testing"
              }
            ],
            "sort_field": "id",
            "sort_order": "asc"
          }
        },
        "sdp_technician": {
          "request": {
            "technician": {
              "name": "ELK SDP-RECON"
            }
          }
        }
      },
      "Next": "Call SDP - Search for test ticket",
      "Type": "Pass"
    },
    "Sent Email": {
      "Arguments": {
        "Message": {
          "message": "{% 'Step function has failed!!! Ticket Count found in SDP: '& $count($sdp_response) &'; Execution ID: '& $states.context.Execution.Id %}"
        },
        "TopicArn": "${aws_sns_topic.mon_prom_alert_verification_sns_virginia[0].arn}"
      },
      "Next": "Ticket not found",
      "Resource": "arn:aws:states:::sns:publish",
      "Type": "Task"
    },
    "Ticket found": {
      "Type": "Succeed"
    },
    "Ticket not found": {
      "Type": "Fail"
    }
  }
})

  tags = {
    Name        = "${local.naming_prefix_virginia}-mon-prom_alert_to_ticket_verification"
  }
}

# Define EventBridge scheduler for the step function

resource "aws_iam_role_policy_attachment" "mon_prom_alert_verification_scheduler_virginia" {
  count       = local.sdp_connection_arn_dr != "Missing" ? 1 : 0
  provider    = aws.dr
  policy_arn  = aws_iam_policy.mon_prom_alert_verification_scheduler_policy_virginia[0].arn
  role        = aws_iam_role.mon_prom_alert_verification_scheduler_role[0].name
}

resource "aws_iam_policy" "mon_prom_alert_verification_scheduler_policy_virginia" {
  count     = local.sdp_connection_arn_dr != "Missing" ? 1 : 0
  provider  = aws.dr
  name      = "${local.naming_prefix_virginia}-mon-prom-alert-verification-scheduler-policy"
  policy    = templatefile("${path.module}/policies/mon_prom_alert_scheduler_policy.json", {
    state_machine_arn = aws_sfn_state_machine.prom_alert_to_ticket_verification_virginia[0].arn
  })
}

resource "aws_scheduler_schedule" "mon_prom_alert_verification_scheduler_virginia" {
  count     = local.sdp_connection_arn_dr != "Missing" ? 1 : 0
  provider  = aws.dr
  name      = "${local.naming_prefix_virginia }-mon_prom_alert_verification_scheduler"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(1 hours)"

  target {
    arn       = aws_sfn_state_machine.prom_alert_to_ticket_verification_virginia[0].arn
    role_arn  = aws_iam_role.mon_prom_alert_verification_scheduler_role[0].arn
  }
}
