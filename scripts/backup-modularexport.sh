#!/bin/bash
# Usage:
# ./run_modularexport.sh <work_dir> <file> <user> <password> <server> <port> <projects>

if [ $# -ne 8 ]; then
  echo "Usage: $0 <work_dir> <file> <user> <password> <server> <port> <projects> <java_path>"
  exit 2
fi

WORK_DIR=$1
FILE_ARG=$2
USER_ARG=$3
PASS_ARG=$4
SERVER_ARG=$5
PORT_ARG=$6
PROJECTS_ARG=$7
JAVA_PATH=$8

if [ ! -d "$WORK_DIR" ]; then
  echo "❌ Directory not found: $WORK_DIR"
  exit 2
fi


export JAVA_HOME="$JAVA_PATH"
export PATH="$JAVA_HOME/bin:$PATH"
echo "JAVA_HOME is set to: $JAVA_HOME"

cd "$WORK_DIR" || { echo "❌ Failed to cd to $WORK_DIR"; exit 2; }

echo "👉 Running modularexport in: $WORK_DIR"
echo "------------------------------------------------------------"

# Run and capture output
OUTPUT=$(./controlutil.sh modularexport -audittype CHECKIN -file "$FILE_ARG" -user "$USER_ARG" -password "$PASS_ARG" -server "$SERVER_ARG" -port "$PORT_ARG" -projects "$PROJECTS_ARG" 2>&1)

# Print live output
echo "$OUTPUT"

# Check success or failure
if echo "$OUTPUT" | grep -qi "modularexport.*completed successfully"; then
  echo "✅ Modular export backup of project '${PROJECTS_ARG}' completed successfully."
  exit 0
else
  echo "❌ Modular export FAILED."
  echo "---- Possible error lines ----"
  echo "$OUTPUT" | grep -i -E "ERROR|EXCEPTION|FAILED|unable|cannot" || true
  exit 1
fi
