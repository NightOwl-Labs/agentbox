#!/bin/bash
# Cloudflare: scripted. A one time "token creator" token (kept in Bitwarden) mints a
# narrowly scoped API token per repo, so no repo ever holds a broad token.
# Sourced by cicd/connect-provider.sh.
CF="https://api.cloudflare.com/client/v4"
creator="$(bws_get_or_prompt "$BWS_PROJECT_BOOTSTRAP" CLOUDFLARE_TOKEN_CREATOR \
  "Paste a Cloudflare user API token made from the 'Create Additional Tokens' template")"
cf() { curl -fsS -H "Authorization: Bearer $creator" -H 'Content-Type: application/json' "$@"; }
cf "$CF/user/tokens/verify" >/dev/null || fail "Cloudflare rejected the token creator token."

account_id="$(cf "$CF/accounts" | jq -r '.result[0].id')"
log "  account $(cf "$CF/accounts" | jq -r '.result[0].name') ($account_id)"

groups="$(cf "$CF/user/tokens/permission_groups")"
pg() { jq -c --arg n "$1" '[.result[] | select(.name == $n) | {id}][0] // empty' <<<"$groups"; }
account_perms="$(for n in "Workers Scripts Write" "Workers KV Storage Write" "Workers R2 Storage Write" \
  "D1 Write" "Pages Write" "Account Settings Read"; do p="$(pg "$n")"; [[ -n "$p" ]] && echo "$p" || warn "permission '$n' not found"; done | jq -sc .)"
zone_perms="$(for n in "DNS Write" "Zone Read"; do p="$(pg "$n")"; [[ -n "$p" ]] && echo "$p"; done | jq -sc .)"

body="$(jq -n --arg name "$GH_ORG/$REPO deploy" --arg acct "com.cloudflare.api.account.$account_id" \
  --argjson ap "$account_perms" --argjson zp "$zone_perms" --arg exp "$(date -u -v+1y +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+1 year' +%Y-%m-%dT%H:%M:%SZ)" '{
  name: $name, expires_on: $exp,
  policies: [
    {effect: "allow", resources: {($acct): "*"}, permission_groups: $ap},
    {effect: "allow", resources: {($acct): {"com.cloudflare.api.account.zone.*": "*"}}, permission_groups: $zp}
  ]}')"
token="$(cf -X POST "$CF/user/tokens" --data-binary "$body" | jq -r .result.value)"
[[ -n "$token" && "$token" != "null" ]] || fail "Cloudflare didn't return a token."

printf '%s' "$token" | set_secret both CLOUDFLARE_API_TOKEN
set_var both CLOUDFLARE_ACCOUNT_ID "$account_id"
log "  token '$GH_ORG/$REPO deploy' expires in one year; re-run this to rotate"
