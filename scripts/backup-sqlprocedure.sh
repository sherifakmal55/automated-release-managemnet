
#!/bin/bash

# Make failures visible early
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DB_HOST=$1
DB_PORT=$2
DB_SERVICE=$3
DB_USER=$4
DB_PASSWORD=$5
PROCEDURE_NAME=$6
OUTPUT_FILE_PATH=$7        # e.g., /opt/arm/sqlbackup/procedure
JIRA_ID=$8                 # e.g., xxxxx_bkp_30_07.sql
S3_TARGET_PATH=$9          # e.g., s3://stl-<client>-housekeeping/release-management/<JIRA_ID>/DatabaseProcedure/
ORACLE_PATH=${10}          # e.g., /usr/lib/oracle/19.15/client64

OUTPUT_FILE_NAME="${PROCEDURE_NAME}-${JIRA_ID}.sql"
OUTPUT_FILE="${OUTPUT_FILE_PATH}/${OUTPUT_FILE_NAME}"
LOG_FILE="/tmp/${PROCEDURE_NAME}_procedure_backup_$(date +%Y%m%d).log"

# --- Ensure Oracle env is visible to this SSM shell ---
export ORACLE_HOME="$ORACLE_PATH"
export PATH="$ORACLE_HOME/bin:${PATH:-}"
export LD_LIBRARY_PATH="$ORACLE_HOME/lib:$ORACLE_HOME/network/lib:${LD_LIBRARY_PATH:-}"

# Diagnostics
echo "ORACLE_HOME=$ORACLE_HOME"
echo "PATH=$PATH"
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"

echo -e "${YELLOW}🔍 sqlplus discovery${NC}"
SQLPLUS_BIN=""
if command -v sqlplus >/dev/null 2>&1; then
  SQLPLUS_BIN="$(command -v sqlplus)"
  echo "which sqlplus: $SQLPLUS_BIN"
else
  SQLPLUS_BIN="$ORACLE_HOME/bin/sqlplus"
  echo "which sqlplus: (not on PATH); trying $SQLPLUS_BIN"
fi

# Print version (uses -v)
if [ -x "$SQLPLUS_BIN" ]; then
  echo "sqlplus version:"
  "$SQLPLUS_BIN" -v || echo -e "${RED}⚠️ Failed to run 'sqlplus -v'${NC}"
else
  echo -e "${RED}❌ sqlplus binary not executable at: $SQLPLUS_BIN${NC}"
  ls -l "$ORACLE_HOME/bin" || true
  exit 10
fi

echo "🔄 Backing up Procedure: $PROCEDURE_NAME"
echo "📁 Output File: $OUTPUT_FILE"
echo "📝 Log File: $LOG_FILE"

# Ensure output dir exists
mkdir -p "$OUTPUT_FILE_PATH"

# --- Run SQL to generate procedure DDL ---
"$SQLPLUS_BIN" -s "$DB_USER/$DB_PASSWORD@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$DB_HOST)(PORT=$DB_PORT))(CONNECT_DATA=(SERVICE_NAME=$DB_SERVICE)))" <<EOF > "$LOG_FILE" 2>&1
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF LONG 100000 LONGCHUNKSIZE 100000 LINESIZE 32767 TRIMSPOOL ON
SPOOL $OUTPUT_FILE
SELECT DBMS_METADATA.GET_DDL('PROCEDURE', UPPER('$PROCEDURE_NAME'), UPPER('$DB_USER')) FROM DUAL;
SPOOL OFF
EXIT
EOF

# Append "/" so SQL*Plus can execute on redeploy
echo "/" >> "$OUTPUT_FILE"

# Check for errors and upload
if grep -qi "ORA-31603" "$LOG_FILE"; then
  echo -e "${RED}❌ Error: Procedure '$PROCEDURE_NAME' not found in schema '$DB_USER'${NC}"
  rm -f "$OUTPUT_FILE"
  exit 1
elif grep -qi "ORA-" "$LOG_FILE"; then
  echo -e "${RED}❌ Oracle error encountered while extracting DDL${NC}"
  echo "Log tail:"
  tail -50 "$LOG_FILE" || true
  rm -f "$OUTPUT_FILE"
  exit 1
elif [ -s "$OUTPUT_FILE" ]; then
  echo -e "${GREEN}✅ Procedure backup completed successfully: $OUTPUT_FILE${NC}"
  echo "🚀 Uploading backup to: $S3_TARGET_PATH"
  if aws s3 cp "$OUTPUT_FILE" "$S3_TARGET_PATH/"; then
    echo -e "${GREEN}✅ Upload to S3 succeeded: $S3_TARGET_PATH$(basename "$OUTPUT_FILE")${NC}"
  else
    echo -e "${RED}❌ Failed to upload to S3.${NC}"
    exit 2
  fi
else
  echo -e "${RED}❌ Failed to back up procedure: $PROCEDURE_NAME (empty or invalid output)${NC}"
  echo "Log tail:"
  tail -50 "$LOG_FILE" || true
  exit 1
fi
