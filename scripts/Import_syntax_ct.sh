#!/bin/bash

set -euo pipefail

# Inputs
JIRA_TICKET="$1"
CTE_FILE="$2"              # Input .cte file to be imported
S3_PATH="$3"
DB_URL="$4"                # Database URL (e.g., jdbc:oracle:thin:@...)
DB_USER="$5"               # Database username
DB_PASS="$6"               # Database password
env_name=$1           # <env-name>
env_id=$2                     # <env-id>
TASK_IDENTIFIER="$7"       # e.g., Syntax_CTTask1 or Syntax_CTTask2

TASK_TYPE="SyntaxCT"
TASK_ID="${TASK_IDENTIFIER}"

# Prepare working directory for deployment executions logs
WORK_DIR="/tmp/${JIRA_TICKET}/deploy/${TASK_TYPE}/${TASK_ID}"
mkdir -p "$WORK_DIR"

# Paths
SyntaxCT_DIR="/tmp/${JIRA_TICKET}/utilities/${TASK_TYPE}"
SyntaxCT_BINARY="${SyntaxCT_DIR}/Installer"
CTE_PATH="/tmp/${JIRA_TICKET}/client-packages/${JIRA_TICKET}/deploy/${CTE_FILE}"  # <-- Updated
# SyntaxCT_LOG_FILE="${SyntaxCT_DIR}/ConfigurationTransfer.log"  # <-- Updated

# Timestamp for unique log files
TIMESTAMP=$(date +%Y%m%d%H%M%S)
DEPLOY_LOG_FILE="${WORK_DIR}/SyntaxCT_${TASK_ID}_${TIMESTAMP}.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$DEPLOY_LOG_FILE"
}

cd "$WORK_DIR"

log "=== Starting SyntaxCT deployment for task $TASK_ID ==="
log "CTE file: $CTE_PATH"
# log "SyntaxCT binary: $SyntaxCT_BINARY"
log "Working dir: $WORK_DIR"

# Check if SyntaxCT binary exists
if [[ ! -f "$SyntaxCT_BINARY" ]]; then
    log "ERROR: SyntaxCT binary not found at: $SyntaxCT_BINARY"
    exit 1
fi

# Check if CTE file exists
if [[ ! -f "$CTE_PATH" ]]; then
    log "ERROR: CTE file not found at: $CTE_PATH"
    exit 1
fi

# Set up Java environment
log "Setting up Java environment for SyntaxCT deployment..."

export JAVA_HOME="/STL/Java/jdk-17.0.7"
export PATH="$JAVA_HOME/bin:$PATH"

if ! command -v java &> /dev/null; then
    log "ERROR: Java not found even after setting JAVA_HOME"
    exit 1
fi

log "Java found at: $(which java)"
log "Java version: $(java -version 2>&1 | head -n 1)"

# Change to SyntaxCT directory and run import
cd "$SyntaxCT_DIR"
log "Executing SyntaxCT import..."

if ./installer -cli -i $env_id -n $env_name -c $cte_file_path &; then
    log "SyntaxCT import completed successfully for $TASK_ID."
else
    log "ERROR: SyntaxCT import failed for $TASK_ID."
    exit 1
fi

# Upload SyntaxCT log file (Configurationtransfer.log) to S3
# S3_SyntaxCT_LOG_PATH="${S3_PATH}/${JIRA_TICKET}/${TASK_TYPE}/${TASK_ID}/Configurationtransfer_${TIMESTAMP}.log"
# log "Uploading Configurationtransfer.log to S3: $S3_SyntaxCT_LOG_PATH"

# if [[ -f "$SyntaxCT_LOG_FILE" ]]; then
#     if aws s3 cp "$SyntaxCT_LOG_FILE" "$S3_SyntaxCT_LOG_PATH"; then
#         log "S3 upload successful for Configurationtransfer.log"
#     else
#         log "ERROR: Failed to upload Configurationtransfer.log to S3"
#         exit 1
#     fi
# else
#     log "ERROR: Configurationtransfer.log not found at $SyntaxCT_LOG_FILE"
#     exit 1
# fi

# Upload deploy log file (this script's log) to S3
S3_DEPLOY_LOG_PATH="${S3_PATH}/${JIRA_TICKET}/${TASK_TYPE}/${TASK_ID}/deploy_wrapper_${TASK_ID}_${TIMESTAMP}.log"
log "Uploading deploy log to S3: $S3_DEPLOY_LOG_PATH"

if aws s3 cp "$DEPLOY_LOG_FILE" "$S3_DEPLOY_LOG_PATH"; then
    log "S3 upload successful for deploy wrapper log."
else
    log "ERROR: Failed to upload deploy wrapper log to S3."
    exit 1
fi

log "=== Configuration Transfer deployment for task $TASK_ID completed successfully ==="