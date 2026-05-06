#!/usr/bin/env python3
import traceback
import boto3
import json
import csv
import os
import datetime
import elasticsearch
import elasticsearch.helpers
from requests.utils import requote_uri
from smtplib import SMTP
import contextlib
import urllib.parse
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication

REPORT_FILE = '/tmp/cloudwatch_alert_events.csv'

ELK_INDEX = os.getenv('ELK_INDEX')
ENV = os.getenv('ENVIRONMENT')
REGION = os.getenv('REGION')
CLOUD_ACCOUNT_ID = os.getenv('CLOUD_ACCOUNT_ID')
ELK_SECRET_NAME = os.getenv('ELK_SECRET_NAME')
NOTIFY_EMAILS = os.getenv('NOTIFY_EMAILS')

service = {
    'name': 'cloudwatch-active-alerts',
    'type': 'lambda'
}

local_cache = {}
if not local_cache.get('aws_request_id', None):
    local_cache['aws_request_id'] = {}


def keep_only_numbers(input_string):
    return ''.join([char for char in input_string if char.isdigit()])


def get_active_cloudwatch_alarms():
    client = boto3.client('cloudwatch')
    paginator = client.get_paginator('describe_alarms')
    active_alarms = []

    for page in paginator.paginate(StateValue='ALARM'):
        active_alarms.extend(page['MetricAlarms'])

    return active_alarms


def alert_event_creation(cw_alarm_tags: dict, cw_alarm_event: dict, context):
    # extracting the cw alarm state reason data, to get the timestamp of when the alarm started.
    cw_alarm_StateReasonData = json.loads(cw_alarm_event['StateReasonData'])
    tagsdict = {'cloud': {"account": {}}}
    tagsdict['alarm_tags'] = cw_alarm_tags
    if 'hs:app:monitored' in cw_alarm_tags and cw_alarm_tags['hs:app:monitored'] == 'true' and 'hs:app:amdb' in cw_alarm_tags:
        print(
            f"Creating JSON event for alarm {cw_alarm_event['AlarmName']} with hs:app:monitored set to true, will forward to elastic...")
        # Add new fields
        amdb_number = keep_only_numbers(cw_alarm_tags['hs:app:amdb'])
        tagsdict['alarm_name'] = cw_alarm_event['AlarmName']
        tagsdict['event_type'] = cw_alarm_tags['hs:app:amdb']
        tagsdict['cloud']['account']['id'] = CLOUD_ACCOUNT_ID
        tagsdict['cloud']['account']['name'] = ENV
        tagsdict['cloud']['account']['region'] = REGION
        cw_alarm_event_url = urllib.parse.quote(cw_alarm_event['AlarmName'].replace('/', '%2F'))
        tagsdict[
            'amdb_link'] = requote_uri(
            f'https://hedgeservcorp.sharepoint.com/sites/globaltechnology/amdb/sitepages/{amdb_number}.aspx')
        tagsdict[
            'dashboard_link'] = requote_uri(
            'https://console.aws.amazon.com/cloudwatch/home?region=' + REGION + '#alarmsV2:alarm/' + cw_alarm_event_url)
        tagsdict['service.type'] = service['type']
        tagsdict['service.name'] = service['name']
        tagsdict['tags_to_exclude'] = 'N_A'
        # timestamp of when the alarm started
        tagsdict['alarm_reason'] = cw_alarm_event['StateReason']
        # timestamp of when the ivent was processed by the lambda.
        time = datetime.datetime.utcnow().isoformat() + "Z"
        tagsdict['@timestamp'] = time
        tagsdict['cw_alert_timestamp'] = cw_alarm_StateReasonData['queryDate']
        tagsdict['trace_id'] = str(context.aws_request_id)
        tagsdict[
            'event_uuid'] = f"mt_{amdb_number}_{ENV}_{REGION}_{cw_alarm_event['AlarmName'].replace(' ', '-')}"
    else:
        print(f"Check tags 'hs:app:monitored' and 'hs:app:amdb' they do no meet requirements for alarm {cw_alarm_event['AlarmName']}. Skipping alert event...")
        return 0
    return tagsdict


def get_secret_value(key, secret):
    return secret.get(key, "").strip().rstrip('"').lstrip('"')


def get_elk_credentials():
    sm_connection = boto3.client('secretsmanager')
    secret_arn = f'arn:aws:secretsmanager:{REGION}:{CLOUD_ACCOUNT_ID}:secret:{ELK_SECRET_NAME}'
    sm_response = sm_connection.get_secret_value(SecretId=secret_arn)
    secret = json.loads(sm_response['SecretString'])

    api_key = get_secret_value('api_key', secret)
    host = ":".join([get_secret_value('host', secret), str(get_secret_value('host_port', secret))])
    local_cache['elk_key'] = api_key
    local_cache['elk_host'] = host
    return host, api_key


def write_events_2_elastic(alerts_events: dict, elk_host, api_key):
    es = elasticsearch.Elasticsearch(elk_host, api_key=api_key, verify_certs=False, ssl_show_warn=False)
    result = elasticsearch.helpers.bulk(es, gendata(alerts_events), stats_only=False, request_timeout=60)
    return result


def gendata(payload: dict):
    payload_list = payload
    for item in payload_list:
        item['_index'] = ELK_INDEX
        yield item


def get_cw_alarm_tags(cw_alarm_raw_event):
    # The ARN format of an alarm is arn:aws:cloudwatch:Region:account-id:alarm:alarm-name
    alarm_arn = cw_alarm_raw_event
    # alarm_arn = 'arn:aws:cloudwatch:us-east-2:359068364091:alarm:TEST'
    cw_connection = boto3.client('cloudwatch')
    response = cw_connection.list_tags_for_resource(
        ResourceARN=alarm_arn
    )

    cw_alarm_tags = {subdict['Key']: subdict['Value'] for subdict in response['Tags']}
    return cw_alarm_tags


