#!/usr/bin/env bash
# Amazon Linux 2023. Run as root after Terraform has created the log group/IAM policy.
set -euo pipefail
LOG_GROUP=${1:?Usage: sudo bash install-logging.sh LOG_GROUP AWS_REGION}
LOG_REGION=${2:?Supply the deployment region}
test "$(id -u)" -eq 0
systemctl cat retrograde.service >/dev/null
# Fail before modifying the service if its expected runtime identity is missing.
id retrograde >/dev/null
dnf install -y amazon-cloudwatch-agent logrotate
install -d -o retrograde -g retrograde -m 0750 /var/log/retrograde
touch /var/log/retrograde/application.log
chown retrograde:retrograde /var/log/retrograde/application.log
chmod 0640 /var/log/retrograde/application.log
install -d -m 0755 /etc/systemd/system/retrograde.service.d
# Preserve the deployment script's override.conf and ExecStart.
cat > /etc/systemd/system/retrograde.service.d/90-cloudwatch-logging.conf <<'SERVICE'
[Service]
StandardOutput=append:/var/log/retrograde/application.log
StandardError=append:/var/log/retrograde/application.log
Environment=PYTHONUNBUFFERED=1
SERVICE
cat > /etc/logrotate.d/retrograde <<'ROTATE'
/var/log/retrograde/application.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su retrograde retrograde
}
ROTATE
# JSON encoding avoids quoting/injection problems in group names.
python3 - "$LOG_GROUP" "$LOG_REGION" <<'PY'
import json,sys
config={"agent":{"region":sys.argv[2],"run_as_user":"root"},
 "logs":{"force_flush_interval":5,"logs_collected":{"files":{"collect_list":[
 {"file_path":"/var/log/retrograde/application.log","log_group_name":sys.argv[1],"log_stream_name":"{instance_id}/application"},
 {"file_path":"/var/log/nginx/access.log","log_group_name":sys.argv[1],"log_stream_name":"{instance_id}/nginx-access"},
 {"file_path":"/var/log/nginx/error.log","log_group_name":sys.argv[1],"log_stream_name":"{instance_id}/nginx-error"}
 ]}}}}
with open('/opt/aws/amazon-cloudwatch-agent/etc/retrograde.json','w') as f:
 json.dump(config,f,indent=2)
PY
systemctl daemon-reload
systemctl restart retrograde
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/retrograde.json -s
systemctl enable amazon-cloudwatch-agent
systemctl is-active retrograde amazon-cloudwatch-agent
curl --fail --silent --show-error --retry 5 --retry-connrefused http://127.0.0.1:8000/health
printf '\nLogging configured. Verify a fresh application event from CloudWatch; service status alone is not proof.\n'
