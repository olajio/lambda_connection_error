import os
import requests
# from requests_auth_aws_sigv4 import AWSSigV4
from requests_aws4auth import AWS4Auth
import boto3
from smtplib import SMTP
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

CLOUD_ACCOUNT_REGION = os.getenv('CLOUD_ACCOUNT_REGION')
CLOUD_ACCOUNT_ID = os.getenv('CLOUD_ACCOUNT_ID')
CLOUD_ACCOUNT_NAME = os.getenv('CLOUD_ACCOUNT_NAME')
NOTIFY_EMAILS = os.getenv('NOTIFY_EMAILS')
PROMETHEUS = os.getenv('PROMETHEUS_ENDPOINT')
DOCS = "https://hedgeservcorp.sharepoint.com/:u:/s/GlobalTechnology/MonitoringAndAnalytics/EROQQazKXyNMumUEbbxktwwBTzqYGrCKpRqJpwYlRdPivw?e=84Gea8"

QUERIES = {
    '51003': '(max(container_memory_working_set_bytes{container!="",namespace!~"hs-checklist|hs-rc2",namespace=~"hs-.+"}) by(pod, namespace, job, container) / on(pod) group_right max(kube_pod_container_resource_limits{resource="memory"}) by(pod, namespace, job, container) > 0) * on(pod) group_left(label_owner) (count by (pod, label_owner) (kube_pod_labels{label_filtered_out_alerts!~"^.*51003.*$"}))',
    '51004': 'kube_node_status_condition{condition="DiskPressure", status="true"}',
    '51005': 'kube_node_status_condition{condition="PIDPressure", status="true"}',
    '51006': 'kube_node_status_condition{condition="MemoryPressure", status="true"}',
    '51007': '((kube_replicaset_status_ready_replicas <= kube_replicaset_spec_replicas) or (kube_replicaset_status_ready_replicas > kube_replicaset_spec_replicas)) * on(replicaset, instance) group_left(label_owner) kube_replicaset_labels{label_filtered_out_alerts!~"^.*51013.*$"}',
    '51009': '(kube_pod_container_status_terminated_reason or kube_pod_container_status_last_terminated_reason) * on(pod, namespace) group_left(label_owner) kube_pod_labels{label_filtered_out_alerts!~"^.*51009.*$"}',
    '51014': '(kube_horizontalpodautoscaler_status_current_replicas / on(horizontalpodautoscaler, namespace, instance) group_right() kube_horizontalpodautoscaler_spec_max_replicas * 100) * on(horizontalpodautoscaler, namespace, instance) group_left(label_owner, label_app_kubernetes_io_component) kube_horizontalpodautoscaler_labels{label_filtered_out_alerts!~"^.*51014.*$"}',
    '51041': 'label_replace(kube_job_status_failed{job="kube-state-metrics", reason!~"^$"}, "cronjob", "$1", "job_name", "^(.*)-[0-9]+$") * on (namespace, cronjob, instance) group_left (label_owner, label_app_kubernetes_io_component) kube_cronjob_labels{job="kube-state-metrics"}',
    '51047': '(100 - (avg by(nodename) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 0) * on (nodename) group by(nodename) (label_replace(kube_node_labels{label_node_kubernetes_io_lifecycle="ondemand_components"}, "nodename", "$1", "node", "(.*)"))',
    '51048': '((100 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100) > 0) * on(nodename) group by(nodename) (label_replace(kube_node_labels{label_node_kubernetes_io_lifecycle="ondemand_components"}, "nodename", "$1", "node", "(.*)"))'
}

def get_aws_creds():
    session = boto3.Session(region_name=CLOUD_ACCOUNT_REGION)
    credentials = session.get_credentials()

    return AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        CLOUD_ACCOUNT_REGION,
        "aps",
        session_token=credentials.token if credentials.token else None,
    )


def lambda_handler(event, context):
    if not event or not context:
        pass
    auth = get_aws_creds()
    errors = []
    success = []
    print('Checking alerts')
    for alert, alert_query in QUERIES.items():
        alert_res = {
            'alert': alert
        }
        try:
            params = {'query': alert_query}
            response = requests.get(PROMETHEUS + 'api/v1/query', params=params, auth=auth)

            if len(response.json().get('data', {}).get('result', [])) > 0:
                success.append(alert_res)
            else:
                errors.append(alert_res)
        except Exception as e:
            errors.append(alert_res)
            print('Error: ', str(e))

    print('Errors: ', errors)
    print('Success: ', success)
    if len(errors) > 0:
        notify_for_error(errors)
    
    return (success, errors)


def notify_for_error(failing_alerts=None):
    mail_subject = "Issue with Prometheus alert queries"
    mail_content = "One or more of the prometheus alert queries failed to return any results.\n"
    mail_content += f"Account: {CLOUD_ACCOUNT_NAME}.\n"
    mail_content += f"Region: {CLOUD_ACCOUNT_REGION}.\n"
    mail_content += "This needs to be checked as soon as possible. Alerts with failing queries:\n"
    mail_content += str(failing_alerts)
    mail_content += f"\n\nTroubleshooting steps: {DOCS}"
    
    from_email = 'service-elasticauto@hedgeserv.com'
    email_message = MIMEMultipart()
    email_message.add_header('To', NOTIFY_EMAILS)
    email_message.add_header('From', from_email)
    email_message.add_header('Subject', mail_subject)
    body_part = MIMEText(mail_content)
    email_message.attach(body_part)

    server_name = 'mail.hedgeservtest.com'

    try:
        client = SMTP()
        client.connect(server_name, 25)
        client.sendmail(from_email, NOTIFY_EMAILS, email_message.as_bytes())
        client.quit()
    except Exception as e:
        print(f"Sending email message for lambda errors failed: {e}")
