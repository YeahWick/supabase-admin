#!/usr/bin/env bash
# Shared helper: apply network restrictions (specialised because API uses POST
# to .../apply endpoint and sorts CIDR arrays for comparison).
#
# Required environment variables: same as apply-config.sh
# No arguments – all config is hard-coded for network restrictions.

set -euo pipefail

api="https://api.supabase.com/v1"
auth="Authorization: Bearer $SUPABASE_ACCESS_TOKEN"
url="$api/projects/$PROJECT_REF/network-restrictions"

desired=$(jq -S '{dbAllowedCidrs}' "${CONFIG_DIR}/network.json")

# ── Plan mode: project doesn't exist ────────────────────────────────────
if [ "$MODE" = "plan" ] && [ "${PROJECT_EXISTS:-}" = "false" ]; then
  jq -n --argjson desired "$desired" \
    '{"status":"create","diff":{"dbAllowedCidrs":{"current":[],"desired":$desired.dbAllowedCidrs}}}' \
    > /tmp/plan-parts/network.json
  echo "::notice::Network restrictions: will be created with project"
  exit 0
fi

# ── Fetch current ───────────────────────────────────────────────────────
current_result=$(curl -s -w "\n%{http_code}" -H "$auth" "$url")
current_code=$(echo "$current_result" | tail -1)
current_body=$(echo "$current_result" | sed '$d')

if [ "$current_code" -ne 200 ]; then
  echo "::error::Failed to fetch current network restrictions (HTTP $current_code)"
  echo "$current_body"
  exit 1
fi

# Sort CIDR arrays for deterministic comparison
desired_sorted=$(echo "$desired" | jq -S '{dbAllowedCidrs: (.dbAllowedCidrs | sort)}')
current_sorted=$(echo "$current_body" | jq -S '{dbAllowedCidrs: (.dbAllowedCidrs // [] | sort)}')

if [ "$desired_sorted" = "$current_sorted" ]; then
  echo "::notice::Network restrictions: no changes"
  if [ "$MODE" = "plan" ]; then
    echo '{"status":"no-change"}' > /tmp/plan-parts/network.json
  fi
  exit 0
fi

if [ "$MODE" = "plan" ]; then
  jq -n --argjson desired "$desired_sorted" --argjson current "$current_sorted" \
    '{"status":"changed","diff":{"dbAllowedCidrs":{"current":$current.dbAllowedCidrs,"desired":$desired.dbAllowedCidrs}}}' \
    > /tmp/plan-parts/network.json
  echo "::notice::Network restrictions: changes detected (plan mode, not applying)"
  exit 0
fi

# ── Apply ───────────────────────────────────────────────────────────────
result=$(curl -s -w "\n%{http_code}" \
  -X POST -H "$auth" -H "Content-Type: application/json" \
  -d "$desired" "$url/apply")

code=$(echo "$result" | tail -1)
body=$(echo "$result" | sed '$d')

if [ "$code" -eq 200 ] || [ "$code" -eq 201 ]; then
  echo "::notice::Network restrictions applied successfully"
else
  echo "::error::Failed to apply network restrictions (HTTP $code)"
  echo "$body"
  exit 1
fi
