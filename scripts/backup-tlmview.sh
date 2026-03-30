#!/bin/bash

set -euo pipefail

# Inputs
JIRA_TICKET="$1"
BLUEPRINT_FILE="$2"
CREATED_BACKUP_FILE="$3"
S3_PATH="$4"
DB_URL="$5"
DB_USER="$6"
DB_PASS="$7"
JAVA_PATH="$8"
TASK_IDENTIFIER="$9"  # TLMView1 or TLMView2 (to identify the task)

TASK_TYPE="TLMView"
TASK_ID="${TASK_IDENTIFIER}"

# Prepare working directory
WORK_DIR="/tmp/${JIRA_TICKET}/backup/${TASK_TYPE}/${TASK_ID}"
mkdir -p "$WORK_DIR"

# Local path for config-manager.jar
CONFIG_JAR_PATH="/tmp/${JIRA_TICKET}/utilities/${TASK_TYPE}/config-manager.jar"

# Local blueprint path
BLUEPRINT_PATH="/tmp/${JIRA_TICKET}/client-packages/${JIRA_TICKET}/backup/${BLUEPRINT_FILE}"

# Timestamp for unique log files
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE="${WORK_DIR}/backup_${TASK_ID}_${TIMESTAMP}.log"
CONFIG_MANAGER_LOG="${WORK_DIR}/config-manager.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

cd "$WORK_DIR"

log "=== Starting TLMView backup for task $TASK_ID with blueprint: $BLUEPRINT_FILE ==="
log "Working directory: $WORK_DIR"
log "Output file: $CREATED_BACKUP_FILE"

# Check if the config-manager.jar exists locally
if [[ ! -f "$CONFIG_JAR_PATH" ]]; then
    log "ERROR: config-manager.jar does not exist: $CONFIG_JAR_PATH"
    exit 1
fi
log "Found config-manager.jar at: $CONFIG_JAR_PATH"

# Check if the blueprint file exists locally
if [[ ! -f "$BLUEPRINT_PATH" ]]; then
    log "ERROR: Blueprint file does not exist: $BLUEPRINT_PATH"
    exit 1
fi
log "Found blueprint file at: $BLUEPRINT_PATH"

# Run the Java export command
# if /STL/Java/jdk-17.0.7/bin/java \
# Run the Java export command for WBC
export JAVA_HOME="${JAVA_PATH}"
export PATH="$JAVA_HOME/bin:$PATH"

#if /STL/Java/jdk-17.0.7/bin/java \
if java \
  -Dspring.datasource.url="$DB_URL" \
  -Dspring.datasource.username="$DB_USER" \
  -Dspring.datasource.password="$DB_PASS" \
  -DpackagingType=ALL \
  -Dspring.datasource.driver-class-name=oracle.jdbc.driver.OracleDriver \
  -Dmode=EXPORT \
  -Dblueprint="$BLUEPRINT_PATH" \
  -Dfile="./$CREATED_BACKUP_FILE" \
  -jar "$CONFIG_JAR_PATH" >> "$LOG_FILE" 2>&1; then

    log "TLMView export for $TASK_ID completed successfully."

else
    log "ERROR: TLMView export for $TASK_ID failed."
    exit 1
fi

# Upload JSON to S3 (using folder based on TASK_ID)
S3_BACKUP_PATH="${S3_PATH}/${JIRA_TICKET}/${TASK_TYPE}/${TASK_ID}/${CREATED_BACKUP_FILE}"
log "Uploading backup file to S3: $S3_BACKUP_PATH"

if aws s3 cp "$CREATED_BACKUP_FILE" "$S3_BACKUP_PATH"; then
    log "S3 upload successful for backup $TASK_ID."
else
    log "ERROR: Failed to upload backup $TASK_ID to S3."
    exit 1
fi

# Upload log file to S3 (using folder based on TASK_ID)
S3_LOG_PATH="${S3_PATH}/${JIRA_TICKET}/${TASK_TYPE}/${TASK_ID}/${TASK_ID}_${TIMESTAMP}.log"
log "Uploading log file to S3: $S3_LOG_PATH"

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

log "=== TLMView backup for task $TASK_ID completed successfully ==="