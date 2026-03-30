#!/bin/bash
set -euo pipefail

# Inputs
JIRA_TICKET="$1"
FILE_NAME="$2"
TARGET_PATH="$3"

# Task Type is fixed as "LinuxPackages"
TASK_TYPE="LinuxPackages"

# Derived paths
SRC_FILE="/tmp/${JIRA_TICKET}/client-packages/${JIRA_TICKET}/deploy/${FILE_NAME}"
DEPLOY_DIR="/tmp/${JIRA_TICKET}/deploy-logs/${TASK_TYPE}"
mkdir -p "$DEPLOY_DIR"
LOG_FILE="${DEPLOY_DIR}/deploy_$(basename "$FILE_NAME" | sed 's/\.[^.]*$//').log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

cleanup() {
    [[ -n "${TMP_COPY:-}" && -f "$TMP_COPY" ]] && rm -f "$TMP_COPY" || true
}
trap cleanup EXIT

log "=== Starting deployment ==="
log "Source file : $SRC_FILE"
log "Target path : $TARGET_PATH"
log "File name   : $FILE_NAME"

# Basic validations
if [[ -z "$JIRA_TICKET" || -z "$FILE_NAME" || -z "$TARGET_PATH" ]]; then
    log "ERROR: usage: $0 <JIRA_TICKET> <FILE_NAME> <TARGET_PATH>"
    exit 1
fi

# Check source file
if [[ ! -f "$SRC_FILE" ]]; then
    log "ERROR: Deployment source file not found: $SRC_FILE"
    exit 1
fi

# Determine whether TARGET_PATH is a directory path or already a full file path
# If TARGET_PATH is an existing directory -> treat as directory
# Else if the basename of TARGET_PATH equals FILE_NAME -> treat TARGET_PATH as the final DEST_FILE
# Else treat TARGET_PATH as a directory (create parent dir) and append FILE_NAME
if [[ -d "$TARGET_PATH" ]]; then
    PARENT_DIR="$TARGET_PATH"
    DEST_FILE="${PARENT_DIR%/}/$FILE_NAME"
elif [[ "$(basename "$TARGET_PATH")" == "$FILE_NAME" ]]; then
    # TARGET_PATH looks like it's already the destination file
    DEST_FILE="$TARGET_PATH"
    PARENT_DIR="$(dirname "$DEST_FILE")"
else
    # TARGET_PATH is not a directory and not equal to file name: create parent dir of TARGET_PATH
    PARENT_DIR="$(dirname "$TARGET_PATH")"
    DEST_FILE="${PARENT_DIR%/}/$FILE_NAME"
fi

# Safety checks on computed parent dir
if [[ -z "$PARENT_DIR" || "$PARENT_DIR" == "/" ]]; then
    log "ERROR: Refusing to operate on empty or root parent directory: $PARENT_DIR"
    exit 2
fi

# If parent exists but is regular file -> error
if [[ -e "$PARENT_DIR" && ! -d "$PARENT_DIR" ]]; then
    log "ERROR: Parent path exists and is not a directory: $PARENT_DIR"
    exit 3
fi

# Ensure parent directory exists
if [[ ! -d "$PARENT_DIR" ]]; then
    log "Creating parent directory: $PARENT_DIR"
    mkdir -p "$PARENT_DIR"
    log "Created parent directory: $PARENT_DIR"
fi

# Decide ownership/permissions to apply after deploy
if [[ -f "$DEST_FILE" ]]; then
    log "Destination file already exists; preserving its owner/permissions."
    EXISTING_OWNER=$(stat -c '%U' "$DEST_FILE")
    EXISTING_GROUP=$(stat -c '%G' "$DEST_FILE")
    EXISTING_PERMS=$(stat -c '%a' "$DEST_FILE")
else
    log "Destination file does not exist; using parent directory's owner/permissions."
    EXISTING_OWNER=$(stat -c '%U' "$PARENT_DIR")
    EXISTING_GROUP=$(stat -c '%G' "$PARENT_DIR")
    EXISTING_PERMS=$(stat -c '%a' "$PARENT_DIR")
fi

log "Computed values:"
log "  Parent dir : $PARENT_DIR"
log "  Dest file  : $DEST_FILE"
log "  Owner/Group to set : ${EXISTING_OWNER}:${EXISTING_GROUP}"
log "  Perms to set       : $EXISTING_PERMS"

# Copy via atomic move: copy to temp file in same filesystem, then mv
TMP_COPY="$(mktemp "${PARENT_DIR%/}/.${FILE_NAME}.tmp.XXXXXX")"
log "Copying source to temp file: $TMP_COPY"
cp -f --preserve=mode,timestamps "$SRC_FILE" "$TMP_COPY"
sync "$TMP_COPY"

# Ensure tmp file exists and size seems sane
if [[ ! -f "$TMP_COPY" ]]; then
    log "ERROR: temp copy failed: $TMP_COPY"
    exit 4
fi

# Move into place (atomic on same FS)
log "Moving temp file to final destination: $DEST_FILE"
mv -f "$TMP_COPY" "$DEST_FILE"
TMP_COPY=""   # cleared so cleanup won't remove it

# Set ownership and permissions
log "Setting ownership to ${EXISTING_OWNER}:${EXISTING_GROUP}"
chown "${EXISTING_OWNER}:${EXISTING_GROUP}" "$DEST_FILE" || log "WARN: chown failed (permission?)"
log "Setting permissions to ${EXISTING_PERMS}"
chmod "${EXISTING_PERMS}" "$DEST_FILE" || log "WARN: chmod failed (permission?)"

# Log final file metadata
OWNER=$(stat -c '%U' "$DEST_FILE")
GROUP=$(stat -c '%G' "$DEST_FILE")
PERMS=$(stat -c '%a' "$DEST_FILE")
MTIME=$(stat -c '%y' "$DEST_FILE")
SIZE=$(stat -c '%s' "$DEST_FILE")

log "Deployed file metadata:"
log "  Owner         : $OWNER"
log "  Group         : $GROUP"
log "  Permissions   : $PERMS"
log "  Size (bytes)  : $SIZE"
log "  Last Modified : $MTIME"

log "=== Deployment completed successfully ==="
exit 0