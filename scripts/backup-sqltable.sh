#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Args
DB_HOST=$1
DB_PORT=$2
DB_SERVICE=$3
DB_USER=$4
DB_PASSWORD=$5
TABLE_NAME=$6
JIRA_ID=$7
ORACLE_PATH=$8

# Oracle directory object on RDS
DATA_PUMP_DIR=RELEASE_MANAGEMENT

# Sanitized Jira id for filenames
SAFE_JIRA="${JIRA_ID//-/}"

# Filenames derived from table + Jira
DUMP_FILE_NAME="${TABLE_NAME}_${SAFE_JIRA}_${DB_USER}.dmp"
LOG_FILE_NAME="${TABLE_NAME}_${SAFE_JIRA}_${DB_USER}.log"

export ORACLE_HOME="$ORACLE_PATH"
export PATH="$ORACLE_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$ORACLE_HOME/lib:$ORACLE_HOME/network/lib:${LD_LIBRARY_PATH:-}"

# Use /tmp for TNS configuration
TNS_ADMIN="/tmp/tns_$$"
mkdir -p "$TNS_ADMIN"
export TNS_ADMIN

# Cleanup function
cleanup() {
  echo "🧹 Cleaning up temporary files..."
  rm -rf "$TNS_ADMIN"
  rm -f "/tmp/expdp_${TABLE_NAME}_$$.par"
}
trap cleanup EXIT

# Create tnsnames.ora in temporary location
cat > "${TNS_ADMIN}/tnsnames.ora" << EOF
EXPDP_DB =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${DB_HOST})(PORT = ${DB_PORT}))
    (CONNECT_DATA =
      (SERVICE_NAME = ${DB_SERVICE})
    )
  )
EOF

echo -e "${YELLOW}🔧 TNS configuration created at: ${TNS_ADMIN}/tnsnames.ora${NC}"

# ALWAYS quote the password - this handles all special characters
echo "🔐 Using quoted password format for maximum compatibility"
QUOTED_PASSWORD="\"${DB_PASSWORD}\""

# Diagnostic output
echo "🔍 Environment Diagnostics:"
echo "   ORACLE_HOME: $ORACLE_HOME"
echo "   TNS_ADMIN: $TNS_ADMIN"
echo "   DB_USER: $DB_USER"
echo "   Password length: ${#DB_PASSWORD} characters"

# Verify expdp exists
if ! command -v expdp &> /dev/null; then
  echo -e "${RED}❌ Error: expdp not found in PATH${NC}"
  exit 1
fi

echo "📍 Validating table '$TABLE_NAME' existence..."

# Use TNS alias for sqlplus with quoted password
EXIST_CHECK=$(sqlplus -s "${DB_USER}/${QUOTED_PASSWORD}@EXPDP_DB" <<EOF
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT table_name FROM user_tables WHERE table_name = UPPER('$TABLE_NAME');
EXIT;
EOF
)

if [[ -z "$EXIST_CHECK" ]]; then
  echo -e "${RED}❌ Error: Table '$TABLE_NAME' does not exist${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Table exists. Checking size...${NC}"

TABLE_SIZE_MB=$(sqlplus -s "${DB_USER}/${QUOTED_PASSWORD}@EXPDP_DB" <<EOF
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT NVL(ROUND(BYTES / 1024 / 1024, 2), 0)
FROM user_segments
WHERE segment_type='TABLE' AND segment_name = UPPER('$TABLE_NAME');
EXIT;
EOF
)
TABLE_SIZE_MB=$(echo "$TABLE_SIZE_MB" | xargs)
INT_MB=${TABLE_SIZE_MB%%.*}

echo "📏 Table size: ${TABLE_SIZE_MB} MB"
if [ -n "${INT_MB}" ] && [ "${INT_MB}" -gt 200 ]; then
  echo -e "${YELLOW}⚠️  Table too large (${TABLE_SIZE_MB}MB). Consider snapshot strategy.${NC}"
  exit 1
fi

echo "📦 Backing up Table: $TABLE_NAME"
echo "📁 Directory object: $DATA_PUMP_DIR"
echo "📄 Dump File: $DUMP_FILE_NAME"
echo "📝 Log  File: $LOG_FILE_NAME"

# Create PARFILE with quoted password
PARFILE="/tmp/expdp_${TABLE_NAME}_$$.par"

cat > "$PARFILE" << EOF
USERID=${DB_USER}/${QUOTED_PASSWORD}@EXPDP_DB
TABLES=${TABLE_NAME}
DIRECTORY=${DATA_PUMP_DIR}
DUMPFILE=${DUMP_FILE_NAME}
LOGFILE=${LOG_FILE_NAME}
REUSE_DUMPFILES=Y
EOF

echo "🚀 Running expdp with parameter file..."

if expdp PARFILE="$PARFILE"; then
  echo -e "${GREEN}✅ expdp backup complete. Stored in Oracle dir '$DATA_PUMP_DIR':${NC}"
  echo "   - $DUMP_FILE_NAME"
  echo "   - $LOG_FILE_NAME"
  exit 0
fi

# If that failed, all we can do is report it
echo -e "${RED}❌ expdp failed. Check log in $DATA_PUMP_DIR: $LOG_FILE_NAME${NC}"
exit 1