def process_arn(arn: str):
    arn_list = []
    arn_list = arn.split(":")
    return arn_list


def notify_for_error(error, alerts, function_name, lambda_exec_id='Missing lambda exec id!'):
    amdbs = {}
    events = []
    print(f'amdbs: {amdbs}')
    print(f'events: {events}')
    mail_subject = f"Monitoring lambda error - " + lambda_exec_id
    mail_content = f"There was an error in one of the Monitoring Lambdas. Details:\n"
    mail_content += f"Lambda: {function_name}\nAccount: {CLOUD_ACCOUNT_ID}\nRegion: {REGION}\nError: {error}\n"
    mail_content += '\nFor a list of affected resource and teams to notify please check the attached file!\n'

    build_report_file(REPORT_FILE, alerts)
    from_email = 'service-elasticauto@hedgeserv.com'
    email_message = MIMEMultipart()
    email_message.add_header('To', NOTIFY_EMAILS)
    email_message.add_header('From', from_email)
    email_message.add_header('Subject', mail_subject)
    body_part = MIMEText(mail_content)
    email_message.attach(body_part)

    server_name = 'mail.hedgeservtest.com'

    with open(REPORT_FILE, 'rb') as f:
        email_message.attach(MIMEApplication(f.read(), Name='cloudwatch_alert_events.csv'))

    try:
        client = SMTP()
        client.connect(server_name, 25)
        client.sendmail(from_email, NOTIFY_EMAILS, email_message.as_bytes())
        client.quit()
    except Exception as e:
        print(f"Sending email message for lambda errors failed: {e}")

    clear_file(REPORT_FILE)


def build_report_file(file, alerts):
    with open(file, 'w') as f:
        writer = csv.writer(f)
        writer.writerow(['AMDB', 'Resource', 'Owner', 'Event UUID', 'AWS_Link', 'AMDBLink'])
        for alert in alerts:
            writer.writerow([
                alert.get('event_type', 'missing_event_type'),
                alert.get('event_uuid', '').split('_')[-1],
                alert.get('alarm_tags', {}).get('hs:std:svc-software-owner', 'Missing'),
                alert.get('event_uuid', ''),
                alert.get('dashboard_link', ''),
                alert.get('amdb_link')
            ])


def clear_file(file):
    with contextlib.suppress(FileNotFoundError):
        os.remove(file)


def lambda_handler(cw_alarm_event, context):  # Needs refactoring.. pylint: disable=too-complex
    try:
        print(f'cw_alarm_event: {cw_alarm_event}')
        error = None
        # Check cloudwatch alarms for any active alerts
        print(f'Checking for active Cloudwatch Alarms...')
        active_alarms = get_active_cloudwatch_alarms()
        if len(active_alarms) == 0:
            print("No active cloudwatch alarms. Exiting...")
            return 0
        print(f'Found {len(active_alarms)} active alarms')

        ready_alert_event = []

        # Get tags for each active alert
        print(f'Processing each active cloudwatch alarm...')
        for alarm in active_alarms:
            print(f"Alarm Name: {alarm['AlarmName']}, Alarm State: {alarm['StateValue']}, ARN: {alarm['AlarmArn']}")
            cw_alarm_tags = get_cw_alarm_tags(alarm['AlarmArn'])
            print(f'Got {len(cw_alarm_tags)} tags for alarm {alarm["AlarmName"]}')
            alert_event = alert_event_creation(cw_alarm_tags, alarm, context)
            if alert_event != 0:
                ready_alert_event.append(alert_event)

        # Get credentials for connection to elasticsearch
        print(f'Get credentials for connection to elasticsearch')
        elk_key = local_cache.get('elk_key', None)
        elk_host = local_cache.get('elk_host', None)

        if not elk_key or not elk_host:
            elk_host, elk_key = get_elk_credentials()

        # Send ready_alert_event list of events to Elastic
        if len(ready_alert_event) > 0:
            print(f"Sending {len(ready_alert_event)} events to elastic...")
            response_from_elastic_ingestion = write_events_2_elastic(ready_alert_event, elk_host, elk_key)
            print(response_from_elastic_ingestion)
            print(ready_alert_event)
        else:
            print(f"No events to send to elastic. Exiting...")
            return 0

    except Exception as e:
        trace_message = ''.join(traceback.TracebackException.from_exception(e).format())
        print(f'Error!{e}\n{trace_message}')
        error = str(e) + "\n" + str(trace_message)

    if error:
        print('Request id from cache: ', local_cache.get('aws_request_id'))
        if local_cache['aws_request_id'].get(str(context.aws_request_id), None):
            if local_cache['aws_request_id'].get(str(context.aws_request_id), 1) == 2:
                try:
                    notify_for_error(error, ready_alert_event, str(context.function_name), str(context.aws_request_id))
                    notified_request = local_cache['aws_request_id'].pop(str(context.aws_request_id))
                    print(f'notified_request: {notified_request}')
                    print('Notifying for the error via an email for request with id: ', str(context.aws_request_id))
                except Exception as e:
                    print(f"Couldn't notify for error: {e}")
            else:
                local_cache['aws_request_id'][str(context.aws_request_id)] += 1
                print('Less than 3 errors for this request id. Last check was: ',
                      local_cache['aws_request_id'][str(context.aws_request_id)])
        else:
            local_cache['aws_request_id'][str(context.aws_request_id)] = 1
        raise Exception('Error: ', error)
