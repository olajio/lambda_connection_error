import base64
import json
import logging
import os

import boto3
from elasticsearch import Elasticsearch, AuthenticationException
from elasticsearch.helpers import streaming_bulk, BulkIndexError

log = logging.getLogger(__name__)

aws_region = os.getenv('AWS_REGION')
cloud_account_id = os.getenv('AWS_ACCOUNT_ID')
es_secret_name = os.getenv('ES_API_KEY_SSM_PATH')

sm_client = boto3.client('secretsmanager')
local_cache = {}


def set_field(elastic_record, elastic_name, value):
    elastic_keys = elastic_name.split('.')
    current_record = elastic_record['_source']
    for elastic_key in elastic_keys[:-1]:
        if elastic_key not in current_record:
            current_record[elastic_key] = {}
        current_record = current_record[elastic_key]
    value = value if value is not None else "None"
    current_record[elastic_keys[-1]] = value
    elastic_record['fields'][elastic_name] = [value]


def get_elastic_credentials():
    log.info("getting credentials from secret manager")
    secret_arn = f'arn:aws:secretsmanager:{aws_region}:{cloud_account_id}:secret:{es_secret_name}'
    sm_response = sm_client.get_secret_value(SecretId=secret_arn)
    secret = json.loads(sm_response['SecretString'])

    api_key = _get_secret_value('api_key', secret)
    host = ":".join([_get_secret_value('host', secret), str(_get_secret_value('host_port', secret))])
    encoded_key = base64.b64encode(bytes(api_key, 'utf-8')).decode('utf-8')
    log.info(f"Got creds from secrets: host={host}, len(api_key)={len(api_key)}")
    local_cache['api_key'] = encoded_key
    local_cache['host'] = host
    return host, encoded_key


def send_to_elastic(elastic_data):
    encoded_key = local_cache.get('api_key', None)  # we cache to reduce access to ssm (because of throttling exception)
    host = local_cache.get('host', None)  # we cache to reduce access to ssm (because of throttling exception)
    if not encoded_key or not host:
        host, encoded_key = get_elastic_credentials()

    try:
        _send_data(host, encoded_key, elastic_data)
    except AuthenticationException as auth_exc:
        if getattr(auth_exc, "status_code", None) == 401:
            log.warning("401 AuthenticationException sending to Elastic. Refreshing credentials and retrying.")
            host, encoded_key = get_elastic_credentials()
            _send_data(host, encoded_key, elastic_data)
        else:
            raise
    except Exception as e:
        log.error(f"Exception sending data to Elastic: {e}. Clearing cached client and retrying.")
        local_cache.pop("Elasticsearch", None)
        host, encoded_key = get_elastic_credentials()
        _send_data(host, encoded_key, elastic_data)
        raise


def _send_data(host, encoded_key, elastic_data):
    es = local_cache.get('Elasticsearch', None)
    if es is None:
        es = Elasticsearch(host, api_key=encoded_key)
        local_cache['Elasticsearch'] = es
    try:
        for success, info in streaming_bulk(es, elastic_data.values(), request_timeout=180):
            log.info(f"The result from calling was success: {success}, info: {info}")
            if not success:
                log.warning(f"Failed to index document: {info}")
    except BulkIndexError as e:
        # These are failures due to mapping inconsistencies in elastic.
        # For example, the field might be defined as a "long" in elastic, but we are getting an object from AWS
        # While these are real issues, we suppress the error because it will keep failing on retry.
        # We still want to keep the retry for other errors like connectivity issues
        log.error(f'Failed to ingest due to mapping error: {e}')


def _get_secret_value(key, secret):
    return secret.get(key, "").strip().rstrip('"').lstrip('"')
