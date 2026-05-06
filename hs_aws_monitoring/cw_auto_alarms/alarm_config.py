import re
import logging
import boto3
import os
import yaml

from hs_aws_monitoring.cw_auto_alarms.custom_calc import CustomCalc

log = logging.getLogger('alarm-config')


def get_s3_alarm_config():
    s3 = boto3.resource('s3')
    environment = os.getenv('AWS_ENVIRONMENT')
    key = f'configs/{environment}/monitoring/cloudwatch_auto_alarms.yaml'
    log.info('Loading config from %s', key)
    s3_object = s3.Object('hedgeserv-shd-ci-us-east-2-s3-configs', key)
    alarm_config = yaml.full_load(s3_object.get()['Body'])
    return AlarmConfigContainer(alarm_config)


def get_local_alarm_config():
    # used when testing this entire thing locally.
    namespace_file_path = r"C:\Dev\hs_aws_applications_configs\configs\rnd\monitoring\cloudwatch_auto_alarms.yaml"
    with open(namespace_file_path, "r") as namespace_file_fp:
        alarm_config = yaml.full_load(namespace_file_fp)

    return AlarmConfigContainer(alarm_config)


class AlarmConfigContainer:
    """
    The configuration for all the alarms.
    """

    def __init__(self, config):
        self.config = config

    @property
    def alarm_configs(self):
        return [AlarmConfig(c) for c in self.config['alarms']]

    @property
    def create_alarms(self):
        return self.config.get('config', {}).get('create_alarms', True)

    @property
    def create_tickets(self):
        return self.config.get('config', {}).get('create_tickets', True)

    @property
    def maintenance_window(self):
        """
        If True then we do NOT generate tickets during the weekend blackout window for alarms.
        Ideally we don't want to set this, we would prefer to know as soon as there is some problem.
        Unfortunately some services (like SQL Server or anything that depends on it)
        are not stable during the weekend (e.g. because of DB reorgs).
        This prevents generating false alarms and creating ticket fatigue for those services.
        """
        return self.config.get('config', {}).get('maintenance_window', False)


class AlarmConfig:
    """
    The configuration for a single alarm.
    This configuration is used to find all the matching resources and create a CloudWatch alarm per resources.
    """

    def __init__(self, config):
        self.config = config

    def is_included(self, tags):
        for tag_name, included_values in self.included_tags.items():
            tag_value = tags.get(tag_name)
            if not tag_value or not re.match(included_values, tag_value):
                return False

        for tag_name, excluded_values in self.excluded_tags.items():
            tag_value = tags.get(tag_name)
            if tag_value and re.match(excluded_values, tag_value):
                return False

        return True

    @property
    def amdb_number(self):
        return str(self.config['amdb_number'])

    @property
    def sdp_priority(self):
        return str(self.config.get('sdp_priority', '3 - Moderate'))

    @property
    def namespace(self):
        return self.config['namespace']

    def get_threshold(self, tags):
        threshold = str(self.config['threshold'])
        if not threshold.startswith('CUSTOM:'):
            return threshold
        return getattr(CustomCalc, threshold.rsplit(':', maxsplit=1)[-1])(tags, self.threshold_tag_name,
                                                                          self.threshold_percent)

    @property
    def threshold_tag_name(self):
        return self.config.get('threshold_tag_name', 'hs:app:iops')

    @property
    def threshold_percent(self):
        return self.config.get('threshold_percent', 90)

    @property
    def comparison_operator(self):
        return self.config.get('comparison_operator', 'GreaterThanThreshold')

    @property
    def metric_name(self):
        if self.metric_math:
            # This is converted to a AWS Tag so we are limited with what characters we can use
            return f'{self.metric_math["operator"]}-{"+".join(self.metric_math["operands"])}'

        return self.config['metric_name']

    @property
    def metric_math(self):
        return self.config.get('metric_math')

    @property
    def statistic(self):
        return self.config.get('statistic', 'Average')

    @property
    def period(self):
        return str(self.config.get('period', 60))

    @property
    def datapoints_to_alarm(self):
        return str(self.config.get('datapoints_to_alarm', 1))

    @property
    def evaluation_periods(self):
        return str(self.config.get('evaluation_periods', self.datapoints_to_alarm))

    @property
    def included_tags(self):
        return self.config.get('included_tags', {})

    @property
    def excluded_tags(self):
        return self.config.get('excluded_tags', {})

    @property
    def display_name(self):
        display_name = self.config.get('display_name')
        self.validate_display_name(display_name)
        return display_name

    def validate_display_name(self, display_name):
        pattern = r'[^\w\.\:/=\+\-@ ]'

        if re.search(pattern, display_name):
            invalid_chars = re.findall(pattern, display_name)
            raise ValueError(f"The dispay_name contains the following invalid charachter(s): '{invalid_chars}'. "
                             f"Actual display_name is: '{display_name}'. "
                             f"Please update the display_name in the config and try again. "
                             f"Valid Characters are UTF-8 chars plus '_ . : / = + - @ <space>'. ")
        return True

    @property
    def maintenance_window(self):
        return self.config.get('maintenance_window')

    @property
    def create_tickets(self):
        return self.config.get('create_tickets', True)
