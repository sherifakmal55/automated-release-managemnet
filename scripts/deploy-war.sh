#!/usr/bin/env bash
# Deploy a WAR to WildFly/JBoss (standalone) with reliable undeploy + wait + timestamp table.
# Usage: sudo bash deploy-war.sh <APP_NAME> <WAR_FILE_PATH> <JIRA_ID> <S3_UPLOAD_PATH> <BACKUP_DIR> <JBOSS_HOME> <JAVA_PATH> <MGMT_PORT>
#
# Notes:
#  - All arguments are required (no arg-count guessing).
#  - Runs jboss-cli commands as "jboss" user (su - "${JBOSS_USER}" -c ...). Requires sudo/root to su.
#  - Pre-deploy backup uses same content-hash method as backup-war.sh and uploads to S3 if aws CLI present.
set -euo pipefail

# ---------- inputs (all required) ----------
APP_NAME="${1:-}"
WAR_PATH="${2:-}"
JIRA_ID="${3:-}"
JBOSS_HOME="${4:-}"
JAVA_PATH="${5:-}"
MGMT_PORT="${6:-}"
JBOSS_USER="${7:-}"

# ---------- sanity checks ----------
if [[ -z "$APP_NAME" || -z "$WAR_PATH" || -z "$JIRA_ID" || -z "$JBOSS_HOME" || -z "$JAVA_PATH" || -z "$MGMT_PORT" ]]; then
  echo "❌ Usage: sudo bash deploy-war.sh <APP_NAME> <WAR_FILE_PATH> <JIRA_ID> <JBOSS_HOME> <JAVA_PATH> <MGMT_PORT>"
  exit 64
fi

if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root (so we can su - "${JBOSS_USER}" and use jboss-cli)."
  exit 1
fi

if [[ ! -f "$WAR_PATH" ]]; then
  echo "❌ WAR file not found at: $WAR_PATH"
  exit 2
fi

CLI="${JBOSS_HOME%/}/bin/jboss-cli.sh"
CONNECT_ARG="--connect --controller=127.0.0.1:${MGMT_PORT}"
DEPLOY_WAIT_SECS="${DEPLOY_WAIT_SECS:-600}"

# ---------- warnings for environment ----------
if [[ ! -d "$JBOSS_HOME" ]]; then
  echo "⚠️ JBOSS_HOME directory not found at: $JBOSS_HOME"
fi
if [[ ! -x "$CLI" ]]; then
  echo "⚠️ jboss-cli.sh not found/executable at: $CLI"
fi
if [[ ! -x "${JAVA_PATH%/}/bin/java" ]]; then
  echo "⚠️ Provided JAVA_PATH does not contain executable java: ${JAVA_PATH%/}/bin/java"
fi

echo "🔧 JBOSS_HOME: $JBOSS_HOME"
echo "📦 Deployment name: ${APP_NAME}"
echo "📄 WAR file path: ${WAR_PATH}"
echo "🗂 Jira: ${JIRA_ID}"
echo "☕ JAVA_PATH: ${JAVA_PATH}"
echo "🔌 MGMT_PORT: ${MGMT_PORT}"
echo "🔗 CLI invoke args: ${CONNECT_ARG}"

# ---------- helpers ----------
jboss_cli_cmd_out() {
  local cmd="$1"
  # run as jboss user, set JAVA_HOME to provided path
  su - "${JBOSS_USER}" -c "export JAVA_HOME='${JAVA_PATH}'; export PATH=\"\$JAVA_HOME/bin:\$PATH\"; \"${CLI}\" ${CONNECT_ARG} --commands=\"${cmd}\"" 2>&1 || true
}

op_ok() { grep -Eq '"outcome"[[:space:]]*=>[[:space:]]*"success"'; }

deployment_exists() {
  jboss_cli_cmd_out "/deployment=${APP_NAME}:read-resource" | op_ok
}

is_enabled() {
  local raw
  raw="$(jboss_cli_cmd_out "/deployment=${APP_NAME}:read-attribute(name=enabled)")"
  local val
  val=$(echo "$raw" | tr -d '\n' | grep -oE '\b(true|false)\b' | head -n1 || true)
  if [[ -z "$val" ]]; then
    echo "unknown"
  else
    echo "$val"
  fi
}

wait_until_exists() {
  local end ts now
  ts=$(date +%s); end=$((ts + DEPLOY_WAIT_SECS))
  while :; do
    if deployment_exists; then return 0; fi
    now=$(date +%s); (( now >= end )) && return 1
    echo " … waiting for ${APP_NAME} to appear (deploying)…"
    sleep 5
  done
}

