#!/bin/bash
# Stores each agent profile's two credentials in its own Secrets Manager project, after
# checking that each one works and belongs to the right account:
#
#   project        GH_TOKEN                               ANTHROPIC_API_KEY
#   coding         fine grained token of WORKER_GH_LOGIN  key from the "coding" workspace
#   orchestrator   fine grained token of ORCH_GH_LOGIN    key from the "orchestrator" workspace
#
# GitHub and Anthropic only create these in their web consoles; see
# docs/01-manual-prep.md steps 4 and 5 for the exact scopes. Re-run any time to rotate:
#   prep/05-agent-credentials.sh --rotate
set -euo pipefail
# shellcheck source=../lib/config.sh
source "$(dirname "$0")/../lib/config.sh"
# shellcheck source=../lib/bws.sh
source "$AGENTBOX_ROOT/lib/bws.sh"
require_value WORKER_GH_LOGIN
ROTATE=0; [[ "${1:-}" == "--rotate" ]] && ROTATE=1

ask() { local v; printf '%s (input hidden): ' "$1" >/dev/tty; read -rs v </dev/tty; echo >/dev/tty; printf '%s' "$v"; }

store_github() {
  local project="$1" login="$2" token who
  if [[ $ROTATE -eq 0 && -n "$(bws_get "$project" GH_TOKEN)" ]]; then log "$project/GH_TOKEN already stored"; return; fi
  token="$(ask "Paste the fine grained GitHub token for $login")"
  who="$(GH_TOKEN="$token" gh api user --jq .login 2>/dev/null)" || fail "GitHub rejected that token."
  [[ "$who" == "$login" ]] || fail "That token belongs to $who, expected $login."
  GH_TOKEN="$token" gh api "orgs/$GH_ORG" --silent 2>/dev/null || \
    fail "The token can't see $GH_ORG. Set its resource owner to $GH_ORG (and approve it if the org requires approval)."
  printf '%s' "$token" | bws_put "$project" GH_TOKEN
}

store_anthropic() {
  local project="$1" workspace="$2" key code
  if [[ $ROTATE -eq 0 && -n "$(bws_get "$project" ANTHROPIC_API_KEY)" ]]; then log "$project/ANTHROPIC_API_KEY already stored"; return; fi
  key="$(ask "Paste the Claude API key from the '$workspace' workspace")"
  code="$(curl -s -o /dev/null -w '%{http_code}' https://api.anthropic.com/v1/models \
    -H "x-api-key: $key" -H 'anthropic-version: 2023-06-01')"
  [[ "$code" == "200" ]] || fail "Anthropic rejected that key (HTTP $code)."
  printf '%s' "$key" | bws_put "$project" ANTHROPIC_API_KEY
}

log "Coding agents"
store_github    "$BWS_PROJECT_CODE" "$WORKER_GH_LOGIN"
store_anthropic "$BWS_PROJECT_CODE" "coding"
log "Orchestrator"
store_github    "$BWS_PROJECT_ORCH" "$ORCH_GH_LOGIN"
store_anthropic "$BWS_PROJECT_ORCH" "orchestrator"
log "Done. Next: prep/06-check.sh"
