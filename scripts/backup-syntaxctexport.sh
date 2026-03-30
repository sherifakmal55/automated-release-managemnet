#!/bin/bash
# Usage:
# ./run_Syntax-CT-Export.sh <work_dir> <file> <env-id> <env-name> <obj_version> <server-arg> <syntax-name>

#sample-cmd:
#./backup-syntaxctexport.sh /tmp/lc-test-ct /tmp/MMI_TEST_01.cte 3 LC_DEV 3.0.0 MMI_SYNTAX /STL/Java/jdk-17.0.7

if [ $# -ne 7 ]; then
  echo "Usage: $0 <work_dir> <file> <env-id> <env-name> <obj_version>  <syntax-name> <java_path>"
  exit 2
fi

WORK_DIR=$1
FILE_ARG=$2
ENV_ID=$3
ENV_NAME=$4
OBJ_VERSION=$5
SYNTAX_NAME=$6
JAVA_PATH=$7

if [ ! -d "$WORK_DIR" ]; then
  echo "❌ Directory not found: $WORK_DIR"
  exit 2
fi


export JAVA_HOME="$JAVA_PATH"
export PATH="$JAVA_HOME/bin:$PATH"
echo "JAVA_HOME is set to: $JAVA_HOME"

cd "$WORK_DIR" || { echo "❌ Failed to cd to $WORK_DIR"; exit 2; }

echo "👉 Running Syntax-CT-Export in: $WORK_DIR"
echo "------------------------------------------------------------"

# Run and capture output

OUTPUT=$(./installer -cli -i "$ENV_ID" -n "$ENV_NAME" -C "$FILE_ARG" -export ""${SYNTAX_NAME}.*:${OBJ_VERSION}"" 2>&1)

# Print live output
echo "$OUTPUT"

# Check success or failure
if echo "$OUTPUT" | grep -qi "Wrote CTE output for.*cte"; then
  echo "✅ Syntax CT export backup of syntax-ct '${SYNTAX_NAME}' completed successfully."
  exit 0
else
  echo "❌ SYNTAX CT export FAILED."
  echo "---- Possible error lines ----"
  echo "$OUTPUT" | grep -i -E "FAILED|unable|cannot" || true
  exit 1
fi
