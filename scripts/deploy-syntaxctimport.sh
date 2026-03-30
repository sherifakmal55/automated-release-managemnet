#!/bin/bash
# Usage:
# ./run_Syntax-CT-Export.sh <work_dir> <file> <env-id> <env-name> <obj_version> <server-arg> <syntax-name>

#sample-cmd:
#./deploy-syntaxctimport.sh /tmp/OND-1112/syntax-ct/installer-3.0.1.23-linux.gtk.x86_64 3 LC_DEV /tmp/MMI_SYNTAX-FULL.cte /STL/Java/jdk-17.0.7

if [ $# -ne 5 ]; then
  echo "Usage: $0 <work_dir> <file> <env-id> <env-name> <java_path>"
  exit 2
fi

WORK_DIR=$1
FILE_ARG=$2
ENV_ID=$3
ENV_NAME=$4
JAVA_PATH=$5

if [ ! -d "$WORK_DIR" ]; then
  echo "❌ Directory not found: $WORK_DIR"
  exit 2
fi


export JAVA_HOME="$JAVA_PATH"
export PATH="$JAVA_HOME/bin:$PATH"
echo "JAVA_HOME is set to: $JAVA_HOME"

cd "$WORK_DIR" || { echo "❌ Failed to cd to $WORK_DIR"; exit 2; }

echo "👉 Running Syntax-CT-Import in: $WORK_DIR"
echo "------------------------------------------------------------"

# Run and capture output

OUTPUT=$(./installer -cli -i "$ENV_ID" -n "$ENV_NAME" -c "$FILE_ARG" 2>&1)

# Print live output
echo "$OUTPUT"

# Check success or failure
if echo "$OUTPUT" | grep -qi "com.smartstream.installer.app.*Wrote data to DB"; then
  echo "✅ Syntax CT Import of syntax-ct '${FILE_ARG}' completed successfully."
  exit 0
else
  echo "❌ SYNTAX CT Import FAILED."
  echo "---- Possible error lines ----"
  echo "$OUTPUT" | grep -i -E "FAILED|unable|cannot" || true
  exit 1
fi
