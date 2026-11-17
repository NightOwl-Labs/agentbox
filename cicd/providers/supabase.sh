#!/bin/bash
# Supabase: personal access tokens are only created in the dashboard and can see every
# project in the account, so use a dedicated Supabase organization for agent products.
# Sourced by cicd/connect-provider.sh.
token="$(bws_get_or_prompt "$BWS_PROJECT_BOOTSTRAP" SUPABASE_ACCESS_TOKEN \
  "Paste a Supabase access token (Account > Access Tokens)")"
http_ok -H "Authorization: Bearer $token" https://api.supabase.com/v1/projects || fail "Supabase rejected the token."
orgs="$(curl -fsS -H "Authorization: Bearer $token" https://api.supabase.com/v1/organizations)"
org_id="$(jq -r '.[0].id' <<<"$orgs")"
[[ "$(jq length <<<"$orgs")" -gt 1 ]] && warn "Several Supabase orgs; using $(jq -r '.[0].name' <<<"$orgs"). Set SUPABASE_ORG_ID by hand to change."
printf '%s' "$token" | set_secret both SUPABASE_ACCESS_TOKEN
set_var both SUPABASE_ORG_ID "$org_id"
