#!/bin/bash

set -euo pipefail

# Inputs
JIRA_TICKET="$1"
FILE_NAME="$2"
TARGET_PATH="$3"
S3_BUCKET="${4:-}"  # Optional S3 bucket

# Task Type is fixed
TASK_TYPE="LinuxPackages"

# Derived paths
BACKUP_FILE="/tmp/${JIRA_TICKET}/backup/${TASK_TYPE}/backup_${FILE_NAME}"
DEPLOYED_FILE="${TARGET_PATH}/${FILE_NAME}"
LOG_DIR="/tmp/${JIRA_TICKET}/rollback-logs/${TASK_TYPE}"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/rollback_$(basename "$FILE_NAME" | sed 's/\.[^.]*$//').log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

log "=== Starting rollback for $FILE_NAME ==="
log "Backup file: $BACKUP_FILE"
log "Deployed file: $DEPLOYED_FILE"
log "Target path: $TARGET_PATH"

# Initialize restoration flag
RESTORED=false

# Try restoring from local backup
if [[ -f "$BACKUP_FILE" ]]; then
    log "Backup file found locally. Restoring..."

    # Ensure target directory exists
    if [[ ! -d "$TARGET_PATH" ]]; then
        log "Creating target directory: $TARGET_PATH"
        mkdir -p "$TARGET_PATH"
    fi

    # Restore the backup file and set permissions of the backup file
    log "Restoring backup to target directory..."
    cp "$BACKUP_FILE" "$DEPLOYED_FILE"
    log "Backup file restored successfully to $DEPLOYED_FILE"

    # Set the correct permissions and ownership for the restored file
    OWNER=$(stat -c '%U' "$BACKUP_FILE")
    GROUP=$(stat -c '%G' "$BACKUP_FILE")
    PERMS=$(stat -c '%a' "$BACKUP_FILE")
    chown "$OWNER":"$GROUP" "$DEPLOYED_FILE"
    chmod "$PERMS" "$DEPLOYED_FILE"
    log "Permissions and ownership set for $DEPLOYED_FILE"

    RESTORED=true

# Try restoring from S3 if local backup is missing
elif [[ -n "$S3_BUCKET" ]]; then
    log "No local backup found. Checking S3..."

    S3_BACKUP_PATH="s3://${S3_BUCKET}/Release-Management/${JIRA_TICKET}/${TASK_TYPE}/${FILE_NAME}"

    # Check if file exists in S3
    if aws s3 ls "$S3_BACKUP_PATH" > /dev/null 2>&1; then
        log "Backup file found in S3: $S3_BACKUP_PATH"

        if [[ -f "$DEPLOYED_FILE" ]]; then
            log "Taking permissions from the deployed file ($DEPLOYED_FILE)..."
            OWNER=$(stat -c '%U' "$DEPLOYED_FILE")
            GROUP=$(stat -c '%G' "$DEPLOYED_FILE")
            PERMS=$(stat -c '%a' "$DEPLOYED_FILE")
        else
            log "ERROR: Deployed file does not exist: $DEPLOYED_FILE"
            exit 1
        fi

        if aws s3 cp "$S3_BACKUP_PATH" "$DEPLOYED_FILE"; then
            log "Backup file downloaded from S3 to $DEPLOYED_FILE"
            chown "$OWNER":"$GROUP" "$DEPLOYED_FILE"
            chmod "$PERMS" "$DEPLOYED_FILE"
            log "Permissions and ownership set for $DEPLOYED_FILE"
            RESTORED=true
        else
            log "ERROR: Failed to download backup file from S3."
            exit 1
        fi
    else
        log "No backup file found in S3 at $S3_BACKUP_PATH"
    fi
fi

# Rename only if no backup was restored
if [[ "$RESTORED" == false ]]; then
    if [[ ! -f "$DEPLOYED_FILE" ]]; then
        log "ERROR: Deployed file does not exist to rename."
        exit 1
    else
        log "No backup found in local or S3. Renaming deployed file..."
        TIMESTAMP=$(date +%Y%m%d%H%M%S)
        RENAMED_FILE="${DEPLOYED_FILE%.*}.${TIMESTAMP}.renamed.${FILE_NAME##*.}"
        mv "$DEPLOYED_FILE" "$RENAMED_FILE"
        log "Deployed file renamed to $RENAMED_FILE"
    fi
fi

log "=== Rollback process completed ==="