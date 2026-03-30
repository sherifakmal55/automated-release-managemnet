#!/bin/bash

set -euo pipefail

# Inputs
JIRA_TICKET="$1"
TASK_IDENTIFIER="$2"  # TLMView1 or TLMView2
S3_PATH="$3"
DB_URL="$4"
DB_USER="$5"
DB_PASS="$6"
CREATED_BACKUP_FILE="$7"  # Input file from TLM View backup element in input JSON

TASK_TYPE="TLMView"
TASK_ID="${TASK_IDENTIFIER}"

# Prepare working directory
WORK_DIR="/tmp/Release-Management/${JIRA_TICKET}/rollback/${TASK_TYPE}/${TASK_ID}"
mkdir -p "$WORK_DIR"

# Timestamp for unique log files
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE="${WORK_DIR}/rollback_${TASK_ID}_${TIMESTAMP}.log"
CONFIG_MANAGER_LOG="${WORK_DIR}/config-manager.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

cd "$WORK_DIR"

log "=== Starting TLMView rollback for task $TASK_ID ==="
log "Working directory: $WORK_DIR"

# Use the same CREATED_BACKUP_FILE for consistency
S3_BACKUP_PATH="${S3_PATH}/${JIRA_TICKET}/${TASK_TYPE}/${TASK_ID}/${CREATED_BACKUP_FILE}"
log "Downloading backup from S3: $S3_BACKUP_PATH"

if aws s3 cp "$S3_BACKUP_PATH" "./$CREATED_BACKUP_FILE"; then
    log "Backup file downloaded successfully."
else
    log "ERROR: Failed to download backup from S3."
    exit 1
fi

# The database restore will now be using the backup taken during deployment
log "Restoring backup using the database connection..."
if /STL/Java/jdk-17.0.7/bin/java \
  -Dspring.datasource.url="$DB_URL" \
  -Dspring.datasource.username="$DB_USER" \
  -Dspring.datasource.password="$DB_PASS" \
  -DpackagingType=ALL \
  -Dspring.datasource.driver-class-name=oracle.jdbc.driver.OracleDriver \
  -Dmode=IMPORT \  # The mode will be 'IMPORT', as we are importing the backup
  -Dfile="${WORK_DIR}/${CREATED_BACKUP_FILE}" \  # Full path to the backup file
  -jar "/tmp/Release-Management/${JIRA_TICKET}/utilities/${TASK_TYPE}/config-manager.jar" >> "$LOG_FILE" 2>&1; then
    log "TLMView restore for $TASK_ID completed successfully."
else
    log "ERROR: TLMView restore for $TASK_ID failed."
    exit 1
fi

# Upload all logs to S3
S3_LOG_PATH="${S3_PATH}/${JIRA_TICKET}/${TASK_TYPE}/${TASK_ID}/${TASK_ID}-rollback_${TIMESTAMP}.log"
log "Uploading rollback log file to S3: $S3_LOG_PATH"

if aws s3 cp "$LOG_FILE" "$S3_LOG_PATH"; then
    log "S3 upload successful for log file $TASK_ID."
else
    log "ERROR: Failed to upload log file $TASK_ID to S3."
    exit 1
fi

# Upload config-manager.log to S3 (if it exists)
if [[ -f "$CONFIG_MANAGER_LOG" ]]; then
    S3_CONFIG_MANAGER_LOG_PATH="${S3_PATH}/${JIRA_TICKET}/${TASK_TYPE}/${TASK_ID}/config-manager.log"
    log "Uploading config-manager.log to S3: $S3_CONFIG_MANAGER_LOG_PATH"
    
    if aws s3 cp "$CONFIG_MANAGER_LOG" "$S3_CONFIG_MANAGER_LOG_PATH"; then
        log "S3 upload successful for config-manager.log."
    else
        log "ERROR: Failed to upload config-manager.log to S3."
        exit 1
    fi
else
    log "No config-manager.log found for $TASK_ID."
fi

log "=== TLMView rollback for task $TASK_ID completed successfully ==="