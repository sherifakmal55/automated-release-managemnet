#!/usr/bin/env bash
set -euo pipefail

###############################################
# USAGE
###############################################
usage() {
  echo "Usage: $0 HOST PORT SID USER PASS SQL_FILE [ORACLE_PATH]"
  exit 2
}

[ "$#" -lt 6 ] && usage

ORACLE_HOST="$1"
ORACLE_PORT="$2"
ORACLE_SID="$3"
ORACLE_USER="$4"
ORACLE_PASS="$5"
SQL_FILE="$6"
ORACLE_PATH="${7:-}"

[ ! -f "$SQL_FILE" ] && { echo "❌ SQL file not found: $SQL_FILE"; exit 1; }

TMPDIR=$(mktemp -d /tmp/sql-exec-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

echo "🔎 Executing SQL file: $SQL_FILE"
echo "   Host: $ORACLE_HOST:$ORACLE_PORT/$ORACLE_SID"
echo "   Temp: $TMPDIR"

###############################################
# ORACLE ENV
###############################################
if [ -n "$ORACLE_PATH" ]; then
  export ORACLE_HOME="$ORACLE_PATH"
  export LD_LIBRARY_PATH="$ORACLE_HOME:$ORACLE_HOME/lib:$ORACLE_HOME/network/lib"
  export PATH="$ORACLE_HOME/bin:$PATH"
fi

CONN_STR="${ORACLE_USER}/${ORACLE_PASS}@${ORACLE_HOST}:${ORACLE_PORT}/${ORACLE_SID}"

SQLPLUS_BIN=$(command -v sqlplus || true)
[ -z "$SQLPLUS_BIN" ] && { echo "❌ sqlplus not found."; exit 1; }

###############################################
# BLOCK TYPE DETECTION
###############################################
detect_block_type() {
  local block="$1"

  # PL/SQL
  if echo "$block" | grep -Eiq '^[[:space:]]*(DECLARE|BEGIN)'; then
    echo "PLSQL"; return
  fi

  if echo "$block" | grep -Eiq '^CREATE[[:space:]]+(OR[[:space:]]+REPLACE[[:space:]]+)?(PROCEDURE|FUNCTION|PACKAGE|TRIGGER|TYPE)'; then
    echo "PLSQL"; return
  fi

  # DDL
  if echo "$block" | grep -Eiq '^[[:space:]]*(CREATE|ALTER|DROP|TRUNCATE|RENAME|COMMENT|GRANT|REVOKE)'; then
    echo "DDL"; return
  fi

  echo "DML"
}

###############################################
# PARSER (SAFE)
###############################################
BLOCKS=()
CURRENT=""
PLSQL_MODE=0

while IFS= read -r line || [ -n "$line" ]; do
  stripped="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  # Enter PLSQL mode
  if [ "$PLSQL_MODE" -eq 0 ]; then
    if echo "$stripped" | grep -Eiq '^(DECLARE|BEGIN)$'; then
      PLSQL_MODE=1
    elif echo "$stripped" | grep -Eiq '^CREATE[[:space:]]+(OR[[:space:]]+REPLACE[[:space:]]+)?(PROCEDURE|FUNCTION|PACKAGE|TRIGGER|TYPE)'; then
      PLSQL_MODE=1
    fi
  fi

  CURRENT+="$line"$'\n'

  # Exit conditions
  if [ "$PLSQL_MODE" -eq 1 ]; then
    if [ "$stripped" = "/" ]; then
      BLOCKS+=("$CURRENT")
      CURRENT=""
      PLSQL_MODE=0
    fi
  else
    if echo "$stripped" | grep -q ';[[:space:]]*$'; then
      BLOCKS+=("$CURRENT")
      CURRENT=""
    elif [ "$stripped" = "/" ]; then
      BLOCKS+=("$CURRENT")
      CURRENT=""
    fi
  fi

done < "$SQL_FILE"

# Flush last block
[ -n "$(echo "$CURRENT" | tr -d '[:space:]')" ] && BLOCKS+=("$CURRENT")

echo "📦 Total blocks/statements parsed: ${#BLOCKS[@]}"

###############################################
# EXECUTION
###############################################
INDEX=0

for BLOCK in "${BLOCKS[@]}"; do
  INDEX=$((INDEX+1))

  WRAPPER="$TMPDIR/block_${INDEX}.sql"
  LOGFILE="$TMPDIR/output_${INDEX}.log"

  BLOCK_TYPE=$(detect_block_type "$BLOCK")

  echo "----------------------------------------"
  echo "🚀 Executing block #$INDEX ($BLOCK_TYPE)"
  echo "----------------------------------------"

  {
    echo "WHENEVER SQLERROR EXIT SQL.SQLCODE"
    echo "SET ECHO ON"
    echo "SET FEEDBACK ON"
    echo "SET VERIFY OFF"
    echo "SET PAGESIZE 0"
    echo "SET SERVEROUTPUT ON SIZE UNLIMITED"
    echo "SET DEFINE OFF"
    echo ""

    echo "PROMPT ---- BEGIN BLOCK $INDEX ($BLOCK_TYPE) ----"
    echo ""

    if [ "$BLOCK_TYPE" = "DDL" ]; then
      CLEAN=$(echo "$BLOCK" | sed 's/[[:space:]]*[;/][[:space:]]*$//')
      printf "%s\n" "$CLEAN"
      echo ";"
      echo "/"

    elif [ "$BLOCK_TYPE" = "PLSQL" ]; then
      CLEAN=$(echo "$BLOCK" | sed '/^[[:space:]]*\/[[:space:]]*$/d')
      printf "%s\n" "$CLEAN"
      echo "/"

    else
      CLEAN=$(echo "$BLOCK" | sed 's/[[:space:]]*;[[:space:]]*$//')

      echo "DECLARE"
      echo "  v_rows NUMBER := 0;"
      echo "BEGIN"
      printf "%s\n" "$CLEAN"
      echo ";"
      echo "  v_rows := SQL%ROWCOUNT;"
      echo "  DBMS_OUTPUT.PUT_LINE(v_rows || ' row(s) affected.');"
      echo "  COMMIT;"
      echo "EXCEPTION"
      echo "  WHEN OTHERS THEN"
      echo "    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);"
      echo "    ROLLBACK;"
      echo "    RAISE;"
      echo "END;"
      echo "/"
    fi

    echo ""
    echo "PROMPT ---- END BLOCK $INDEX ----"
    echo "EXIT"
  } > "$WRAPPER"

  set +e
  "$SQLPLUS_BIN" -s "$CONN_STR" @"$WRAPPER" >"$LOGFILE" 2>&1
  RC=$?
  set -e

  sed -n '1,200p' "$LOGFILE"

  if grep -Eiq 'ORA-[0-9]+|SP2-[0-9]+' "$LOGFILE"; then
    echo "❌ Oracle error detected in block #$INDEX"
    tail -n 200 "$LOGFILE"
    exit 1
  fi

  if [ "$RC" -ne 0 ]; then
    echo "❌ Block #$INDEX FAILED (exit $RC)"
    tail -n 200 "$LOGFILE"
    exit 1
  fi

  echo "✅ Block #$INDEX completed successfully."

done

echo "========================================"
echo "🎉 All ${#BLOCKS[@]} block(s) executed successfully."
echo "========================================"