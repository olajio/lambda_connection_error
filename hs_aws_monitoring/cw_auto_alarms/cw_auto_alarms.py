"""
This Lambda is used discover AWS resources and automatically create cloudwatch alarms for them.
The cloudwatch alarms then can create alerts for service desk.
It is scheduled to run in each account every hour. It is configured using the aws config repo.
For more details, see:
https://tech-docs.shd.pantheon.hedgeservx.com/hs-aws-docs/latest/monitoring/cloud_watch.html#cloudwatch-auto-alarms
"""

import logging
import boto3

from hs_common_utilities.util.aws.lambda_json_log_formatter import capture_lambda_metadata, configure_lambda_logging

from hs_aws_monitoring.cw_auto_alarms.alarm_config import get_s3_alarm_config
from hs_aws_monitoring.cw_auto_alarms.alarm_data import AlarmData
from hs_aws_monitoring.cw_auto_alarms.namespace_config import get_namespace_config, get_resources_and_tags

log = logging.getLogger('auto-alarms')

configure_lambda_logging(service_name='HS CW Auto Alarms')


@capture_lambda_metadata
def handler(event, context):  # Required args for lambda functions. pylint: disable=unused-argument
    """
    Lambda to automatically create CloudWatch alarms.
    Inspired by: https://github.com/aws-samples/amazon-cloudwatch-auto-alarms
    """
    log.info('Generating alarms')
    generate_alarms()
    log.info('Finished successfully')


def generate_alarms():
    s3_alarm_config = get_s3_alarm_config()
    # s3_alarm_config = get_local_alarm_config()
    desired_alarms = get_desired_alarms(s3_alarm_config)
    log.info('Got %s desired alarms', len(desired_alarms))
    save_alarms(desired_alarms)


def get_desired_alarms(s3_alarm_config):
    if not s3_alarm_config.create_alarms:
        return []

    alarms = []
    for namespace_config in get_namespace_config():
        resource_finder = namespace_config['resource_finder']
        for arn, tags in resource_finder(namespace_config['resource_type'], namespace_config['tag_filters']):
            namespace = namespace_config['name']
            resource_identifier = arn.split(namespace_config['identifier_from_arn_parse_char'])[-1]
            for alarm_config in s3_alarm_config.alarm_configs:
                if alarm_config.namespace != namespace or not alarm_config.is_included(tags):
                    continue

                alarm_data = AlarmData(namespace=namespace,
                                       resource_identifier=resource_identifier,
                                       resource_name=tags.get('Name'),
                                       statistic=alarm_config.statistic,
                                       metric_name=alarm_config.metric_name,
                                       metric_math=alarm_config.metric_math,
                                       comparison_operator=alarm_config.comparison_operator,
                                       threshold=alarm_config.get_threshold(tags),
                                       datapoints_to_alarm=alarm_config.datapoints_to_alarm,
                                       evaluation_periods=alarm_config.evaluation_periods,
                                       period=alarm_config.period,
                                       display_name=alarm_config.display_name,
                                       amdb_number=alarm_config.amdb_number,
                                       sdp_priority=alarm_config.sdp_priority,
                                       maintenance_window=bool(alarm_config.maintenance_window),
                                       software_owner=tags.get('hs:std:svc-software-owner', 'TechOps'),
                                       app_code=tags.get('hs:std:app-code', 'UNKNOWN'),
                                       monitored=alarm_config.create_tickets and s3_alarm_config.create_tickets)
                alarms.append(alarm_data)
    return alarms


def save_alarms(desired_alarms):
    cloudwatch = boto3.client('cloudwatch')

    desired_alarm_map = {alarm.alarm_name: alarm for alarm in desired_alarms}

    for arn, tags in get_resources_and_tags('cloudwatch', [{'Key': 'hs:app:auto-generated', 'Values': ['true']}]):
        existing_alarm = AlarmData.create_from_alarm_tags(tags)
        existing_alarm_name = ':'.join(arn.split(':')[6:])
        desired_alarm = desired_alarm_map.pop(existing_alarm_name, None)
        if not desired_alarm:
            log.info('Deleting existing alarm %s %s', existing_alarm_name, existing_alarm)
            cloudwatch.delete_alarms(AlarmNames=[existing_alarm_name])
        elif existing_alarm == desired_alarm:
            log.debug('Alarm already configured correctly %s', desired_alarm.alarm_name)
        else:
            log.info('Updating existing alarm. Before %s, After %s', existing_alarm, desired_alarm)
            cloudwatch.delete_alarms(AlarmNames=[existing_alarm_name])  # put won't change tags unless we delete first
            save_alarm(cloudwatch, desired_alarm)

    for desired_alarm in desired_alarm_map.values():
        log.info('Adding missing alarm %s', desired_alarm)
        save_alarm(cloudwatch, desired_alarm)


def save_alarm(cloudwatch, desired_alarm):
    try:
        alarm_json = desired_alarm.get_alarm_json()
        cloudwatch.put_metric_alarm(**alarm_json)
    except Exception as e:
        log.info(f"Failed to create the CloudWatch alarm using the following alarm_json: \n {alarm_json}")
        raise e

# used for testing locally
# if __name__ == '__main__':
#     handler("", "")

#
# generate_alarms()
