#!/bin/bash

# Usage:
# ./get_project_id.sh <db_host> <db_port> <db_sid> <db_user> <db_pass> <project_name>
#
# Example:
# ./get_project_id.sh 10.1.1.10 1521 ORCL myuser mypass MY_PROJECT

DB_HOST=$1
DB_PORT=$2
DB_SID=$3
DB_USER=$4
DB_PASS=$5
INPUT_PROJECT=$6
ORACLE_PATH=$7

if [ $# -ne 7 ]; then
  echo "Usage: $0 <db_host> <db_port> <db_sid> <db_user> <db_pass> <project_name> <oracle_path>"
  exit 2
fi


export ORACLE_HOME="$ORACLE_PATH"
export PATH="$ORACLE_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$ORACLE_HOME/lib:$ORACLE_HOME/network/lib:${LD_LIBRARY_PATH:-}"

# SQLPlus connect string
CONNECT_STRING="${DB_USER}/${DB_PASS}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${DB_HOST})(PORT=${DB_PORT}))(CONNECT_DATA=(SID=${DB_SID})))"

# Run SQL and capture output
PROJECT_ID=$(sqlplus -s "$CONNECT_STRING" <<EOF
SET HEADING OFF FEEDBACK OFF VERIFY OFF ECHO OFF PAGESIZE 0
SELECT ID FROM project WHERE NAME = '${INPUT_PROJECT}';
EXIT;
EOF
)

# Trim spaces
PROJECT_ID=$(echo "$PROJECT_ID" | xargs)

if [ -z "$PROJECT_ID" ]; then
  echo "❌ No project_id found for project = ${INPUT_PROJECT}"
  exit 1
else
  echo "✅ project_id for '${INPUT_PROJECT}' is: $PROJECT_ID"
  exit 0
fi