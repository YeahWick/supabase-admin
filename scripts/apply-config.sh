#!/usr/bin/env bash
# Shared helper: fetch current config → diff against desired → plan or apply.
#
# Required environment variables:
#   SUPABASE_ACCESS_TOKEN  – PAT
#   PROJECT_REF            – project reference
#   CONFIG_DIR             – directory containing config JSON files
#   MODE                   – "plan" or "apply"
#   PROJECT_EXISTS         – "true" / "false" (set by determine-state step, plan mode only)
#
# Required arguments:
#   $1  config_file   – filename inside CONFIG_DIR (e.g. "auth.json")
#   $2  plan_key      – key name for plan-parts output (e.g. "auth")
#   $3  api_endpoint  – path after /v1/projects/$PROJECT_REF/ (e.g. "config/auth")
#   $4  http_method   – PATCH | PUT | POST  (method used to apply)
#   $5  jq_filter     – jq expression to extract desired keys from the file, e.g. "." or "{requestedConfig}"
#   $6  trim_mode     – "keyed" | "raw":
#                        "keyed" – trim current response to only keys present in desired
#                        "raw"   – apply jq_filter to current response as-is

set -euo pipefail

CONFIG_FILE="$1"
PLAN_KEY="$2"
API_ENDPOINT="$3"
HTTP_METHOD="$4"
JQ_FILTER="$5"
TRIM_MODE="$6"

api="https://api.supabase.com/v1"
auth="Authorization: Bearer $SUPABASE_ACCESS_TOKEN"
url="$api/projects/$PROJECT_REF/$API_ENDPOINT"

desired=$(jq -S "$JQ_FILTER" "${CONFIG_DIR}/${CONFIG_FILE}")

# ── Plan mode: project doesn't exist ────────────────────────────────────
if [ "$MODE" = "plan" ] && [ "${PROJECT_EXISTS:-}" = "false" ]; then
  jq -n --argjson desired "$desired" '{"status":"create","desired":$desired}' \
    > "/tmp/plan-parts/${PLAN_KEY}.json"
  echo "::notice::${PLAN_KEY}: will be created with project"
  exit 0
fi

# ── Fetch current state ─────────────────────────────────────────────────
current_result=$(curl -s -w "\n%{http_code}" -H "$auth" "$url")
current_code=$(echo "$current_result" | tail -1)
current_body=$(echo "$current_result" | sed '$d')

if [ "$current_code" -ne 200 ]; then
  echo "::error::Failed to fetch current ${PLAN_KEY} config (HTTP $current_code)"
  echo "$current_body"
  exit 1
fi

# ── Trim / filter current state ─────────────────────────────────────────
if [ "$TRIM_MODE" = "keyed" ]; then
  current_trimmed=$(echo "$current_body" | jq -S --argjson d "$desired" \
    '. as $full | $d | keys_unsorted | reduce .[] as $k ({}; . + {($k): $full[$k]})')
else
  current_trimmed=$(echo "$current_body" | jq -S "$JQ_FILTER")
fi

# ── No changes? ─────────────────────────────────────────────────────────
if [ "$desired" = "$current_trimmed" ]; then
  echo "::notice::${PLAN_KEY}: no changes"
  if [ "$MODE" = "plan" ]; then
    echo '{"status":"no-change"}' > "/tmp/plan-parts/${PLAN_KEY}.json"
  fi
  exit 0
fi

# ── Compute diff ────────────────────────────────────────────────────────
diff_json=$(jq -n --argjson desired "$desired" --argjson current "$current_trimmed" '
  [$desired | keys[] | select($desired[.] != $current[.])] |
  reduce .[] as $k ({}; . + {($k): {"current": $current[$k], "desired": $desired[$k]}})')

if [ "$MODE" = "plan" ]; then
  jq -n --argjson diff "$diff_json" '{"status":"changed","diff":$diff}' \
    > "/tmp/plan-parts/${PLAN_KEY}.json"
  echo "::notice::${PLAN_KEY}: changes detected (plan mode, not applying)"
  exit 0
fi

# ── Apply ───────────────────────────────────────────────────────────────
result=$(curl -s -w "\n%{http_code}" \
  -X "$HTTP_METHOD" -H "$auth" -H "Content-Type: application/json" \
  -d "$desired" "$url")

code=$(echo "$result" | tail -1)
body=$(echo "$result" | sed '$d')

if [ "$code" -eq 200 ] || [ "$code" -eq 201 ]; then
  echo "::notice::${PLAN_KEY} applied successfully"
else
  echo "::error::Failed to apply ${PLAN_KEY} (HTTP $code)"
  echo "$body"
  exit 1
fi
