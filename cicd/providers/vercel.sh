#!/bin/bash
# Vercel: tokens are only created in the dashboard. Scope it to your team, not "Full Account".
# Sourced by cicd/connect-provider.sh.
token="$(bws_get_or_prompt "$BWS_PROJECT_BOOTSTRAP" VERCEL_API_TOKEN \
  "Paste a Vercel token (Account Settings > Tokens, scoped to your team)")"
http_ok -H "Authorization: Bearer $token" https://api.vercel.com/v2/user || fail "Vercel rejected the token."
team_id="$(curl -fsS -H "Authorization: Bearer $token" https://api.vercel.com/v2/teams | jq -r '.teams[0].id // empty')"
printf '%s' "$token" | set_secret both VERCEL_API_TOKEN
[[ -n "$team_id" ]] && set_var both VERCEL_TEAM_ID "$team_id"
