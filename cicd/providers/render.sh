#!/bin/bash
# Render: API keys are only created in the dashboard and cover the whole account, so use a
# dedicated Render workspace for agent products. Sourced by cicd/connect-provider.sh.
key="$(bws_get_or_prompt "$BWS_PROJECT_BOOTSTRAP" RENDER_API_KEY \
  "Paste a Render API key (Account Settings > API Keys)")"
http_ok -H "Authorization: Bearer $key" "https://api.render.com/v1/owners?limit=20" || fail "Render rejected the key."
owner="$(curl -fsS -H "Authorization: Bearer $key" "https://api.render.com/v1/owners?limit=20" | jq -r '.[0].owner.id')"
printf '%s' "$key" | set_secret both RENDER_API_KEY
set_var both RENDER_OWNER_ID "$owner"
