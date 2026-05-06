from dataclasses import dataclass, fields, field
from typing import Optional

from hs_aws_monitoring.cw_auto_alarms.namespace_config import get_namespace_config

DIMENSION_MAP = {ns_config['name']: ns_config['dimension'] for ns_config in get_namespace_config()}


@dataclass
class AlarmData:
    """ Data that is needed to create an alerm """
    namespace: str  # 'AWS/EC2'
    resource_identifier: str
    resource_name: str
    statistic: str
    metric_name: str
    comparison_operator: str
    threshold: str
    datapoints_to_alarm: str  # datapoints_to_alarm is how many checks have to fail within the evaluation_periods
    evaluation_periods: str  # evaluation_periods is how many checks we look at in a row
    period: str  # period is how often to check
    software_owner: str
    app_code: str
    amdb_number: str
    sdp_priority: str
    display_name: str
    maintenance_window: bool
    monitored: bool
    metric_math: Optional[dict] = field(compare=False, default=None)  # Can compare metric_name instead

    @property
    def dimension(self):
        return DIMENSION_MAP[self.namespace]

    @property
    def alarm_name(self):
        """
        We include the resource identifier because if the alarm name is not unique it will update the other alarm.
        For example with EC2 instances created by an ASGs, we are not able to create unique Name tags for the underlying EC2 instances.

        For some use cases the logic in the alarm_name_tag includes the resource_identifier, see the alarm_name_tag property, So the name ends up as
        'AUTO-ALARM <Some string that has resource_identifier and other stuff> (<resource_identifier>)
        """
        if self.resource_identifier in self.alarm_name_tag:
            return f'AUTO-ALARM {self.alarm_name_tag}'
        return f'AUTO-ALARM {self.alarm_name_tag} ({self.resource_identifier})'

    @property
    def alarm_name_tag(self):
        """ Without the auto alarm to keep it shorter/cleaner """
        if self.display_name:
            resource_name = self.resource_name or self.resource_identifier
            return f'{self.display_name} for {resource_name}'
        return f'{self.resource_identifier} ({self.namespace}) {self.statistic}-{self.metric_name} is {self.comparison_operator} {self.threshold} ({self.datapoints_to_alarm}/{self.evaluation_periods} periods of {self.period}s)'

    @classmethod
    def create_from_alarm_tags(cls, tags):
        field_2_tag = {f.name: f'hs:alarm:{f.name}' for f in fields(AlarmData)}
        # Custom field mappings
        field_2_tag['sdp_priority'] = 'hs:app:sdp-priority'
        field_2_tag['maintenance_window'] = 'hs:app:maintenance-window'
        field_2_tag['app_code'] = 'hs:std:app-code'
        field_2_tag['software_owner'] = 'hs:std:svc-software-owner'
        field_2_tag['monitored'] = 'hs:app:monitored'
        field_2_tag['amdb_number'] = 'hs:app:amdb'

        values = {field_name: tags.get(tag_name) for field_name, tag_name in field_2_tag.items()}

        # Custom value parsing
        values['maintenance_window'] = str_to_bool(values.get('maintenance_window', False))
        values['monitored'] = str_to_bool(values.get('monitored', False))
        values['amdb_number'] = values['amdb_number'].split('_')[-1] if values.get('amdb_number') else ''

        return AlarmData(**values)

    def get_alarm_json(self):
        """ The actual JSON used to created the alarm"""
        dimensions = [{'Name': self.dimension, 'Value': self.resource_identifier}]

        tags = [
            # Tags that are set using pre-existing or external naming conventions
            {'Key': 'Name', 'Value': self.alarm_name_tag},
            {'Key': 'hs:app:monitored', 'Value': bool_to_str(self.monitored)},
            {'Key': 'hs:app:auto-generated', 'Value': 'true'},
            {'Key': 'hs:app:amdb', 'Value': f'sdpmt_{self.amdb_number}'},
            {'Key': 'hs:app:sdp-priority', 'Value': self.sdp_priority},
            {'Key': 'hs:app:maintenance-window', 'Value': bool_to_str(self.maintenance_window)},
            {'Key': 'hs:std:svc-software-owner', 'Value': self.software_owner},
            {'Key': 'hs:std:app-code', 'Value': self.app_code},

            # Tags that are only used for lambda function
            {'Key': 'hs:alarm:namespace', 'Value': self.namespace},
            {'Key': 'hs:alarm:resource_identifier', 'Value': self.resource_identifier},
            {'Key': 'hs:alarm:resource_name', 'Value': self.resource_name},
            {'Key': 'hs:alarm:statistic', 'Value': self.statistic},
            {'Key': 'hs:alarm:metric_name', 'Value': self.metric_name},
            {'Key': 'hs:alarm:comparison_operator', 'Value': self.comparison_operator},
            {'Key': 'hs:alarm:threshold', 'Value': self.threshold},
            {'Key': 'hs:alarm:datapoints_to_alarm', 'Value': self.datapoints_to_alarm},
            {'Key': 'hs:alarm:evaluation_periods', 'Value': self.evaluation_periods},
            {'Key': 'hs:alarm:period', 'Value': self.period},
            {'Key': 'hs:alarm:display_name', 'Value': self.display_name},
        ]

        tags = [tag for tag in tags if tag['Value'] is not None]

        result = {
            'AlarmName': self.alarm_name,
            'AlarmDescription': 'Created by cloudwatch-auto-alarms',
            'DatapointsToAlarm': int(self.datapoints_to_alarm),
            'EvaluationPeriods': int(self.evaluation_periods),
            'ComparisonOperator': self.comparison_operator,
            'Threshold': float(self.threshold),
            'Tags': tags}

        if self.metric_math:
            metrics = []
            operand_names = []
            for operand_index, operand in enumerate(self.metric_math['operands']):
                operand_name = f'm{operand_index + 1}'
                operand_names.append(operand_name)
                metrics.append({
                    'Id': operand_name,
                    'MetricStat': {
                        'Metric': {
                            'MetricName': operand,
                            'Namespace': self.namespace,
                            'Dimensions': dimensions
                        },
                        'Stat': self.statistic,
                        'Period': int(self.period),
                    },
                    'ReturnData': False
                })

            if self.metric_math["operator"] == "SUM":
                expression = f'{self.metric_math["operator"]}([{",".join(operand_names)}])'
            elif self.metric_math["operator"] == "SUBTRACTION":
                expression = f'{"-".join(operand_names)}'

            if self.metric_math.get('divisor'):
                expression = f'{expression}/{self.metric_math["divisor"]}'

            metrics.append({'Id': 'e1',
                            'Expression': expression,
                            'ReturnData': True})
            result['Metrics'] = metrics
        else:
            # Simple format for metrics that will also show up with resource (e.g. on the EC2 Console for EC2 Alarms)
            result['Namespace'] = self.namespace
            result['MetricName'] = self.metric_name
            result['Dimensions'] = dimensions
            result['Statistic'] = self.statistic
            result['Period'] = int(self.period)

        return result


def bool_to_str(value):
    return str(bool(value)).lower()


def str_to_bool(value):
    return str(value).lower() == 'true'
