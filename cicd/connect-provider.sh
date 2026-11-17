#!/bin/bash
# Connects one hosting or cloud provider to one product repo, so its iac workflow can
# provision from infra/. Credentials go into the repo's GitHub environments only
# (preview and production), never onto the Mac mini. Re-run to rotate.
#
# Usage: cicd/connect-provider.sh PROVIDER REPO [options]
#   PROVIDER: azure | cloudflare | supabase | vercel | netlify | fly | railway | render
#
# Reusable account level tokens are kept in Bitwarden (bootstrap project) so you paste each
# one once, not once per repo.
set -euo pipefail
# shellcheck source=../lib/config.sh
source "$(dirname "$0")/../lib/config.sh"
# shellcheck source=../lib/bws.sh
source "$AGENTBOX_ROOT/lib/bws.sh"
unset GITHUB_TOKEN GH_TOKEN

provider="${1:-}"; REPO="${2:-}"; shift 2 2>/dev/null || true
script="$AGENTBOX_ROOT/cicd/providers/$provider.sh"
[[ -n "$provider" && -f "$script" ]] || fail "Usage: cicd/connect-provider.sh {azure|cloudflare|supabase|vercel|netlify|fly|railway|render} REPO"
[[ -n "$REPO" ]] || fail "Name the repo to connect."
gh api "repos/$GH_ORG/$REPO/environments/production" --silent 2>/dev/null || \
  fail "$GH_ORG/$REPO has no production environment yet. Run: cicd/guardrails.sh $REPO"
FULL_REPO="$GH_ORG/$REPO"

# set_secret ENV NAME: value from stdin. ENV is preview, production, or both.
set_secret() {
  local envs="$1" name="$2" value e
  value="$(cat)"
  [[ "$envs" == "both" ]] && envs="preview production"
  for e in $envs; do printf '%s' "$value" | gh secret set "$name" --env "$e" -R "$FULL_REPO"; done
  log "  $name -> $1"
}
set_var() {
  local envs="$1" e
  [[ "$envs" == "both" ]] && envs="preview production"
  for e in $envs; do gh variable set "$2" --env "$e" -R "$FULL_REPO" --body "$3"; done
  log "  $2=$3 -> $1"
}
need() { command -v "$1" >/dev/null 2>&1 || { log "Installing $2"; brew install "$2"; }; }
http_ok() { [[ "$(curl -s -o /dev/null -w '%{http_code}' "$@")" == "200" ]]; }

log "Connecting $provider to $FULL_REPO"
# shellcheck source=/dev/null
source "$script"
log "Done. Add infra/$provider/ to $REPO and open a pull request to see a plan."
