# pylint: disable=redefined-outer-name
import os
import contextlib
from datetime import datetime
import csv
import json
import boto3
from smtplib import SMTP
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication

import elasticsearch
import elasticsearch.helpers

REPORT_FILE = '/tmp/prometheus_alert_events.csv'

ALARM_TAGS_PREFIXES = ['hs_app_', 'hs_std_']

ELK_INDEX = os.getenv('ELK_INDEX')
CLOUD_ACCOUNT_REGION = os.getenv('CLOUD_ACCOUNT_REGION')
CLOUD_ACCOUNT_ID = os.getenv('CLOUD_ACCOUNT_ID')
CLOUD_ACCOUNT_NAME = os.getenv('CLOUD_ACCOUNT_NAME')
ELK_SECRET_NAME = os.getenv('ELK_SECRET_NAME')
NOTIFY_EMAILS = os.getenv('NOTIFY_EMAILS')

LABELS_TO_TRACK = [
    'event_type', # required
    'event_uuid', # required
    'alarm_reason', # required
    'alertname', # always available
    'amdb_link', # defaulted
    'cloud_account_id', # defaulted
    'cloud_account_name', # defaulted
    'cloud_account_region', # defaulted
    'dashboard_link', # required
    'tags_to_exclude', # required
    'alert_time_range_m' # defaulted in milliseconds(how far back to look for the error)
]

DEFAULT_LABELS = {
    'amdb_link': 'https://hedgeservcorp.sharepoint.com/sites/globaltechnology/amdb/sitepages/(event_type).aspx?web=1',
    'cloud': {
        'account': {
            'id': CLOUD_ACCOUNT_ID,
            'name': CLOUD_ACCOUNT_NAME,
            'region': CLOUD_ACCOUNT_REGION
        }
    },
    'alarm_tags': {
        'hs:app:amdb': '',
        'hs:app:monitored': 'true',
        'hs:app:sdp-priority': '2 - High',
        'hs:std:svc-operator': 'TechOps',
        'hs:std:app-name': 'NA',
        'hs:std:app-code': 'NA'
    },
    'alert_time_range_m': 5
}

local_cache = {}
if not local_cache.get('aws_request_id', None):
    local_cache['aws_request_id'] = {}
sm_client = boto3.client('secretsmanager')

service = {
    'name': 'prometheus-alerts',
    'type': 'lambda'
}

def get_elk_credentials():
    print('Getting elastic credentials from secrets manager!')
    secret_arn = f'arn:aws:secretsmanager:{CLOUD_ACCOUNT_REGION}:{CLOUD_ACCOUNT_ID}:secret:{ELK_SECRET_NAME}'
    sm_response = sm_client.get_secret_value(SecretId=secret_arn)
    secret = json.loads(sm_response['SecretString'])

    api_key = get_secret_value('api_key', secret)
    host = ":".join([get_secret_value('host', secret), str(get_secret_value('host_port', secret))])
    local_cache['elk_key'] = api_key
    local_cache['elk_host'] = host

    return host, api_key


def get_secret_value(key, secret):
    return secret.get(key, "").strip().rstrip('"').lstrip('"')

def get_es_client(elk_host, api_key):
    print('Setting Elastic client!')
    try:
        es = elasticsearch.Elasticsearch(elk_host, api_key=api_key, timeout=60, verify_certs=False, ssl_show_warn=False)
        local_cache['es'] = es
        return es
    except elasticsearch.AuthenticationException as e:
        print(f"Elastic AuthenticationException: {e}")
        return None

def setup_elastic_client():
    if not local_cache.get('elk_key', None) or not local_cache.get('elk_host', None):
        elk_host, elk_key = get_elk_credentials()
    else:
        elk_host = local_cache.get('elk_host')
        elk_key = local_cache.get('elk_key')

    get_es_client(elk_host, elk_key)
    return elk_key, elk_host

INIT_ERROR = None
try:
    elk_key, elk_host = setup_elastic_client()
