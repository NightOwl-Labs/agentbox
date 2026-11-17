#!/bin/bash
# Railway: project tokens are only created in the dashboard (Project Settings > Tokens)
# and are scoped to one project and environment, which is what you want per repo.
# Sourced by cicd/connect-provider.sh.
printf 'Paste the Railway project token for %s (input hidden): ' "$REPO" >/dev/tty
read -rs token </dev/tty; echo >/dev/tty
code="$(curl -s -o /dev/null -w '%{http_code}' https://backboard.railway.com/graphql/v2 \
  -H "Project-Access-Token: $token" -H 'Content-Type: application/json' \
  --data '{"query":"query { projectToken { projectId environmentId } }"}')"
[[ "$code" == "200" ]] || fail "Railway rejected the token (HTTP $code)."
printf '%s' "$token" | set_secret both RAILWAY_TOKEN
