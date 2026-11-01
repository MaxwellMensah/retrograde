#!/bin/bash
# Runs once when each instance boots. Log: /var/log/retrograde-bootstrap.log
# app bundle: ${code_hash}
set -euxo pipefail
exec > >(tee /var/log/retrograde-bootstrap.log) 2>&1

dnf install -y python3.11 python3.11-pip

mkdir -p /opt/retrograde/templates
aws s3 cp s3://${bucket}/app/app.py /opt/retrograde/app.py --region ${region}
aws s3 cp s3://${bucket}/app/templates/retro_test.html /opt/retrograde/templates/retro_test.html --region ${region}

python3.11 -m pip install --no-cache-dir fastapi uvicorn jinja2 boto3

cat > /etc/retrograde.env <<ENVEOF
ASG_NAME=${asg_name}
SCALE_THRESHOLD=${threshold}
AWS_REGION=${region}
CW_PUBLISH=true
ENVEOF

chown -R ec2-user:ec2-user /opt/retrograde

cat > /etc/systemd/system/retrograde.service <<SVCEOF
[Unit]
Description=Project Retrograde (FastAPI)
After=network-online.target
Wants=network-online.target

[Service]
User=ec2-user
WorkingDirectory=/opt/retrograde
EnvironmentFile=/etc/retrograde.env
ExecStart=/usr/bin/python3.11 -m uvicorn app:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable --now retrograde.service
