#!/usr/bin/env python3
import traceback
import boto3
import json
import csv
import os
from smtplib import SMTP
from elasticsearch import Elasticsearch
import datetime
from requests.utils import requote_uri
import urllib.parse
import contextlib
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
    'name': 'cloudwatch-alerts',
    'type': 'lambda'
}

local_cache = {}
if not local_cache.get('aws_request_id', None):
    local_cache['aws_request_id'] = {}


def keep_only_numbers(input_string):
    return ''.join([char for char in input_string if char.isdigit()])


def lambda_handler(cw_alarm_event: dict, context):  # Needs refactoring.. pylint: disable=too-complex
    try:
        print('Getting cloudwatch alarm tags')
        cw_alarm_tags = get_cw_alarm_tags(cw_alarm_event)
        if len(cw_alarm_tags) == 0:
            print(
                f"The Cloudwatch alarm has no tags configured. Skipping {cw_alarm_event['detail']['alarmName']} alarm ...")
            return 0
        ready_alert_event = alert_event_creation(cw_alarm_tags, cw_alarm_event, context)
        if ready_alert_event == 0:
            print("No need to send to elastic")
            return 0

        print("Get the ELK credentials")
        elk_key = local_cache.get('elk_key', None)
        elk_host = local_cache.get('elk_host', None)

        if not elk_key or not elk_host:
            elk_host, elk_key = get_elk_credentials()

        print(f'Sending cloudwatch alarm event to Elastic index')
        response_from_elastic_ingestion = write_event_2_elastic(ready_alert_event, elk_host, elk_key)
        print(response_from_elastic_ingestion)
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
                    print(f"Couldn't notify for error: {e}\n{trace_message}")
            else:
                local_cache['aws_request_id'][str(context.aws_request_id)] += 1
                print('Less than 3 errors for this request id. Last check was: ',
                      local_cache['aws_request_id'][str(context.aws_request_id)])
        else:
            local_cache['aws_request_id'][str(context.aws_request_id)] = 1
        raise Exception('in error - Error: ', error)


def write_event_2_elastic(ready_alert_event, elk_host, elk_key):
    # print(ready_alert_event)
    client = Elasticsearch(elk_host, api_key=elk_key)
    # print(client.info())
    resp = client.index(index=ELK_INDEX, document=ready_alert_event)
    return resp


def alert_event_creation(cw_alarm_tags: dict, cw_alarm_event: dict, context):
    tagsdict = {'cloud': {"account": {}}}
    tagsdict['alarm_tags'] = cw_alarm_tags
    if 'hs:app:monitored' in cw_alarm_tags and cw_alarm_tags['hs:app:monitored'] != 'true':
        print(
            f"The cloudwatch {cw_alarm_event['detail']['alarmName']} alarm hs:app:monitored tag is set to {cw_alarm_tags['hs:app:monitored']}")
    if 'hs:app:monitored' in cw_alarm_tags and cw_alarm_tags['hs:app:monitored'] == 'true' and 'hs:app:amdb' in cw_alarm_tags:
        print(f"Creating Json event for {cw_alarm_event['detail']['alarmName']} cloudwatch alarm")
        # Add new fields
        amdb_number = keep_only_numbers(cw_alarm_tags['hs:app:amdb'])
        tagsdict['alarm_name'] = cw_alarm_event['detail']['alarmName']
        tagsdict['event_type'] = cw_alarm_tags['hs:app:amdb']
        tagsdict['cloud']['account']['id'] = cw_alarm_event['account']
        tagsdict['cloud']['account']['name'] = ENV
        tagsdict['cloud']['account']['region'] = cw_alarm_event['region']
        cw_alarm_event_url = urllib.parse.quote(cw_alarm_event['detail']['alarmName'].replace('/', '%2F'))
        tagsdict[
            'amdb_link'] = requote_uri(
            f'https://hedgeservcorp.sharepoint.com/sites/globaltechnology/amdb/sitepages/{amdb_number}.aspx')
        tagsdict['dashboard_link'] = requote_uri(
            'https://console.aws.amazon.com/cloudwatch/home?region=' + cw_alarm_event[
                'region'] + '#alarmsV2:alarm/' + cw_alarm_event_url)
        tagsdict['service.type'] = service['type']
        tagsdict['service.name'] = service['name']
        tagsdict['tags_to_exclude'] = 'N_A'
        tagsdict['alarm_reason'] = cw_alarm_event['detail']['state']['reason']
        time = datetime.datetime.utcnow().isoformat() + "Z"
        tagsdict['@timestamp'] = time
        tagsdict['trace_id'] = str(context.aws_request_id)
        tagsdict[
            'event_uuid'] = f"mt_{amdb_number}_{ENV}_{cw_alarm_event['region']}_{cw_alarm_event['detail']['alarmName'].replace(' ', '-')}"
        return tagsdict
    print(f"Alarm event did not meet tag requirements!!!")
    return 0


def get_cw_alarm_tags(cw_alarm_raw_event):
    # The ARN format of an alarm is arn:aws:cloudwatch:Region:account-id:alarm:alarm-name
    alarm_arn = cw_alarm_raw_event['resources'][0]
    # alarm_arn = 'arn:aws:cloudwatch:us-east-2:359068364091:alarm:TEST'
    cw_connection = boto3.client('cloudwatch')
    response = cw_connection.list_tags_for_resource(
        ResourceARN=alarm_arn
    )

    cw_alarm_tags = {subdict['Key']: subdict['Value'] for subdict in response['Tags']}
    print(f'Got {len(cw_alarm_tags)} tags for {alarm_arn}')
    return cw_alarm_tags


def get_secret_value(key, secret):
    return secret.get(key, "").strip().rstrip('"').lstrip('"')


def get_elk_credentials():
    sm_connection = boto3.client('secretsmanager')
    print('Getting elastic credentials from secrets manager')
    secret_arn = f'arn:aws:secretsmanager:{REGION}:{CLOUD_ACCOUNT_ID}:secret:{ELK_SECRET_NAME}'
    sm_response = sm_connection.get_secret_value(SecretId=secret_arn)
    secret = json.loads(sm_response['SecretString'])

    api_key = get_secret_value('api_key', secret)
    host = ":".join([get_secret_value('host', secret), str(get_secret_value('host_port', secret))])
    local_cache['elk_key'] = api_key
    local_cache['elk_host'] = host
    return host, api_key


def notify_for_error(error, ready_alert_event, function_name, lambda_exec_id='Missing lambda exec id!'):
    amdbs = {}
    events = []
    print(f'amdbs: {amdbs}')
    print(f'events: {events}')
    mail_subject = f"Monitoring lambda error - " + lambda_exec_id
    mail_content = f"There was an error in one of the Monitoring Lambdas. Details:\n"
    mail_content += f"Lambda: {function_name}\nAccount: {CLOUD_ACCOUNT_ID}\nRegion: {REGION}\nError: \n{error}\n"
    mail_content += '\nFor a list of affected resource and teams to notify please check the attached file!\n'

    build_report_file(REPORT_FILE, ready_alert_event)
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


def build_report_file(file, alert):
    print(f'Alert event: {alert}')
    with open(file, 'w') as f:
        writer = csv.writer(f)
        writer.writerow(['AMDB', 'Resource', 'Owner', 'Event UUID', 'AWS_Link', 'AMDBLink'])
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
