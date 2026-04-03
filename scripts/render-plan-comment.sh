#!/usr/bin/env bash
# Render a markdown plan comment from the assembled plan JSON.
#
# Required environment variables:
#   PLAN_JSON        – the assembled plan JSON string
#   PROJECT_REF      – project reference
#   PROJECT_NAME     – display name for header (may be empty)
#   ENVIRONMENT      – environment label for header (may be empty)
#   PLAN_COMMENT_FILE – path to write the rendered markdown

set -euo pipefail

# ── Header ──────────────────────────────────────────────────────────────
project_action=$(echo "$PLAN_JSON" | jq -r '.project_action')
has_changes=$(echo "$PLAN_JSON" | jq -r '.has_changes')
plan=$(echo "$PLAN_JSON" | jq -c '.changes')

comment="<!-- supa-plan:${PROJECT_REF} -->"$'\n'

if [ -n "$PROJECT_NAME" ]; then
  header="$PROJECT_NAME"
else
  header="$PROJECT_REF"
fi
if [ -n "$ENVIRONMENT" ]; then
  header="$header ($ENVIRONMENT)"
fi

if [ "$project_action" = "delete" ]; then
  comment+="## Supabase Plan: ${header}"$'\n'
  comment+="> :rotating_light: **This project will be DELETED on apply.**"$'\n\n'
elif [ "$project_action" = "create" ]; then
  comment+="## Supabase Plan: ${header}"$'\n'
  comment+="> :seedling: **New project — all config will be created.**"$'\n\n'
else
  comment+="## Supabase Plan: ${header}"$'\n\n'
fi

if [ "$has_changes" != "true" ] && [ "$project_action" = "update" ]; then
  comment+="Everything is up to date. No changes will be applied on merge."$'\n'
