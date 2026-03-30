#!/bin/bash

set -euo pipefail

# Inputs
JIRA_TICKET="$1"
FILE_TO_BACKUP="$2"
FILE_PATH="$3"
S3_BUCKET="$4"

# Unique Task ID based on source file to ensure distinct backup logs/directories
TASK_ID=$(basename "$FILE_TO_BACKUP" | sed 's/\.[^.]*$//') # Strip extension to create task ID
TASK_TYPE="LinuxPackages"

# Derived paths
SRC_FILE="${FILE_PATH}/${FILE_TO_BACKUP}"
#BACKUP_DIR="/tmp/${JIRA_TICKET}/${TASK_TYPE}/backup_linux_packages"
BACKUP_DIR="/tmp/${JIRA_TICKET}/backup/${TASK_TYPE}/backup_${FILE_TO_BACKUP}"
mkdir -p "$BACKUP_DIR"

# Create a timestamp for unique log file names
TIMESTAMP=$(date +%Y%m%d%H%M%S)  # Format: YYYYMMDDHHMMSS

# Automatically generate the backup file name
BACKUP_FILE="${BACKUP_DIR}/backup_${FILE_TO_BACKUP}"
LOG_FILE="${BACKUP_DIR}/backup_${TASK_ID}_${TIMESTAMP}.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

log "=== Starting backup for $SRC_FILE ==="

# Check if source file exists
if [[ ! -f "$SRC_FILE" ]]; then
    log "ERROR: Source file does not exist: $SRC_FILE"
    exit 1
fi

# Copy the file with metadata (preserve ownership, permissions, timestamps, etc.)
cp --preserve=all "$SRC_FILE" "$BACKUP_FILE"
log "File copied successfully to: $BACKUP_FILE"

# Collect and log metadata
OWNER=$(stat -c '%U' "$SRC_FILE")
GROUP=$(stat -c '%G' "$SRC_FILE")
PERMS=$(stat -c '%a' "$SRC_FILE")
MTIME=$(stat -c '%y' "$SRC_FILE")

log "File metadata:"
log "  Owner       : $OWNER"
log "  Group       : $GROUP"
log "  Permissions : $PERMS"
log "  Last Modified : $MTIME"

# Optionally capture ACL if available
if command -v getfacl >/dev/null 2>&1; then
    log "  ACL:"
    getfacl "$SRC_FILE" 2>/dev/null | tee -a "$LOG_FILE"
fi

# Upload to S3 for backup file
S3_BACKUP_PATH="s3://${S3_BUCKET}/Release-Management/${JIRA_TICKET}/${TASK_TYPE}/backup_${FILE_TO_BACKUP}"
log "Uploading backup to S3: $S3_BACKUP_PATH"
if aws s3 cp "$BACKUP_FILE" "$S3_BACKUP_PATH"; then
    log "S3 upload successful for backup."
else
    log "ERROR: Failed to upload backup to S3."
    exit 1
fi

# Upload to S3 for log file
S3_LOG_PATH="s3://${S3_BUCKET}/Release-Management/${JIRA_TICKET}/${TASK_TYPE}/backup_${TASK_ID}_${TIMESTAMP}.log"
log "Uploading log file to S3: $S3_LOG_PATH"
if aws s3 cp "$LOG_FILE" "$S3_LOG_PATH"; then
    log "S3 upload successful for log file."
else
    log "ERROR: Failed to upload log file to S3."
    exit 1
fi

log "=== Backup and log file upload completed successfully ==="