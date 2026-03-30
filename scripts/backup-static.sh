#!/bin/bash
set -euo pipefail

# Args
DB_HOST=$1
DB_PORT=$2
DB_SERVICE=$3
DB_USER=$4
DB_PASSWORD=$5
ORACLE_PATH=$6
JIRA_ID=$7

# Sanitized Jira ID
SAFE_JIRA="${JIRA_ID//-/}"

# Oracle Data Pump directory object
DATA_PUMP_DIR=RELEASE_MANAGEMENT

# Static tables list
TABLES=(
  "BANK"
  "MESSAGE_FEED"
  "RECS_BDR_LIFECYCLE_HEADER"
  "RECS_BDR_LIFECYCLE_HEADER_LINK"
  "BFIN"
  "RECS_REF_ACCOUNT_PARAM"
)

# Track tables exceeding 200MB
LARGE_TABLES=()

# Track successful backups (actual results)
TMP_CREATED=()
EXPDP_CREATED=()

# Source Oracle profile if available
if [ -f /etc/profile.d/oracle.sh ]; then
  source /etc/profile.d/oracle.sh
fi

export ORACLE_HOME="$ORACLE_PATH"
export PATH="$ORACLE_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$ORACLE_HOME/lib:$ORACLE_HOME/network/lib:${LD_LIBRARY_PATH:-}"


# Validate table existence
echo "Validating required tables..."
for T in "${TABLES[@]}"; do
  EXIST_CHECK=$(sqlplus -s "${DB_USER}/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE}" <<EOF
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT table_name FROM user_tables WHERE table_name = UPPER('$T');
EXIT;
EOF
)

  if [[ -z "$EXIST_CHECK" ]]; then
    echo "Error: Table '$T' does not exist"
    exit 1
  fi
done
echo "All required tables exist."
echo ""

# ---------------------------
# Table size check (200MB)
# ---------------------------
echo "Checking table sizes..."
for T in "${TABLES[@]}"; do
  TABLE_SIZE_MB=$(sqlplus -s "${DB_USER}/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE}" <<EOF
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT NVL(ROUND(BYTES / 1024 / 1024, 2), 0)
FROM user_segments
WHERE segment_type='TABLE' AND segment_name = UPPER('$T');
EXIT;
EOF
)
  TABLE_SIZE_MB=$(echo "$TABLE_SIZE_MB" | xargs)
  INT_MB=${TABLE_SIZE_MB%%.*}

  echo "Table size for $T: ${TABLE_SIZE_MB} MB"

  if [ -n "${INT_MB}" ] && [ "${INT_MB}" -gt 200 ]; then
    echo "Table '$T' exceeds 200MB (${TABLE_SIZE_MB} MB). Will use expdp."
    LARGE_TABLES+=("$T")
  fi
done

echo ""
echo "Table size evaluation completed."
echo ""

# Business checkpoint
echo "Fetching MAX(CORR_ACC_NO) from BANK..."
MAX_ACC=$(sqlplus -s "${DB_USER}/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE}" <<EOF
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT NVL(MAX(CORR_ACC_NO), 0) FROM BANK;
EXIT;
EOF
)
MAX_ACC=$(echo "$MAX_ACC" | xargs)

echo "MAX(CORR_ACC_NO) before static import = $MAX_ACC"
echo "Capture this value in logs!"
echo ""


# TMP table backups (<=200MB)
echo "Creating TMP table backups..."
for T in "${TABLES[@]}"; do
  if [[ " ${LARGE_TABLES[*]} " =~ " ${T} " ]]; then
    continue
  fi

  TMP_TABLE="TMP_${SAFE_JIRA}_${DB_USER}_${T}"
  echo "Backing up $T -> $TMP_TABLE"

  sqlplus -s "${DB_USER}/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE}" <<EOF
WHENEVER SQLERROR EXIT SQL.SQLCODE
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE $TMP_TABLE';
EXCEPTION WHEN OTHERS THEN
    IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE $TMP_TABLE AS SELECT * FROM $T;

EXIT;
EOF

  TMP_CREATED+=("$T")
  echo "Backup created: $TMP_TABLE"
  echo ""
done


# expdp backups (>200MB) - per table
if [ "${#LARGE_TABLES[@]}" -gt 0 ]; then
  echo "Backing up large tables using per-table expdp..."
  echo ""

  for T in "${LARGE_TABLES[@]}"; do
    DUMP_FILE_NAME="${T}_${SAFE_JIRA}_${DB_USER}.dmp"
    LOG_FILE_NAME="${T}_${SAFE_JIRA}_${DB_USER}.log"

    echo "expdp backup for table: $T"

    expdp "${DB_USER}/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE}" \
      TABLES="$T" \
      DIRECTORY="$DATA_PUMP_DIR" \
      DUMPFILE="'${DUMP_FILE_NAME}'" \
      LOGFILE="'${LOG_FILE_NAME}'" \
      REUSE_DUMPFILES=Y

    EXPDP_CREATED+=("$T")

    echo "expdp completed for $T"
    echo "  Dump File : $DUMP_FILE_NAME"
    echo "  Log  File : $LOG_FILE_NAME"
    echo ""
  done
fi


# Summary (actual results)
echo "------------------------------------------------------------"
echo "STATIC IMPORT BACKUP COMPLETED SUCCESSFULLY"
echo "------------------------------------------------------------"
echo "JIRA ID              : $JIRA_ID"
echo "Sanitized JIRA       : $SAFE_JIRA"
echo "Execution Timestamp  : $(date)"
echo ""
echo "MAX(CORR_ACC_NO) before static import:"
echo "       $MAX_ACC"
echo ""

if [ "${#TMP_CREATED[@]}" -gt 0 ]; then
  echo "TMP tables created:"
  for T in "${TMP_CREATED[@]}"; do
    echo "       TMP_${SAFE_JIRA}_${DB_USER}_${T}"
  done
fi

if [ "${#EXPDP_CREATED[@]}" -gt 0 ]; then
  echo ""
  echo "Tables backed up via expdp:"
  for T in "${EXPDP_CREATED[@]}"; do
    echo "       $T"
  done
fi

echo ""
echo "------------------------------------------------------------"
echo "SCRIPT FINISHED"
echo "------------------------------------------------------------"