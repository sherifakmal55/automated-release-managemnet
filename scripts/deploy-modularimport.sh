#!/bin/bash
# Usage:
# ./run_modularimport.sh <work_dir> <file> <user> <password> <server> <port>
#
# Example:
# ./run_modularimport.sh /tmp/WES-1234 /home/ec2-user/rec-process.tcm "ADMIN" 'Kd624kmQLa6oWZ!kgf84@' 10.1.1.79 50051

set -o errexit
set -o nounset
set -o pipefail

if [ $# -ne 7 ]; then
  echo "Usage: $0 <work_dir> <file> <user> <password> <server> <port> <java_path>"
  exit 2
fi

WORK_DIR=$1
FILE_ARG=$2
USER_ARG=$3
PASS_ARG=$4
SERVER_ARG=$5
PORT_ARG=$6
JAVA_PATH=$7

# Validate work dir
if [ ! -d "$WORK_DIR" ]; then
  echo "❌ Directory not found: $WORK_DIR"
  exit 2
fi

# Validate file to import
if [ ! -f "$FILE_ARG" ]; then
  echo "❌ Import file not found: $FILE_ARG"
  exit 2
fi

# Source Java env if present
export JAVA_HOME="$JAVA_PATH"
export PATH="$JAVA_HOME/bin:$PATH"

echo "JAVA_HOME: ${JAVA_HOME:-<not set>}"

cd "$WORK_DIR" || { echo "❌ Failed to cd to $WORK_DIR"; exit 2; }

# Ensure controlutil exists and is executable
if [ ! -x "./controlutil.sh" ]; then
  echo "❌ controlutil.sh not found or not executable in $WORK_DIR"
  exit 2
fi

echo "👉 Running modularimport in: $WORK_DIR"
echo "------------------------------------------------------------"

# Build command safely (keeps password quoting intact)
CMD=( ./controlutil.sh modularimport -file "$FILE_ARG" -user "$USER_ARG" -password "$PASS_ARG" -server "$SERVER_ARG" -port "$PORT_ARG" )

# Print the command (mask password for display)
MASKED_CMD_DISPLAY=$(printf "%s " "${CMD[@]}" | sed -E "s/(-password )[^ ]+/\1'********'/")
echo "▶ Command: $MASKED_CMD_DISPLAY"

# Execute command and capture output
# We capture output so we can search for success/failure markers and print useful lines on failure
OUTPUT="$("${CMD[@]}" 2>&1)" || RC=$?
RC=${RC:-0}

# Print full output
echo
echo "---- controlutil output ----"
echo "$OUTPUT"
echo "----------------------------"
echo

# Determine success: match typical success messages; adjust pattern if your tool prints something else
if echo "$OUTPUT" | grep -qiE "modularimport.*completed successfully|completed successfully|import.*completed"; then
  echo "✅ Modular import completed successfully."
  exit 0
else
  echo "❌ Modular import FAILED (exit code: ${RC:-1})."
  echo "---- Possible error lines ----"
  echo "$OUTPUT" | grep -i -E "ERROR|EXCEPTION|FAILED|unable|cannot|exception" || true
  echo "-------------------------------"
  exit 1
fi