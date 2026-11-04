#!/usr/bin/env bash
# Runs on the GitHub Actions runner, not inside Terraform.
set -euo pipefail
: "${EC2_HOST:?Set the EC2_HOST repository variable}"
: "${EC2_USER:=ec2-user}"
: "${GITHUB_REPOSITORY:?GitHub supplies owner/repository}"
: "${GH_READ_TOKEN:?GitHub supplies a read-only workflow token}"
[[ "$EC2_HOST" =~ ^[a-zA-Z0-9.-]+$ ]]
[[ "$EC2_USER" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]
[[ "$GITHUB_REPOSITORY" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]
REPO_URL="https://github.com/$GITHUB_REPOSITORY.git"

# Pass the short-lived token over encrypted stdin, never as a command argument
# or a persistent Git remote URL. EC2's default ec2-user has passwordless sudo.
{
  printf '%s\n' "$GH_READ_TOKEN"
  cat scripts/deploy-remote.sh
} | ssh -i "$HOME/.ssh/retrograde_deploy" \
  -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
  -o ConnectTimeout=20 -o ServerAliveInterval=30 -o ServerAliveCountMax=4 \
  "$EC2_USER@$EC2_HOST" \
  "sudo -n bash -c 'IFS= read -r GH_READ_TOKEN; export GH_READ_TOKEN; bash -s -- \"\$1\"' -- '$REPO_URL'"