except Exception as e:
    # print(f"Failure during initialization: {e}")
    INIT_ERROR = f"Failure during initialization: {e}"


def lambda_handler(event, context):
    print('Event:\n', event)
    error = None
    result = None
    alerts = None
    try:
        print('Parsing Alert Events...')
        alerts = parse_event(event, context)
        print('Alerts:\n', alerts)
        if len(alerts) == 0:
            print('No active alerts in the event! Skipping...')
            return
        
        if INIT_ERROR:
            print(f"Failed to initialize es client: {INIT_ERROR}")

        result, error = ingest_logs(alerts)

        print('Result from request to Elastic to ingest alert events:', result)
    except Exception as e:
        error = str(e)
        print('Error: \n', error)
    
    if error:
        # print('Request id from cache: ', local_cache.get('aws_request_id'))
        if local_cache['aws_request_id'].get(str(context.aws_request_id), None):
            if local_cache['aws_request_id'].get(str(context.aws_request_id), 1) == 2:
                try:
                    notify_for_error(error, alerts, str(context.aws_request_id))
                    local_cache['aws_request_id'].pop(str(context.aws_request_id))
                except Exception as e:
                    print(f"Couldn't notify for error: {e}")
            else:
                local_cache['aws_request_id'][str(context.aws_request_id)] += 1
        else:
            local_cache['aws_request_id'][str(context.aws_request_id)] = 1

        raise Exception('Error: ', error)


def parse_event(event, context):
    alert_events = []
    for record in event.get('Records', []):
        sns_event = record.get('Sns', {})
        if not sns_event:
            continue
        
        time = sns_event.get('Timestamp', datetime.now().isoformat())
        event_message = sns_event.get('Message', None)
        if not event_message:
            continue

        
        if len(event_message.split('Alerts Firing:')) < 2:
            print('No Alerts Firing found during event parsing!')
            return alert_events
        all_alerts = event_message.split('Alerts Firing:')[1]
        active_alerts = all_alerts.split('Alerts Resolved:')[0]
        # resolved_alerts = all_alerts.split('Alerts Resolved:')[-1]
        alerts = active_alerts.split('Labels:')
        
        # print('Alerts:')
        for alert in alerts:
            if alert in ('', '\n'):
                continue

            labels = alert.split('\n')

            parsed_labels = parse_labels(labels)
            if parsed_labels:
                parsed_labels['@timestamp'] = time
                parsed_labels['service'] = service
                parsed_labels['trace_id'] = str(context.aws_request_id)
                build_grafana_dashboard_link(parsed_labels)
                populate_default_labels(parsed_labels)
                alert_events.append(parsed_labels)
                # print(parsed_labels)

    return alert_events


def parse_labels(labels):
    # print('Parsing labels: ', labels)
    config = {
        'alarm_tags': {}
    }

    for label in labels:
        if label == '' or label.startswith('Annotations:') or label.startswith('Source:'):
            continue

        components = label.split('=')
        if len(components) < 2:
            continue
        field = components[0][3:].strip()
        value = components[1].strip()

        if field.lower().startswith('alarm_tags_'):
            field = field.replace('alarm_tags_', '')
            if 'hs_app_' in field or 'hs_std_' in field:
                field = field.replace('hs_app_', 'hs:app:').replace('hs_std_', 'hs:std:').replace('_', '-')
                config['alarm_tags'][field] = value
            else:
                config['alarm_tags'][field] = value
        elif not field in LABELS_TO_TRACK:
            continue
        # elif 'cloud_account' in field:
        #     cloud_data = field.split('_')
        #     if config.get('cloud', None):
        #         config['cloud']['account'][cloud_data[-1]] = value
        #     else:
        #         config['cloud'] = {
        #             'account': {
        #                 cloud_data[-1]: value
        #             }
        #         }
        else:
            if field == 'alertname':
                config['alarm_name'] = value
            else:
                config[field] = value
    if not config['alarm_tags'].get('hs:app:monitored', 'true').lower() == 'true':
        # print('hs:app:monitored is not set to true')
        return None
    return config