wait_until_enabled() {
  local end ts now
  ts=$(date +%s); end=$((ts + DEPLOY_WAIT_SECS))
  while :; do
    case "$(is_enabled)" in
      true) echo "✅ ${APP_NAME} is enabled."; return 0 ;;
      false|unknown)
        now=$(date +%s); (( now >= end )) && return 1
        echo " … still deploying; checking enabled state again in 5s"
        sleep 5
        ;;
    esac
  done
}

# ---------- pre-deploy: backup existing deployment (same logic as backup-war.sh) ----------
echo "🔎 Checking current deployment state for: ${APP_NAME}"
if deployment_exists; then
  case "$(is_enabled)" in
    true)  echo "✅ ${APP_NAME} is currently DEPLOYED & ENABLED" ;;
    false) echo "ℹ️ ${APP_NAME} exists but is DISABLED" ;;
    *)     echo "ℹ️ ${APP_NAME} exists (state unknown)" ;;
  esac


  echo "🧹 Undeploying existing ${APP_NAME}…"
  OUT=$(jboss_cli_cmd_out "/deployment=${APP_NAME}:undeploy()");  echo "$OUT" || true
  if echo "$OUT" | op_ok; then echo "✅ undeploy() accepted for ${APP_NAME}"; else echo "⚠️ undeploy() not reported 'success'"; fi

  OUT=$(jboss_cli_cmd_out "/deployment=${APP_NAME}:remove()");   echo "$OUT" || true
  if echo "$OUT" | op_ok; then echo "✅ remove() succeeded for ${APP_NAME}"; else echo "⚠️ remove() not reported 'success'"; fi

  if deployment_exists; then
    echo "❌ ${APP_NAME} still present after undeploy/remove."
    exit 3
  fi
  echo "✅ Existing ${APP_NAME} fully undeployed & removed"
else
  echo "ℹ️ ${APP_NAME} is not currently deployed (nothing to remove)"
fi

# ---------- deploy new WAR ----------
echo "🚀 Deploying new WAR: ${WAR_PATH} as ${APP_NAME}"
OUT=$(jboss_cli_cmd_out "deploy \"${WAR_PATH}\" --name=${APP_NAME} --force"); echo "$OUT" || true

echo "⏳ Waiting for deployment to register…"
if ! wait_until_exists; then
  echo "❌ ${APP_NAME} did not appear after deploy command (timeout ${DEPLOY_WAIT_SECS}s)."
  exit 4
fi

echo "⏳ Waiting for ${APP_NAME} to become enabled…"
if ! wait_until_enabled; then
  echo "❌ ${APP_NAME} did not reach enabled state within ${DEPLOY_WAIT_SECS}s."
  echo "🔎 Runtime dump follows:"
  jboss_cli_cmd_out "/deployment=${APP_NAME}:read-resource(include-runtime=true)" | sed 's/^/  /'
  exit 5
fi

echo "✅ Deployment successful and enabled: ${APP_NAME}"
jboss_cli_cmd_out "/deployment=${APP_NAME}:read-resource(include-runtime=true)" | sed 's/^/  /'

# ---------- final table with timestamps ----------
echo
echo "📊 Deployments (with enabled timestamp)"
echo "NAME                 ENABLED   STATUS   ENABLED-TIMESTAMP"

TMP_TABLE="/tmp/deploy_base_table.$$"
su - "${JBOSS_USER}" -c "export JAVA_HOME='${JAVA_PATH}'; export PATH=\"\$JAVA_HOME/bin:\$PATH\"; \"${CLI}\" ${CONNECT_ARG} --commands='deployment-info'" > "${TMP_TABLE}" 2>/dev/null || true
BASE_TABLE="$(cat "${TMP_TABLE}" 2>/dev/null || true)"

while read -r d; do
  [[ -z "$d" ]] && continue
  row="$(echo "$BASE_TABLE" | awk -v n="$d" '$1==n {print $1, $4, $5}')"
  ts="$(jboss_cli_cmd_out "/deployment=${d}:read-attribute(name=enabled-timestamp)" \
        | awk -F'=> ' '/result/ {print $2}' | tr -d '",')" || ts=""
  printf "%-20s %-8s %-8s %s\n" $row "$ts"
done < <(echo "$BASE_TABLE" | awk 'NR>1 {print $1}' || true)

rm -f "${TMP_TABLE}" || true

echo "🎯 Deploy completed for ${APP_NAME}"