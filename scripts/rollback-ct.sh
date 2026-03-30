#!/bin/bash

set -euo pipefail

# === Inputs ===
JIRA_TICKET="$1"
CTE_FILE="$2"              # The .cte file to import (from backup)
S3_PATH="$3"               # Base S3 path where backup files are stored
DB_URL="$4"
DB_USER="$5"
DB_PASS="$6"
TASK_IDENTIFIER="$7"       # e.g., CTTask1 or CTTask2

TASK_TYPE="ConfigurationTransfer"
TASK_ID="${TASK_IDENTIFIER}"

# === Setup Working Directory ===
WORK_DIR="/tmp/Release-Management/${JIRA_TICKET}/rollback/${TASK_TYPE}/${TASK_ID}"
mkdir -p "$WORK_DIR"

# === Paths ===
CTC_DIR="/tmp/Release-Management/${JIRA_TICKET}/utilities/${TASK_TYPE}"
CTC_BINARY="${CTC_DIR}/CTC"
CTE_LOCAL_PATH="${WORK_DIR}/${CTE_FILE}"  # This will be downloaded from S3
CTC_LOG_FILE="${CTC_DIR}/ConfigurationTransfer.log"

# === Timestamp for Logs ===
TIMESTAMP=$(date +%Y%m%d%H%M%S)
ROLLBACK_LOG_FILE="${WORK_DIR}/config_transfer_rollback_${TASK_ID}_${TIMESTAMP}.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$ROLLBACK_LOG_FILE"
}

cd "$WORK_DIR"

log "=== Starting Configuration Transfer rollback for task $TASK_ID ==="

# === Verify CTC Binary Exists ===
if [[ ! -f "$CTC_BINARY" ]]; then
    log "ERROR: CTC binary not found at: $CTC_BINARY"
    exit 1
fi

# === Set Up Java Environment ===
log "Setting up Java environment..."
export JAVA_HOME="/STL/Java/jdk-17.0.7"
export PATH="$JAVA_HOME/bin:$PATH"

if ! command -v java &> /dev/null; then
    log "ERROR: Java not found after setting JAVA_HOME"
    exit 1
fi

log "Java found at: $(which java)"
log "Java version: $(java -version 2>&1 | head -n 1)"

# === Download .cte file from S3 ===
S3_CTE_PATH="${S3_PATH}/${JIRA_TICKET}/${TASK_TYPE}/${TASK_ID}/${CTE_FILE}"
log "Downloading CTE file from S3: $S3_CTE_PATH"

if aws s3 cp "$S3_CTE_PATH" "$CTE_LOCAL_PATH"; then
    log "CTE file downloaded successfully: $CTE_LOCAL_PATH"
else
    log "ERROR: Failed to download CTE file from S3"
    exit 1
fi

# === Run CTC Import ===
cd "$CTC_DIR"
log "Running CTC import..."

if ./CTC \
    -d"$DB_URL" \
    -u"$DB_USER" \
    -w"$DB_PASS" \
    -aimport \
    -i"$CTE_LOCAL_PATH"; then
    log "CTC import (rollback) completed successfully for $TASK_ID."
else
    log "ERROR: CTC import (rollback) failed for $TASK_ID."
    exit 1
fi

# === Upload CTC Log to S3 ===
S3_CTC_LOG_PATH="${S3_PATH}/${JIRA_TICKET}/${TASK_TYPE}/${TASK_ID}/rollback_Configurationtransfer_${TIMESTAMP}.log"
log "Uploading ConfigurationTransfer.log to S3: $S3_CTC_LOG_PATH"

if [[ -f "$CTC_LOG_FILE" ]]; then
    if aws s3 cp "$CTC_LOG_FILE" "$S3_CTC_LOG_PATH"; then
        log "Upload of ConfigurationTransfer.log successful"
    else
        log "ERROR: Failed to upload ConfigurationTransfer.log to S3"
        exit 1
    fi
else
    log "ERROR: ConfigurationTransfer.log not found at $CTC_LOG_FILE"
    exit 1
fi

# === Upload Rollback Log to S3 ===
S3_ROLLBACK_LOG_PATH="${S3_PATH}/${JIRA_TICKET}/${TASK_TYPE}/${TASK_ID}/rollback_wrapper_${TASK_ID}_${TIMESTAMP}.log"
log "Uploading rollback log to S3: $S3_ROLLBACK_LOG_PATH"

if aws s3 cp "$ROLLBACK_LOG_FILE" "$S3_ROLLBACK_LOG_PATH"; then
    log "Upload of rollback log successful"
else
    log "ERROR: Failed to upload rollback log to S3"
    exit 1
fi

log "=== Configuration Transfer rollback for task $TASK_ID completed successfully ==="