else
  # ── Config sections with table diffs ──────────────────────────────────
  render_keyed_section() {
    local section="$1" nice_name="$2"
    local status
    status=$(echo "$plan" | jq -r ".$section.status // \"absent\"")
    [ "$status" = "absent" ] && return

    if [ "$status" = "no-change" ]; then
      comment+="### ${nice_name} — no changes"$'\n\n'
    elif [ "$status" = "changed" ]; then
      comment+="### ${nice_name} — :warning: changes detected"$'\n'
      comment+="| Key | Current | Desired |"$'\n'
      comment+="|-----|---------|---------|"$'\n'
      for k in $(echo "$plan" | jq -r ".$section.diff | keys[]"); do
        local current desired
        current=$(echo "$plan" | jq -c ".$section.diff.\"$k\".current")
        desired=$(echo "$plan" | jq -c ".$section.diff.\"$k\".desired")
        comment+="| \`$k\` | \`$current\` | \`$desired\` |"$'\n'
      done
      comment+=$'\n'
    elif [ "$status" = "create" ]; then
      comment+="### ${nice_name} — :seedling: will be created"$'\n\n'
    fi
  }

  render_keyed_section "auth"          "Auth Config"
  render_keyed_section "postgrest"     "PostgREST Config"
  render_keyed_section "realtime"      "Realtime Config"
  render_keyed_section "storage-config" "Storage Config"

  # ── Network restrictions ──────────────────────────────────────────────
  net_status=$(echo "$plan" | jq -r '.network.status // "absent"')
  if [ "$net_status" != "absent" ]; then
    if [ "$net_status" = "no-change" ]; then
      comment+="### Network Restrictions — no changes"$'\n\n'
    elif [ "$net_status" = "changed" ]; then
      comment+="### Network Restrictions — :warning: changes detected"$'\n'
      comment+="| Key | Current | Desired |"$'\n'
      comment+="|-----|---------|---------|"$'\n'
      current=$(echo "$plan" | jq -c '.network.diff.dbAllowedCidrs.current')
      desired=$(echo "$plan" | jq -c '.network.diff.dbAllowedCidrs.desired')
      comment+="| \`dbAllowedCidrs\` | \`$current\` | \`$desired\` |"$'\n\n'
    elif [ "$net_status" = "create" ]; then
      comment+="### Network Restrictions — :seedling: will be created"$'\n\n'
    fi
  fi

  # ── SSL enforcement ──────────────────────────────────────────────────
  ssl_status=$(echo "$plan" | jq -r '.ssl.status // "absent"')
  if [ "$ssl_status" != "absent" ]; then
    if [ "$ssl_status" = "no-change" ]; then
      comment+="### SSL Enforcement — no changes"$'\n\n'
    elif [ "$ssl_status" = "changed" ]; then
      comment+="### SSL Enforcement — :warning: changes detected"$'\n'
      comment+="| Key | Current | Desired |"$'\n'
      comment+="|-----|---------|---------|"$'\n'
      current=$(echo "$plan" | jq -c '.ssl.diff.requestedConfig.current')
      desired=$(echo "$plan" | jq -c '.ssl.diff.requestedConfig.desired')
      comment+="| \`requestedConfig\` | \`$current\` | \`$desired\` |"$'\n\n'
    elif [ "$ssl_status" = "create" ]; then
      comment+="### SSL Enforcement — :seedling: will be created"$'\n\n'
    fi
  fi

  # ── Storage buckets ──────────────────────────────────────────────────
  buckets_status=$(echo "$plan" | jq -r '."storage-buckets".status // "absent"')
  if [ "$buckets_status" != "absent" ]; then
    if [ "$buckets_status" = "no-change" ]; then
      comment+="### Storage Buckets — no changes"$'\n\n'
    elif [ "$buckets_status" = "changed" ]; then
      comment+="### Storage Buckets — :warning: changes detected"$'\n'
      comment+="| Bucket | Action | Details |"$'\n'
      comment+="|--------|--------|---------|"$'\n'
      for row in $(echo "$plan" | jq -c '."storage-buckets".buckets[]'); do
        bname=$(echo "$row" | jq -r '.name')
        baction=$(echo "$row" | jq -r '.action')
        if [ "$baction" = "create" ]; then
          comment+="| \`$bname\` | **create** | — |"$'\n'
        else
          changes=$(echo "$row" | jq -c '.changes // {}' | sed 's/"/`/g')
          comment+="| \`$bname\` | update | $changes |"$'\n'
        fi
      done
      comment+=$'\n'
    elif [ "$buckets_status" = "create" ]; then
      comment+="### Storage Buckets — :seedling: will be created"$'\n\n'
    fi
  fi

  # ── SQL migrations ───────────────────────────────────────────────────
  mig_status=$(echo "$plan" | jq -r '.migrations.status // "absent"')
  if [ "$mig_status" != "absent" ]; then
    if [ "$mig_status" = "no-change" ]; then
      comment+="### SQL Migrations — no pending"$'\n\n'
    elif [ "$mig_status" = "pending" ]; then
      count=$(echo "$plan" | jq '.migrations.pending | length')
      comment+="### SQL Migrations — :warning: ${count} pending"$'\n'
      for m in $(echo "$plan" | jq -r '.migrations.pending[]'); do
        comment+="- \`$m\`"$'\n'
      done
      comment+=$'\n'
    fi
  fi

  # ── Edge functions ───────────────────────────────────────────────────
  func_status=$(echo "$plan" | jq -r '.functions.status // "absent"')
  if [ "$func_status" != "absent" ]; then
    if [ "$func_status" = "no-change" ]; then
      comment+="### Edge Functions — no changes"$'\n\n'
    elif [ "$func_status" = "changed" ]; then
      comment+="### Edge Functions — :warning: changes detected"$'\n'
      comment+="| Function | Action |"$'\n'
      comment+="|----------|--------|"$'\n'
      for row in $(echo "$plan" | jq -c '.functions.functions[]'); do
        fname=$(echo "$row" | jq -r '.name')
        faction=$(echo "$row" | jq -r '.action')
        if [ "$faction" = "create" ]; then
          comment+="| \`$fname\` | **create** |"$'\n'
        else
          comment+="| \`$fname\` | update |"$'\n'
        fi
      done
      comment+=$'\n'
    fi
  fi

  # ── Secrets ──────────────────────────────────────────────────────────
  sec_status=$(echo "$plan" | jq -r '.secrets.status // "absent"')
  if [ "$sec_status" = "present" ]; then
    sec_count=$(echo "$plan" | jq -r '.secrets.key_count')
    comment+="### Secrets — ${sec_count} key(s) present"$'\n'
    comment+="> Secret values are not diffed. Apply to sync."$'\n\n'
  fi

  comment+="---"$'\n'
  comment+="Comment \`/supa-apply\` to apply these changes, or \`/supa-plan\` to re-run the plan."$'\n'
fi

echo "$comment" > "$PLAN_COMMENT_FILE"
echo "::notice::Plan comment written to $PLAN_COMMENT_FILE"
