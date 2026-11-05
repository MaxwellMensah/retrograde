#!/usr/bin/env python3
"""Resolve one running EC2 host and its attached application security group."""
import ipaddress
import json
import os
import re
import subprocess
import sys


def resolve(instances, host, group_name):
    candidates = [i for i in instances if i.get('State', {}).get('Name') == 'running'
                  and host in (i.get('PublicIpAddress'), i.get('PublicDnsName'))]
    if len(candidates) != 1:
        raise ValueError('EC2_HOST must identify exactly one running EC2 public IP/DNS in this account/region. Update it after a rebuild.')
    instance = candidates[0]
    groups = [g for g in instance.get('SecurityGroups', []) if g.get('GroupName') == group_name]
    if len(groups) != 1:
        raise ValueError('Expected exactly one attached application group named ' + group_name)
    group_id = groups[0]['GroupId']
    if not re.fullmatch(r'sg-[0-9a-f]+', group_id):
        raise ValueError('Invalid discovered group ID')
    if not instance.get('KeyName'):
        raise ValueError('Instance has no EC2 key pair. Configure ssh_key_name and replace/refresh the instance before SSH deployment.')
    return instance['InstanceId'], group_id


def main():
    host = os.environ['EC2_HOST'].strip()
    if not re.fullmatch(r'[A-Za-z0-9.-]+', host):
        raise ValueError('EC2_HOST must be a public IP or EC2 public DNS name, without a URL scheme')
    try:
        ipaddress.IPv4Address(host)
        field = 'ip-address'
    except ValueError:
        field = 'dns-name'
    result = subprocess.run([
        'aws', 'ec2', 'describe-instances', '--filters',
        'Name=instance-state-name,Values=running',
        'Name=' + field + ',Values=' + host, '--output', 'json'
    ], check=True, capture_output=True, text=True)
    instances = [i for r in json.loads(result.stdout)['Reservations'] for i in r['Instances']]
    instance_id, group_id = resolve(instances, host, os.environ['EC2_APP_SG_NAME'])
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        output.write('instance_id=' + instance_id + '\nsg_id=' + group_id + '\n')
    print('Verified deployment target:', instance_id, 'attached application group:', group_id)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError) as error:
        sys.exit('Deployment target check failed: ' + str(error))
