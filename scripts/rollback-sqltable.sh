#!/bin/bash
set -euo pipefail

# Args
# 1: DB_HOST
# 2: DB_PORT
# 3: DB_SERVICE
# 4: DB_USER
# 5: DB_PASSWORD
# 6: TABLE_NAME        (e.g., WORKFLOW_CHOICES)
# 7: JIRA_ID           (e.g., WES-1234)

DB_HOST=$1
DB_PORT=$2
DB_SERVICE=$3
DB_USER=$4
DB_PASSWORD=$5
TABLE_NAME=$6
JIRA_ID=$7

ORACLE_DIRECTORY=SHERIF
SAFE_JIRA="${JIRA_ID//-/}"
TARGET_TABLE="${TABLE_NAME}_${SAFE_JIRA}"
DUMP_FILE_NAME="${TABLE_NAME}_${SAFE_JIRA}.dmp"
IMP_LOGFILE="impdp_rollback_${TABLE_NAME}_${SAFE_JIRA}.log"

# Optional: Oracle env
if [ -f /etc/profile.d/oracle.sh ]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/oracle.sh
fi

echo "📍 Starting rollback (impdp) for table: $TABLE_NAME"
echo "📁 Directory object: $ORACLE_DIRECTORY"
echo "📦 Dump file: $DUMP_FILE_NAME"
echo "🆕 Target table: $TARGET_TABLE"
echo "🔎 Checking dump presence in $ORACLE_DIRECTORY ..."

# 1) Verify dump exists in the Oracle directory object
DMP_EXISTS=$(sqlplus -s "${DB_USER}/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE}" <<EOF
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT COUNT(*)
FROM TABLE(RDSADMIN.RDS_FILE_UTIL.LISTDIR('$ORACLE_DIRECTORY'))
WHERE UPPER(filename) = UPPER('$DUMP_FILE_NAME');
EXIT;
EOF
)
DMP_EXISTS=$(echo "$DMP_EXISTS" | xargs)

if [[ "$DMP_EXISTS" != "1" ]]; then
  echo "❌ Dump not found in $ORACLE_DIRECTORY: $DUMP_FILE_NAME"
  echo "   Listing files for visibility:"
  sqlplus -s "${DB_USER}/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE}" <<EOF
SET LINES 200 PAGES 200
COL filename FOR A60
SELECT filename, type, filesize, mtime
FROM TABLE(RDSADMIN.RDS_FILE_UTIL.LISTDIR('$ORACLE_DIRECTORY'))
ORDER BY filename;
EXIT;
EOF
  exit 1
fi

# 2) Run impdp — allow exit code 5 (completed with warnings) to pass
set +e
impdp "${DB_USER}/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE}" \
  TABLES="$TABLE_NAME" \
  DIRECTORY="$ORACLE_DIRECTORY" \
  DUMPFILE="'${DUMP_FILE_NAME}'" \
  REMAP_TABLE="${TABLE_NAME}:${TARGET_TABLE}" \
  TABLE_EXISTS_ACTION=SKIP \
  LOGFILE="$IMP_LOGFILE"
STATUS=$?
set -e

# 3) Treat 0 and 5 as success (5 = completed with warnings like ORA-31684)
if [ "$STATUS" -eq 0 ] || [ "$STATUS" -eq 5 ]; then
  echo "✅ Rollback succeeded: created/kept ${TARGET_TABLE} (impdp exit $STATUS)"
  echo "📝 Server log (tail): $IMP_LOGFILE"
  # Show last few lines from the server log (if accessible via directory listing)
  sqlplus -s "${DB_USER}/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE}" <<EOF || true
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT '$ORACLE_DIRECTORY/$IMP_LOGFILE' FROM dual;
EXIT;
EOF
else
  echo "❌ Rollback failed for $TABLE_NAME (impdp exit $STATUS)"
  echo "   Check server log in $ORACLE_DIRECTORY: $IMP_LOGFILE"
  exit 1
fi