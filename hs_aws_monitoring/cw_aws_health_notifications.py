import yaml
import json
import os
import uuid
import logging
from datetime import datetime, timezone
import boto3
from hs_common_utilities.util.aws.lambda_json_log_formatter import capture_lambda_metadata, configure_lambda_logging
from hs_aws_monitoring.elastic_utils import set_field, send_to_elastic

log = logging.getLogger('health_notifications')
configure_lambda_logging(service_name='HS AWS Health Notifications', )

cloud_account_name = os.getenv('AWS_ACCOUNT_NAME')
es_index_prefix = os.getenv('ES_INDEX_PREFIX')
es_index_version = os.getenv('ES_INDEX_VERSION')
es_index_env = os.getenv('ES_INDEX_ENV')
event_source = os.getenv('AWS_LAMBDA_FUNCTION_NAME', 'cw_aws_health_notifications')
config_bucket = os.getenv('S3_BUCKET_NAME')
environment = os.getenv('AWS_ENVIRONMENT')

index_id = f'{es_index_prefix}-{es_index_version}-mt-{es_index_env}'
s3_gateway = boto3.client('s3')

@capture_lambda_metadata
def lambda_handler(event, context):  # Required args for lambda functions. pylint: disable=unused-argument
    """
    Process AWS Health events from EventBridge
    """

    log.info(f"Received event: {event}")

    elastic_data = {}
    data = _extract_health_event_data(event)
    exclude_event_types = [] #_load_exclude_event_types()

    # initialize the local_cache with elastic creds
    # _, _ = get_elastic_credentials()

    if data['event_type'] not in exclude_event_types:
        msg_id = str(uuid.uuid4())
        elastic_data[msg_id] = format_elastic_record(data)

        send_to_elastic(elastic_data)
        message = f"Processed {data['event_type']} event for {data['service']}, sent to elasticsearch index {index_id}"
        affected_resources = len(data['entity_list'])

    else:
        message = f"Excluded {data['event_type']} event for {data['service']} based on configuration."
        affected_resources = 0

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': message,
            'affectedResources': affected_resources
        })
    }


def _load_exclude_event_types() -> list:
    s3_key = f"configs/{environment}/cost-anomaly-alerting/cost_category_rules.yaml"
    try:
        response = s3_gateway.get_object(Bucket=config_bucket, Key=s3_key)
        file_content = response['Body'].read().decode('utf-8')
    except s3_gateway.exceptions.NoSuchKey:
        log.error(f"Config file not found in S3: bucket={config_bucket}, key={s3_key}")
        return []
    config = yaml.safe_load(file_content)
    return config.get('exclude_event_types', [])


def _extract_health_event_data(aws_health_event: dict) -> dict:
    account = aws_health_event.get('account')  # per aws docs this is required
    detail = aws_health_event.get('detail', {})

    event_arn = detail.get('eventArn')
    service = detail.get('service', "unknown")
    event_type = detail.get('eventTypeCode', "unknown")
    category = detail.get('eventTypeCategory')
    status = detail.get('statusCode', "unknown")
    region = detail.get('eventRegion', "Global")

    affected_entities = detail.get('affectedEntities', [])
    entity_list = [entity.get('entityValue') for entity in affected_entities]

    if status.lower() == "closed":
        description = "Event has been resolved."
    else:
        descriptions = detail.get('eventDescription', [])
        description = descriptions[0].get('latestDescription', '') if descriptions else ''
        if len(description) > 100:
            description = description[:100] + "... (see dashboard link for full message)"

    return {
        'account': account,
        'event_arn': event_arn,
        'service': service,
        'event_type': event_type,
        'category': category,
        'status': status,
        'region': region,
        'alert_target': "-".join([account, region, service, event_type]),
        'start_time': detail.get('startTime'),
        'end_time': detail.get('endTime', "ongoing event - no end time provided"),
        'urls': construct_health_event_url(event_arn),
        'description': description,
        'entity_list': entity_list,
        'priority': '2 - High' if category == 'issue' else '3 - Moderate',
    }


def format_elastic_record(data: dict) -> dict:
    now = datetime.now(timezone.utc)
    raw_timestamp = now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"

    message = f"""AWS Health Event Notification:
    Links to AWS Dashboard: {data['urls']}
    Service: {data['service']}
    Event Type: {data['event_type']}
    Category: {data['category']}
    Status: {data['status']}
    Start Time: {data['start_time']}
    End Time: {data['end_time']}
    Affected Entities: {data['entity_list']}
    Description: {data['description']}
    """

    elastic_record = {
        "_op_type": "create",
        "_index": index_id,
        "_id": str(uuid.uuid4()),
        "_source": {"service": {"type": "aws", "name": "lambda"}, "ecs": {"version": "1.12.0"}},
        "fields": {"service.type": ["aws"], "service.name": ["lambda"], "ecs.version": ["1.12.0"]}
    }

    set_field(elastic_record, "@timestamp", raw_timestamp)
    set_field(elastic_record, "cloud.account.id", data['account'])
    set_field(elastic_record, "cloud.account.name", cloud_account_name)
    set_field(elastic_record, "cloud.provider", "aws")
    set_field(elastic_record, "cloud.service.name", "AWS Health Notification")
    set_field(elastic_record, "message", message)

    # required for custom critical log alerting
    set_field(elastic_record, "labels.alert_amdb_number", '51031')
    set_field(elastic_record, "labels.alert_owner", 'TechOps & PlatEng')
    set_field(elastic_record, "labels.alert_target", data['alert_target'])
    set_field(elastic_record, "log.level", "Critical")
    set_field(elastic_record, "log.logger", "lambda:cw_aws_health_notifications")
    set_field(elastic_record, "labels.alert_priority", data['priority'])

    return elastic_record


def construct_health_event_url(event_arn):
    """
    Construct a URL to the AWS Health event in the console
    """

    # Base Health Dashboard URL
    base_url = "https://console.aws.amazon.com/health/home"

    # Create a direct link to the event log
    direct_url = f"{base_url}?region=us-east-1#/account/event-log?eventID={event_arn}"

    return {
        'Main AWS Health Dashboard': base_url,
        'direct_link': direct_url
    }

