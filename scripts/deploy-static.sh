#!/bin/bash

set -euo pipefail

# Inputs
JIRA_TICKET="$1"
STATIC_CFG_FILE="$2"        # Input .cfg file to be used
STATIC_CSV_FILE="$3"        # Input .csv file to be used
S3_PATH="$4"
DB_HOST="$5"                 # Database URL (e.g., jdbc:oracle:thin:@...)
DB_NAME="$6"                # Database name (e.g., ORAC, ORCL)
STATIC_DIR="$7"             # Directory for staticTLM binary (e.g., /STL/tlmsys/TLM_Recon/bin)
ORAC_HOME="$8"
LIBRARY_PATH="$9"
TASK_IDENTIFIER="$10"        # e.g., StaticTask1 or StaticTask2

TASK_TYPE="Static"
TASK_ID="${TASK_IDENTIFIER}"  # Set TASK_ID based on TASK_IDENTIFIER input

# Prepare working directory for deployment execution logs
WORK_DIR="/tmp/${JIRA_TICKET}/deploy/${TASK_TYPE}/${TASK_ID}"
mkdir -p "$WORK_DIR"

# Paths
# STATIC_DIR="/STL/tlmsys/TLM_Recon/bin"
STATIC_CFG_PATH="/tmp/${JIRA_TICKET}/client-packages/${JIRA_TICKET}/deploy/${STATIC_CFG_FILE}"
STATIC_CSV_PATH="/tmp/${JIRA_TICKET}/client-packages/${JIRA_TICKET}/deploy/${STATIC_CSV_FILE}"

LOG_FILE="static_deploy.txt"               # Log file to store the output (e.g., test_log15.txt)
STATIC_LOG_FILE="${WORK_DIR}/${LOG_FILE}"  # Output log file

# Timestamp for unique log files
TIMESTAMP=$(date +%Y%m%d%H%M%S)
DEPLOY_LOG_FILE="${WORK_DIR}/static_tlm_deploy_${TASK_ID}_${TIMESTAMP}.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$DEPLOY_LOG_FILE"
}

# Optional: source env
if [ -f /etc/profile.d/oracle.sh ]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/oracle.sh
fi

cd "$WORK_DIR"

log "=== Starting StaticTLM deployment for task $TASK_ID ==="
log "CFG file: $STATIC_CFG_PATH"
log "CSV file: $STATIC_CSV_PATH"
log "Log file: $STATIC_LOG_FILE"
log "Working dir: $WORK_DIR"
log "Static dir: $STATIC_DIR"

# Check if staticTLM binary exists
if [[ ! -f "$STATIC_DIR/staticTLM" ]]; then
    log "ERROR: staticTLM binary not found at: $STATIC_DIR/staticTLM"
    exit 1
fi

# Check if .cfg file exists
if [[ ! -f "$STATIC_CFG_PATH" ]]; then
    log "ERROR: .cfg file not found at: $STATIC_CFG_PATH"
    exit 1
fi

# Check if .csv file exists
if [[ ! -f "$STATIC_CSV_PATH" ]]; then
    log "ERROR: .csv file not found at: $STATIC_CSV_PATH"
    exit 1
fi

# Check if unpw.txt exists
if [[ ! -f "$STATIC_DIR/unpw.txt" ]]; then
    log "ERROR: unpw.txt not found at: $STATIC_DIR/unpw.txt"
    exit 1
fi

log "Executing staticTLM command..."

ORACLE_HOME=$ORAC_HOME
PATH=$ORACLE_HOME/bin:$PATH
export ORACLE_HOME
export TLM_HOME=/STL/tlmsys/TLM_Recon
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$TLM_HOME/$LIBRARY_PATH
export TNS_ADMIN=$ORACLE_HOME/network/admin #always same
export ORACLE_SID="$DB_NAME"
export END_POINT="$DB_HOST"
export PATH=$PATH:$TLM_HOME/bin

# Execute the staticTLM command
cd "$STATIC_DIR"
if ./staticTLM \
    "$STATIC_CFG_PATH" \
    "$STATIC_CSV_PATH" \
    "$DB_HOST" \
    "$DB_NAME" \
    < unpw.txt > \
    "$STATIC_LOG_FILE"; then
    log "staticTLM execution completed successfully for $TASK_ID."
else
    log "ERROR: staticTLM execution failed for $TASK_ID."
    exit 1
fi

# Upload log file to S3
S3_LOG_PATH="${S3_PATH}/${JIRA_TICKET}/${TASK_TYPE}/${TASK_ID}/static_tlm_deploy_${TIMESTAMP}.log"
log "Uploading staticTLM log to S3: $S3_LOG_PATH"

if aws s3 cp "$STATIC_LOG_FILE" "$S3_LOG_PATH"; then
    log "S3 upload successful for staticTLM log."
else
    log "ERROR: Failed to upload staticTLM log to S3"
    exit 1
fi

# Upload deploy log file (this script's log) to S3
S3_DEPLOY_LOG_PATH="${S3_PATH}/${JIRA_TICKET}/${TASK_TYPE}/${TASK_ID}/deploy_${TASK_ID}_${TIMESTAMP}.log"
log "Uploading deploy log to S3: $S3_DEPLOY_LOG_PATH"

if aws s3 cp "$DEPLOY_LOG_FILE" "$S3_DEPLOY_LOG_PATH"; then
    log "S3 upload successful for deploy wrapper log."
else
    log "ERROR: Failed to upload deploy wrapper log to S3."
    exit 1
fi

log "=== StaticTLM deployment for task $TASK_ID completed successfully ==="