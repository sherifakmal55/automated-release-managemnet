#!/bin/bash

set -euo pipefail

# Inputs
JIRA_TICKET="$1"
PACKAGE="$2"
S3_PATH="$3"
DB_URL="$4"
DB_USER="$5"
DB_PASS="$6"
JAVA_PATH="$7"
TASK_IDENTIFIER="$8"  # TLMView1 or TLMView2 (to identify the task)

TASK_TYPE="TLMView"
TASK_ID="${TASK_IDENTIFIER}"

# Prepare working directory
WORK_DIR="/tmp/${JIRA_TICKET}/deploy/${TASK_TYPE}/${TASK_ID}"
mkdir -p "$WORK_DIR"

# Local path for config-manager.jar
CONFIG_JAR_PATH="/tmp/${JIRA_TICKET}/utilities/${TASK_TYPE}/config-manager.jar"

# Local package path
PACKAGE_PATH="/tmp/${JIRA_TICKET}/client-packages/${JIRA_TICKET}/deploy/${PACKAGE}"

# Timestamp for unique log files
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE="${WORK_DIR}/deploy_${TASK_ID}_${TIMESTAMP}.log"
CONFIG_MANAGER_LOG="${WORK_DIR}/config-manager.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

cd "$WORK_DIR"

log "=== Starting TLMView deployment for task $TASK_ID with package: $PACKAGE ==="
log "Working directory: $WORK_DIR"
log "Package file: $PACKAGE_PATH"

# Check if the config-manager.jar exists locally
if [[ ! -f "$CONFIG_JAR_PATH" ]]; then
    log "ERROR: config-manager.jar does not exist: $CONFIG_JAR_PATH"
    exit 1
fi
log "Found config-manager.jar at: $CONFIG_JAR_PATH"

# Check if the package file exists locally
if [[ ! -f "$PACKAGE_PATH" ]]; then
    log "ERROR: Package file does not exist: $PACKAGE_PATH"
    exit 1
fi
log "Found package file at: $PACKAGE_PATH"

export JAVA_HOME="${JAVA_PATH}"
export PATH="$JAVA_HOME/bin:$PATH"

#if /STL/Java/jdk-17.0.7/bin/java \

# Run the Java import command
log "Executing Java command for import..."
if java \
  -Dspring.datasource.url="$DB_URL" \
  -Dspring.datasource.username="$DB_USER" \
  -Dspring.datasource.password="$DB_PASS" \
  -DpackagingType=ALL \
  -Dspring.datasource.driver-class-name=oracle.jdbc.driver.OracleDriver \
  -Dmode=IMPORT \
  -Dfile="$PACKAGE_PATH" \
  -jar "$CONFIG_JAR_PATH" >> "$LOG_FILE" 2>&1; then

    log "TLMView import for $TASK_ID completed successfully."

else
    log "ERROR: TLMView import for $TASK_ID failed."
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

log "=== TLMView deployment for task $TASK_ID completed successfully ==="