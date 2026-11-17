#!/bin/bash
# Netlify: personal access tokens are only created in the dashboard.
# Sourced by cicd/connect-provider.sh.
token="$(bws_get_or_prompt "$BWS_PROJECT_BOOTSTRAP" NETLIFY_API_TOKEN \
  "Paste a Netlify personal access token (User settings > Applications)")"
http_ok -H "Authorization: Bearer $token" https://api.netlify.com/api/v1/user || fail "Netlify rejected the token."
slug="$(curl -fsS -H "Authorization: Bearer $token" https://api.netlify.com/api/v1/accounts | jq -r '.[0].slug')"
printf '%s' "$token" | set_secret both NETLIFY_API_TOKEN
set_var both NETLIFY_ACCOUNT_SLUG "$slug"
