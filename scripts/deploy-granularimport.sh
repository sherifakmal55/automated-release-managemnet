#!/bin/bash
# Usage:
# ./run_granularimport.sh <work_dir> <project_id> <file> <user> <password> <server> <port>
#
# Example:
# ./run_granularimport.sh /tmp/WES-1234 4028229f-2dd1-9170-012d-d1a0562b1352 "/tmp/REC Audit Item.tcg" ADMIN 'Kd624kmQLa6oWZ!kgf84@' 10.1.1.79 50051

set -o errexit
set -o nounset
set -o pipefail

if [ $# -ne 8 ]; then
  echo "Usage: $0 <work_dir> <project_id> <file> <user> <password> <server> <port> <java_path>"
  exit 2
fi

WORK_DIR=$1
PROJECT_ID=$2
FILE_ARG=$3
USER_ARG=$4
PASS_ARG=$5
SERVER_ARG=$6
PORT_ARG=$7
JAVA_PATH=$8

# Validate work dir
if [ ! -d "$WORK_DIR" ]; then
  echo "❌ Directory not found: $WORK_DIR"
  exit 2
fi

# Validate file
if [ ! -f "$FILE_ARG" ]; then
  echo "❌ Import file not found: $FILE_ARG"
  exit 2
fi

# Clean JAVA_PATH - remove any leading backticks, quotes, or special characters
JAVA_PATH_CLEAN="${JAVA_PATH#\`}"     # Remove leading backtick
JAVA_PATH_CLEAN="${JAVA_PATH_CLEAN#\'}"   # Remove leading single quote
JAVA_PATH_CLEAN="${JAVA_PATH_CLEAN#\"}"   # Remove leading double quote
JAVA_PATH_CLEAN="${JAVA_PATH_CLEAN%\'}"   # Remove trailing single quote
JAVA_PATH_CLEAN="${JAVA_PATH_CLEAN%\"}"   # Remove trailing double quote

echo "🔍 JAVA_PATH debugging:"
echo "  Original: [$JAVA_PATH]"
echo "  Cleaned: [$JAVA_PATH_CLEAN]"

# Source Java env if present
export JAVA_HOME="$JAVA_PATH_CLEAN"
export PATH="${JAVA_HOME}/bin:${PATH}"



echo "JAVA_HOME: ${JAVA_HOME:-<not set>}"

cd "$WORK_DIR" || { echo "❌ Failed to cd to $WORK_DIR"; exit 2; }

# Ensure controlutil exists
if [ ! -x "./controlutil.sh" ]; then
  echo "❌ controlutil.sh not found or not executable in $WORK_DIR"
  exit 2
fi

echo "👉 Running granularimport in: $WORK_DIR"
echo "------------------------------------------------------------"

# Build command
CMD=( ./controlutil.sh granularimport -project "$PROJECT_ID" -file "$FILE_ARG" -user "$USER_ARG" -password "$PASS_ARG" -server "$SERVER_ARG" -port "$PORT_ARG" )

# Print the command (mask password)
MASKED_CMD_DISPLAY=$(printf "%s " "${CMD[@]}" | sed -E "s/(-password )[^ ]+/\1'********'/")
echo "▶ Command: $MASKED_CMD_DISPLAY"

# Run and capture output
OUTPUT="$("${CMD[@]}" 2>&1)" || RC=$?
RC=${RC:-0}

echo
echo "---- controlutil output ----"
echo "$OUTPUT"
echo "----------------------------"
echo

# Success check
if echo "$OUTPUT" | grep -qiE "granularimport.*completed successfully|completed successfully|import.*completed"; then
  echo "✅ Granular import of project '$PROJECT_ID' completed successfully."
  exit 0
else
  echo "❌ Granular import FAILED (exit code: ${RC:-1})."
  echo "---- Possible error lines ----"
  echo "$OUTPUT" | grep -i -E "ERROR|EXCEPTION|FAILED|unable|cannot|exception" || true
  echo "-------------------------------"
  exit 1
fi