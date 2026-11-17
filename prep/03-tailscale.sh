#!/bin/bash
# Tailscale setup, scripted after you create the tailnet and one API access token.
#   1. Stores the API token in the bootstrap project (asks once).
#   2. Pushes the access policy in prep/tailscale-policy.json: only your own signed in
#      devices can reach the agent box, and only on SSH (22).
#   3. Creates a single use, pre-approved auth key tagged for the agent box and stores
#      it in the bootstrap project, so mini setup joins the tailnet with no browser step.
#      Tagged devices never expire, so there is no key expiry to turn off.
#
# Usage: prep/03-tailscale.sh [--new-authkey]
set -euo pipefail
# shellcheck source=../lib/config.sh
source "$(dirname "$0")/../lib/config.sh"
# shellcheck source=../lib/bws.sh
source "$AGENTBOX_ROOT/lib/bws.sh"

API="https://api.tailscale.com/api/v2/tailnet/-"
key="$(bws_get_or_prompt "$BWS_PROJECT_BOOTSTRAP" TAILSCALE_API_KEY "Paste the Tailscale API access token")"
ts() { curl -fsS -u "$key:" "$@"; }

ts "$API/devices" >/dev/null || fail "Tailscale rejected the API token. Make a new one and run: prep/03-tailscale.sh after deleting TAILSCALE_API_KEY in Bitwarden."

log "Access policy"
policy="$(render "$AGENTBOX_ROOT/prep/tailscale-policy.json")"
current="$(ts "$API/acl" -H 'Accept: application/json')"
if [[ "$(jq -S . <<<"$current")" == "$(jq -S . <<<"$policy")" ]]; then
  log "  already applied"
else
  echo "This REPLACES your tailnet policy with:"; echo "$policy"
  confirm "Apply it?" || fail "Not applied. Edit prep/tailscale-policy.json and re-run."
  ts -X POST "$API/acl" -H 'Content-Type: application/json' --data-binary "$policy" >/dev/null
  log "  applied"
fi

log "Agent box auth key"
if [[ -n "$(bws_get "$BWS_PROJECT_BOOTSTRAP" TAILSCALE_AUTHKEY)" && "${1:-}" != "--new-authkey" ]]; then
  log "  already stored (use --new-authkey if it expired; keys last 7 days)"
else
  body="$(jq -n --arg tag "$TAILSCALE_TAG" '{
    capabilities: {devices: {create: {reusable: false, ephemeral: false, preauthorized: true, tags: [$tag]}}},
    expirySeconds: 604800, description: "agentbox mini setup"}')"
  ts -X POST "$API/keys" -H 'Content-Type: application/json' --data-binary "$body" | jq -r .key | \
    bws_put "$BWS_PROJECT_BOOTSTRAP" TAILSCALE_AUTHKEY
fi
log "Done. Install Tailscale on your MacBook and phone and sign in. Never on an employer's device."
