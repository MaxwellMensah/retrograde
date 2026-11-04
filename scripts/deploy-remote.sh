#!/usr/bin/env bash
# Runs as root on EC2, sent over SSH by deploy.sh.
set -euo pipefail
REPO_URL=$1
APP_DIR=/opt/retrograde/source
VENV=/opt/retrograde/.venv311
mkdir -p /opt/retrograde
exec 9>/opt/retrograde/deploy.lock
flock -n 9 || { echo 'Another deployment is running'; exit 1; }

dnf install -y git python3.11 python3.11-pip
ASKPASS=$(mktemp /run/retrograde-askpass.XXXXXX)
trap 'rm -f "$ASKPASS"' EXIT
cat > "$ASKPASS" <<'ASKPASS_SCRIPT'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' 'x-access-token' ;;
  *Password*) printf '%s\n' "$GH_READ_TOKEN" ;;
esac
ASKPASS_SCRIPT
chmod 700 "$ASKPASS"
export GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0
# Do not persist credentials through a system/global credential helper.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=''

if [ ! -d "$APP_DIR/.git" ]; then
  git clone --branch main --single-branch "$REPO_URL" "$APP_DIR"
fi
cd "$APP_DIR"
test "$(git remote get-url origin)" = "$REPO_URL"
test "$(git branch --show-current)" = main
test -z "$(git status --porcelain)" || {
  echo 'Deployment checkout contains local changes; resolve them before deploying.'
  exit 1
}
git pull --ff-only origin main
DEPLOYED_COMMIT=$(git rev-parse HEAD)
unset GH_READ_TOKEN GIT_ASKPASS GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
rm -f "$ASKPASS"

test -s app.py
test -s requirements.txt
test -s templates/index.html
test -d static
test -d images
python3.11 -m venv "$VENV"
"$VENV/bin/python" -m pip install -r requirements.txt
"$VENV/bin/python" -m pip install uvicorn boto3
"$VENV/bin/python" -m pip check
CW_PUBLISH=false "$VENV/bin/python" -B -c 'from app import app; print("Backend import passed")'

# CloudFront serves /static/* and /images/* from S3, so update that origin too.
# Use the bucket from repository configuration without storing a token on disk.
BUCKET_NAME=$(cat /etc/retrograde-assets-bucket)
command -v aws >/dev/null
aws s3 sync static/ "s3://$BUCKET_NAME/static/" --cache-control 'public, max-age=60'
aws s3 sync images/ "s3://$BUCKET_NAME/images/" --cache-control 'public, max-age=60'
# Keep Terraform bootstrap's source objects current for replacement instances.
aws s3 cp app.py "s3://$BUCKET_NAME/app/app.py"
aws s3 cp requirements.txt "s3://$BUCKET_NAME/app/requirements.txt"
aws s3 sync templates/ "s3://$BUCKET_NAME/app/templates/"

mkdir -p /etc/systemd/system/retrograde.service.d
cat > /etc/systemd/system/retrograde.service.d/override.conf <<'SERVICE'
[Service]
WorkingDirectory=/opt/retrograde/source
ExecStart=
ExecStart=/opt/retrograde/.venv311/bin/python -m uvicorn app:app --host 127.0.0.1 --port 8000 --workers 1
Restart=always
RestartSec=5
SERVICE
# Leave the existing service identity/environment from Terraform intact.
chmod -R a+rX "$APP_DIR"
systemctl daemon-reload
systemctl reset-failed retrograde
systemctl restart retrograde

for attempt in $(seq 1 30); do
  if curl -fsS --max-time 5 http://127.0.0.1:8000/health >/dev/null \
    && curl -fsS --max-time 5 http://127.0.0.1/ >/dev/null; then
    echo "Deployment succeeded: $DEPLOYED_COMMIT"
    exit 0
  fi
  sleep 2
done
journalctl -u retrograde -n 60 --no-pager
exit 1
