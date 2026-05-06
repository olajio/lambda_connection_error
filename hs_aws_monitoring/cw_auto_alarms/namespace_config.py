import boto3


def get_namespace_config():
    return [
        {
            'name': 'AWS/EC2',
            'dimension': 'InstanceId',
            'resource_type': 'ec2:instance',
            'tag_filters': [{'Key': 'hs:std:app-code'}],
            'identifier_from_arn_parse_char': '/',
            'resource_finder': get_resources_and_tags
        },
        {
            'name': 'AWS/EBS',
            'dimension': 'VolumeId',
            'resource_type': 'ec2:volume',
            'tag_filters': [{'Key': 'hs:std:app-code', 'Values': ['MSSQL']}],
            'identifier_from_arn_parse_char': '/',
            'resource_finder': get_resources_and_tags
        },
        {
            'name': 'AWS/SQS',
            'dimension': 'QueueName',
            'resource_type': 'sqs:queue',
            'tag_filters': [{'Key': 'hs:app:monitored', 'Values': ['true']}],
            'identifier_from_arn_parse_char': ':',
            'resource_finder': get_resources_and_tags
        },
        {
            'name': 'AWS/Lambda',
            'dimension': 'FunctionName',
            'resource_type': 'lambda:function',
            'tag_filters': [{'Key': 'hs:std:app-code'}],
            'identifier_from_arn_parse_char': ':',
            'resource_finder': get_resources_and_tags
        },
        {
            'name': 'AWS/AutoScaling',
            'dimension': 'AutoScalingGroupName',
            'resource_type': 'autoscaling:autoScalingGroup',
            'tag_filters': [{'Key': 'hs:std:app-code'}],
            'identifier_from_arn_parse_char': '/',
            'resource_finder': get_autoscaling_resources_and_tags
        },
        {
            'name': 'AWS/ElastiCache',
            'dimension': 'CacheClusterId',
            'resource_type': 'elasticache:replicationgroup',
            'tag_filters': [{'Key': 'hs:std:app-code'}],
            'identifier_from_arn_parse_char': ':',
            'resource_finder': get_elasticache_resources_and_tags
        }
    ]


def get_resources_and_tags(resource_type, tag_filters):
    """
    Default implementation to discover resources to create alarms for. Uses tagging API.
    Also used to find the existing alarms.
    """
    tagging = boto3.client('resourcegroupstaggingapi')

    for results in tagging.get_paginator('get_resources').paginate(ResourceTypeFilters=[resource_type],
                                                                   TagFilters=tag_filters):
        for resource_info in results['ResourceTagMappingList']:
            tags = {row['Key']: row['Value'] for row in resource_info['Tags']}
            yield resource_info['ResourceARN'], tags


def get_autoscaling_resources_and_tags(_resource_type, tag_filters):
    asg_client = boto3.client('autoscaling')

    for page in asg_client.get_paginator('describe_auto_scaling_groups').paginate():
        for asg in page['AutoScalingGroups']:
            tags = {tag['Key']: tag['Value'] for tag in asg.get('Tags', {})}
            if _matches_tag_filters(tags, tag_filters):
                yield asg['AutoScalingGroupARN'], tags


def get_elasticache_resources_and_tags(_resource_type, _tag_filters):
    el_client = boto3.client('elasticache')

    response = el_client.describe_cache_clusters()
    for cluster in response['CacheClusters']:
        cluster_arn = cluster.get('ARN', None)
        if cluster_arn:
            tag_res = el_client.list_tags_for_resource(ResourceName=cluster_arn)
            tags = {tag['Key']: tag['Value'] for tag in tag_res.get('TagList', {})}
            yield cluster_arn, tags


def _matches_tag_filters(tags, filters):
    """All filters must match: key present, and if Values given -> tag value ∈ Values."""
    for f in filters:
        key = f['Key']
        if key not in tags:
            return False
        vals = f.get('Values', [])
        if vals and tags.get(key) not in vals:
            return False
    return True
