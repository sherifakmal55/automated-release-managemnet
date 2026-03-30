#!/bin/bash

set -euo pipefail

# Inputs
JIRA_TICKET="$1"
CTE_FILE="$2"              # Output .cte file to be generated
TEMPLATE_FILE="$3"         # Input template XML file
S3_PATH="$4"
DB_URL="$5"
DB_USER="$6"
DB_PASS="$7"
JAVA_PATH="$8"
TASK_IDENTIFIER="$9"       # e.g., CTTask1 or CTTask2

TASK_TYPE="ConfigurationTransfer"
TASK_ID="${TASK_IDENTIFIER}"

# Prepare working directory
WORK_DIR="/tmp/${JIRA_TICKET}/backup/${TASK_TYPE}/${TASK_ID}"
mkdir -p "$WORK_DIR"

# Paths
CTC_DIR="/tmp/${JIRA_TICKET}/utilities/${TASK_TYPE}"
CTC_BINARY="${CTC_DIR}/CTC"
TEMPLATE_PATH="/tmp/${JIRA_TICKET}/client-packages/${JIRA_TICKET}/backup/${TEMPLATE_FILE}"
CTE_PATH="${WORK_DIR}/${CTE_FILE}"  # Output file will be created here

# Timestamp for unique log files
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE="${WORK_DIR}/config_transfer_${TASK_ID}_${TIMESTAMP}.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

cd "$WORK_DIR"

log "=== Starting Configuration Transfer backup for task $TASK_ID ==="
log "Working directory: $WORK_DIR"
log "Template file: $TEMPLATE_FILE"
log "Output CTE file: $CTE_FILE"

# Check if CTC binary exists
if [[ ! -f "$CTC_BINARY" ]]; then
    log "ERROR: CTC binary not found at: $CTC_BINARY"
    exit 1
fi
log "Found CTC binary at: $CTC_BINARY"

# Check if template file exists
if [[ ! -f "$TEMPLATE_PATH" ]]; then
    log "ERROR: Template file not found at: $TEMPLATE_PATH"
    exit 1
fi
log "Found template file at: $TEMPLATE_PATH"

# Set up Java environment
log "Setting up Java environment for CTC execution..."

# Use hardcoded JAVA_HOME since SSM doesn't load env profiles
# export JAVA_HOME="/STL/Java/jdk1.8.0_351"
# export PATH="$JAVA_HOME/bin:$PATH"

export JAVA_HOME="${JAVA_PATH}"
export PATH="$JAVA_HOME/bin:$PATH"

if ! command -v java &> /dev/null; then
    log "ERROR: Java not found even after setting JAVA_HOME"
    exit 1
fi

log "Java found at: $(which java)"
log "Java version: $(java -version 2>&1 | head -n 1)"

# Change to CTC directory and run the export command
cd "$CTC_DIR"
log "Executing Configuration Transfer export command..."

if ./CTC \
    -d"$DB_URL" \
    -u"$DB_USER" \
    -w"$DB_PASS" \
    -aexport \
    -i"$CTE_PATH" \
    -t"$TEMPLATE_PATH" >> "$LOG_FILE" 2>&1; then
    log "Configuration Transfer export for $TASK_ID completed successfully."
else
    log "ERROR: Configuration Transfer export for $TASK_ID failed."
    exit 1
fi

# Upload CTE file to S3
S3_CTE_PATH="${S3_PATH}/${JIRA_TICKET}/${TASK_TYPE}/${TASK_ID}/${CTE_FILE}"
log "Uploading CTE file to S3: $S3_CTE_PATH"

if aws s3 cp "$CTE_PATH" "$S3_CTE_PATH"; then
    log "S3 upload successful for CTE file $TASK_ID."
else
    log "ERROR: Failed to upload CTE file $TASK_ID to S3."
    exit 1
fi

# Upload log file to S3
S3_LOG_PATH="${S3_PATH}/${JIRA_TICKET}/${TASK_TYPE}/${TASK_ID}/${TASK_ID}_${TIMESTAMP}.log"
log "Uploading log file to S3: $S3_LOG_PATH"

if aws s3 cp "$LOG_FILE" "$S3_LOG_PATH"; then
    log "S3 upload successful for log file $TASK_ID."
else
    log "ERROR: Failed to upload log file $TASK_ID to S3."
    exit 1
fi

log "=== Configuration Transfer backup for task $TASK_ID completed successfully ==="