def build_grafana_dashboard_link(alert_event):
    dashboard_link = alert_event.get('dashboard_link', '')
    if alert_event.get('alert_time_range_m', None):
        from_time, to_time = get_timestamp_filters(int(alert_event['alert_time_range_m']))
        del alert_event['alert_time_range_m']
    else:
        from_time, to_time = get_timestamp_filters()
    alert_event['dashboard_link'] = dashboard_link.replace('(from_time)', str(from_time)).replace('(to_time)', str(to_time)).replace('||', '=').replace('var-datasource=1:', 'var-datasource=')


def get_timestamp_filters(time_range_m=5):
    # to_time = int(datetime.timestamp(invoke_time))
    time_range_ms = time_range_m * 60000
    to_time = datetime.now().timestamp() * 1000
    from_time = to_time - time_range_ms
    return from_time, to_time


def populate_default_labels(alert_event):
    amdb = alert_event.get('event_type').split('_')[1]
    if not alert_event.get('amdb_link', None):
        alert_event['amdb_link'] = DEFAULT_LABELS.get('amdb_link', '').replace('(event_type)', amdb)
    if not  alert_event.get('cloud', None):
        alert_event['cloud'] = DEFAULT_LABELS.get('cloud')

    if not alert_event.get('alarm_tags', None):
        alert_event['alarm_tags'] = DEFAULT_LABELS.get('alarm_tags')
    else:
        for k, v in DEFAULT_LABELS.get('alarm_tags').items():
            if not alert_event['alarm_tags'].get(k, None):
                if k == 'hs:app:amdb':
                    alert_event['alarm_tags'][k] = alert_event.get('event_type', '')
                else:
                    alert_event['alarm_tags'][k] = v


def ingest_logs(alerts):
    print('Ingesting alert events in Elastic...')
    try:
        es = local_cache.get('es')
        result = elasticsearch.helpers.bulk(es, gendata(alerts), request_timeout=8)
        return result, None
    except Exception as e:
        print(f"Elastic Exception: {e}")
        return None, str(e)


def gendata(payload):
    for item in payload:
        item['_index'] = ELK_INDEX
        yield item


def notify_for_error(error, alerts, lambda_exec_id='Missing lambda exec id!'):
    print('Notifying for lambda error with id ', lambda_exec_id)
    mail_subject = f"Monitoring lambda error - " + lambda_exec_id
    mail_content = f"There was an error in one of the Monitoring Lambdas. Details:\n"
    mail_content += f"Lambda: prometheus_alerts_lambda\nAccount: {CLOUD_ACCOUNT_ID}\nRegion: {CLOUD_ACCOUNT_REGION}\nError: {error}\n"
    mail_content += '\nFor a list of affected resource and teams to notify please check the attached file!\n'
    
    from_email = 'service-elasticauto@hedgeserv.com'
    email_message = MIMEMultipart()
    email_message.add_header('To', NOTIFY_EMAILS)
    email_message.add_header('From', from_email)
    email_message.add_header('Subject', mail_subject)
    body_part = MIMEText(mail_content)
    email_message.attach(body_part)

    server_name = 'mail.hedgeservtest.com'

    if alerts:
        build_report_file(REPORT_FILE, alerts)
        with open(REPORT_FILE, 'rb') as f:
            email_message.attach(MIMEApplication(f.read(), Name='prometheus_alert_events.csv'))

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
        writer.writerow(['AMDB', 'Resource', 'Owner', 'GrafanaLink', 'AMDBLink'])
        for alert in alerts:
            writer.writerow([
                alert.get('event_type', 'missing_event_type'),
                alert.get('event_uuid', '').split('_')[-1],
                alert.get('alarm_tags', {}).get('hs:std:svc-software-owner', 'Missing'),
                alert.get('dashboard_link', ''),
                alert.get('amdb_link')                
            ])


def clear_file(file):
    with contextlib.suppress(FileNotFoundError):
        os.remove(file)
