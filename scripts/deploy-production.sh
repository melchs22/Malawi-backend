#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

command -v rsync >/dev/null || { echo "rsync is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

if [ "${DEPLOY_LOCAL:-0}" != "1" ]; then
  : "${DEPLOY_HOST:?Set DEPLOY_HOST to the production server host}"
  : "${DEPLOY_USER:?Set DEPLOY_USER to the SSH deployment account}"
  command -v ssh >/dev/null || { echo "ssh is required" >&2; exit 1; }
fi

DEPLOY_REF="${DEPLOY_REF:-$(git -C "$ROOT_DIR" rev-parse --short HEAD)}"
if [[ ! "$DEPLOY_REF" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "DEPLOY_REF contains unsupported characters" >&2
  exit 1
fi

python3 -m compileall -q \
  "$ROOT_DIR/config" "$ROOT_DIR/garages" "$ROOT_DIR/users"

REMOTE_DIR="/opt/smart-mobility/backend"
SYNC_OPTIONS=(
  --include='/.env.example' \
  --exclude='/.env*' \
  --exclude='**/.env*' \
  --exclude='/.git/' \
  --exclude='**/.git/' \
  --exclude='/media/' \
  --exclude='/staticfiles/' \
  --exclude='**/__pycache__/' \
  --exclude='/.pytest_cache/' \
  --exclude='/.venv/' \
  --exclude='/venv/' \
  --exclude='**/.dart_tool/' \
  --exclude='**/.pub-cache/' \
  --exclude='**/.pub/' \
  --exclude='**/build/' \
  --exclude='**/Pods/' \
  --exclude='**/DerivedData/' \
  --exclude='**/.flutter-plugins' \
  --exclude='**/.flutter-plugins-dependencies' \
  --exclude='*.pyc' \
  --exclude='*.log' \
  --exclude='.DS_Store' \
  --exclude='._*'
)

if [ "${DEPLOY_LOCAL:-0}" = "1" ]; then
  rsync -az --delete-delay "${SYNC_OPTIONS[@]}" \
    "$ROOT_DIR/" "${REMOTE_DIR}/"
  DEPLOY_REF="$DEPLOY_REF" bash "$ROOT_DIR/scripts/deploy-server.sh"
else
  REMOTE="${DEPLOY_USER}@${DEPLOY_HOST}"
  rsync -az --delete-delay "${SYNC_OPTIONS[@]}" \
    -e "ssh -o BatchMode=yes -o StrictHostKeyChecking=yes" \
    "$ROOT_DIR/" "${REMOTE}:${REMOTE_DIR}/"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$REMOTE" \
    "DEPLOY_REF='$DEPLOY_REF' bash -s" < "$ROOT_DIR/scripts/deploy-server.sh"
fi
