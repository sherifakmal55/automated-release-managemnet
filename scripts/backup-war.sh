#!/usr/bin/env bash
# Simplified WAR backup script for WildFly/JBoss.
# All key variables are passed as inputs — no pre-export or client logic.
#
# Usage:
#   bash backup-war.sh <APP_NAME> <JIRA_ID> <S3_UPLOAD_PATH> [BACKUP_DIR] <JBOSS_HOME> <JAVA_PATH> <MGMT_PORT>
#
set -euo pipefail

# ---------- collect inputs ----------
APP_NAME="${1:-}"
JIRA_ID="${2:-}"
S3_UPLOAD_PATH="${3:-}"
JBOSS_HOME="${4:-}"
JAVA_PATH="${5:-}"
MGMT_PORT="${6:-}"
JBOSS_USER="${7:-}"
CONTROLLER_HOST="${CONTROLLER_HOST:-127.0.0.1}"
BACKUP_DIR="/tmp/backups-war"

# ---------- sanity checks ----------
if [[ -z "$APP_NAME" || -z "$JIRA_ID" || -z "$S3_UPLOAD_PATH" || -z "$JBOSS_HOME" || -z "$JAVA_PATH" || -z "$MGMT_PORT" ]]; then
  echo "❌ Usage: bash backup-war.sh <APP_NAME> <JIRA_ID> <S3_UPLOAD_PATH> [BACKUP_DIR] <JBOSS_HOME> <JAVA_PATH> <MGMT_PORT>"
  exit 64
fi

CLI="${JBOSS_HOME%/}/bin/jboss-cli.sh"

# ---------- prechecks ----------
if [[ ! -x "$CLI" ]]; then
  echo "❌ jboss-cli.sh not found or not executable at: $CLI"
  exit 1
fi

if ! command -v aws >/dev/null 2>&1 && [[ -x /usr/local/bin/aws ]]; then
  PATH="/usr/local/bin:${PATH}"
fi
if ! command -v aws >/dev/null 2>&1; then
  echo "❌ aws CLI not found in PATH"
  exit 2
fi

# ---------- info summary ----------
echo "📦 App:        $APP_NAME"
echo "🗃 Jira:       $JIRA_ID"
echo "🪣 S3 path:    $S3_UPLOAD_PATH"
echo "📁 Backup dir: $BACKUP_DIR"
echo "🔧 JBOSS_HOME: $JBOSS_HOME"
echo "☕ JAVA_PATH:  $JAVA_PATH"
echo "🔌 MGMT_PORT:  $MGMT_PORT"
echo "🔌 JBOSS_USER:  $JBOSS_USER"
echo "🔗 Controller: ${CONTROLLER_HOST}:${MGMT_PORT}"

# ---------- helper to run CLI ----------
jboss_cli_cmd() {
  local cmd="$1"
  su - "${JBOSS_USER}" -c "export JAVA_HOME='${JAVA_PATH}'; export PATH=\"\$JAVA_HOME/bin:\$PATH\"; \"${CLI}\" --connect --controller=${CONTROLLER_HOST}:${MGMT_PORT} --commands=\"${cmd}\""
}

# ---------- check deployment ----------
echo "🔎 Checking deployment status for: ${APP_NAME}"
ENABLED_RAW=$(jboss_cli_cmd "/deployment=${APP_NAME}:read-attribute(name=enabled)" || true)
ENABLED=$(echo "$ENABLED_RAW" | grep -oE '\b(true|false)\b' | head -n1 || true)

if [[ "$ENABLED" != "true" ]]; then
  echo "❌ ${APP_NAME} is not enabled or not found"
  echo "$ENABLED_RAW"
  exit 3
fi
echo "✅ ${APP_NAME} is deployed and enabled"

# ---------- find data-dir ----------
DATA_DIR_RAW=$(jboss_cli_cmd "/core-service=server-environment:read-attribute(name=data-dir)" )
DATA_DIR=$(echo "$DATA_DIR_RAW" | sed -n 's/.*"result" => "\([^"]*\)".*/\1/p')
if [[ -z "$DATA_DIR" ]]; then
  echo "❌ Failed to read data-dir"
  echo "$DATA_DIR_RAW"
  exit 4
fi
echo "📁 data-dir: $DATA_DIR"

# ---------- get content hash ----------
CONTENT_RAW=$(jboss_cli_cmd "/deployment=${APP_NAME}:read-attribute(name=content)" )
HASH=$(echo "$CONTENT_RAW" | grep -o '0x[0-9A-Fa-f]\+' | sed 's/^0x//' | tr -d '\n')
if [[ -z "$HASH" ]]; then
  echo "❌ Could not extract content hash"
  echo "$CONTENT_RAW"
  exit 5
fi

AA="${HASH:0:2}"
REST="${HASH:2}"
CONTENT_FILE="${DATA_DIR%/}/content/${AA}/${REST}/content"

echo "🧩 Hash: $HASH"
echo "📄 Content file: $CONTENT_FILE"

if [[ ! -f "$CONTENT_FILE" ]]; then
  echo "❌ WAR content file not found: $CONTENT_FILE"
  exit 6
fi

# ---------- create backup ----------
mkdir -p "$BACKUP_DIR"
OUT="${BACKUP_DIR%/}/${APP_NAME%.war}_${JIRA_ID}.war"
cp -f "$CONTENT_FILE" "$OUT"
echo "✅ Backup created: $OUT"

# ---------- upload to S3 ----------
S3_FOLDER="${S3_UPLOAD_PATH%/}"
echo "🚀 Uploading to S3: ${S3_FOLDER}/"
if aws s3 cp "$OUT" "${S3_FOLDER}/"; then
  echo "✅ Upload succeeded: ${S3_FOLDER}/$(basename "$OUT")"
else
  echo "❌ Upload failed"
  exit 7
fi

echo "🎯 WAR backup completed successfully!"