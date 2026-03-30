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
TASK_IDENTIFIER="$8"       # e.g., CTTask1 or CTTask2

TASK_TYPE="ConfigurationTransfer"
TASK_ID="${TASK_IDENTIFIER}"

# Prepare working directory
WORK_DIR="/tmp/Release-Management/${JIRA_TICKET}/backup/${TASK_TYPE}/${TASK_ID}"
mkdir -p "$WORK_DIR"

# Paths
CTC_DIR="/tmp/Release-Management/${JIRA_TICKET}/utilities/${TASK_TYPE}"
CTC_BINARY="${CTC_DIR}/CTC"
TEMPLATE_PATH="/tmp/Release-Management/${JIRA_TICKET}/client_packages/backup/${TEMPLATE_FILE}"
CTE_PATH="${WORK_DIR}/${CTE_FILE}"  # Output file will be created here

# Timestamp for unique log files
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE="${WORK_DIR}/config_transfer_${TASK_ID}_${TIMESTAMP}.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

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

# Java version required
REQUIRED_MAJOR=17

find_java_with_version() {
    local candidate version_output
    # Try common locations
    for candidate in \
        /STL/Java/jdk*/bin/java \
        /usr/java/jdk*/bin/java \
        /usr/lib/jvm/java-*/bin/java \
        /opt/java/jdk*/bin/java; do
        if [[ -x "$candidate" ]]; then
            version_output=$("$candidate" -version 2>&1 | head -n 1)
            if [[ "$version_output" =~ \"${REQUIRED_MAJOR}\. ]]; then
                echo "$candidate"
                return 0
            fi
        fi
    done

    # Fallback: try java on PATH
    if command -v java >/dev/null 2>&1; then
        candidate=$(command -v java)
        version_output=$("$candidate" -version 2>&1 | head -n 1)
        if [[ "$version_output" =~ \"${REQUIRED_MAJOR}\. ]]; then
            echo "$candidate"
            return 0
        fi
    fi

    return 1
}

JAVA_PATH=$(find_java_with_version || true)

if [[ -z "$JAVA_PATH" ]]; then
    log "Java $REQUIRED_MAJOR not found. Attempting to install OpenJDK $REQUIRED_MAJOR..."

    # Detect OS and install Java 17 accordingly
    if command -v yum >/dev/null 2>&1; then
        # Amazon Linux / CentOS / RHEL
        sudo yum install -y java-17-openjdk-devel || {
            log "ERROR: Failed to install Java 17 with yum."
            exit 1
        }
    elif command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y openjdk-17-jdk || {
            log "ERROR: Failed to install Java 17 with apt-get."
            exit 1
        }
    else
        log "ERROR: Unsupported OS or package manager. Please install Java 17 manually."
        exit 1
    fi

    # After installation, re-check java
    if JAVA_PATH=$(command -v java 2>/dev/null); then
        version_output=$("$JAVA_PATH" -version 2>&1 | head -n 1)
        if [[ "$version_output" =~ \"${REQUIRED_MAJOR}\. ]]; then
            log "Java $REQUIRED_MAJOR installed successfully at $JAVA_PATH."
        else
            log "ERROR: Java installed but version mismatch or not found."
            exit 1
        fi
    else
        log "ERROR: Java not found after installation."
        exit 1
    fi
else
    log "Java $REQUIRED_MAJOR found at $JAVA_PATH"
fi

# Export JAVA_HOME based on JAVA_PATH
JAVA_HOME=$(dirname "$(dirname "$JAVA_PATH")")
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
log "JAVA_HOME set to $JAVA_HOME"

cd "$WORK_DIR"

log "Executing Configuration Transfer export command..."

cd "$CTC_DIR"

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