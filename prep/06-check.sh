#!/bin/bash
# Confirms manual prep is complete before you touch CI/CD or the Mac mini.
# Read only. Prints PASS or FAIL for each item and exits non zero if anything is missing.
set -uo pipefail
# shellcheck source=../lib/config.sh
source "$(dirname "$0")/../lib/config.sh"
# shellcheck source=../lib/bws.sh
source "$AGENTBOX_ROOT/lib/bws.sh"
unset GITHUB_TOKEN GH_TOKEN

FAILED=0
pass() { printf '  \033[1;32mPASS\033[0m %s\n' "$*"; }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; FAILED=1; }
check() { local what="$1"; shift; if ( "$@" ) >/dev/null 2>&1; then pass "$what"; else bad "$what"; fi; }
has_secret() { [[ -n "$(bws_get "$1" "$2" 2>/dev/null)" ]]; }

log "Config"
check "OWNER_EMAIL set"      test -n "${OWNER_EMAIL:-}"
check "WORKER_GH_LOGIN set"  test -n "${WORKER_GH_LOGIN:-}"
check "SSH public key committed in mini/ssh/authorized_keys" bash -c "ls '$AGENTBOX_ROOT'/mini/ssh/authorized_keys/*.pub"

log "Email"
check "MX for $ORG_DOMAIN points at Microsoft 365" bash -c "dig +short MX '$ORG_DOMAIN' | grep -qi 'protection.outlook.com'"

log "Bitwarden"
check "Bootstrap token in Keychain" security find-generic-password -a "$USER" -s "$BWS_KEYCHAIN_SERVICE"
for p in "$BWS_PROJECT_BOOTSTRAP" "$BWS_PROJECT_CODE" "$BWS_PROJECT_ORCH"; do check "Project $p visible" bws_project_id "$p"; done
for u in "${AGENT_USERS[@]}"; do
  check "bootstrap/BWS_TOKEN_$u"    has_secret "$BWS_PROJECT_BOOTSTRAP" "BWS_TOKEN_$u"
  check "bootstrap/MAC_PASSWORD_$u" has_secret "$BWS_PROJECT_BOOTSTRAP" "MAC_PASSWORD_$u"
done

log "Tailscale"
check "bootstrap/TAILSCALE_API_KEY" has_secret "$BWS_PROJECT_BOOTSTRAP" TAILSCALE_API_KEY
check "bootstrap/TAILSCALE_AUTHKEY" has_secret "$BWS_PROJECT_BOOTSTRAP" TAILSCALE_AUTHKEY
check "Tailscale running on this MacBook" bash -c "tailscale status || /Applications/Tailscale.app/Contents/MacOS/Tailscale status"

log "GitHub"
check "You are an owner of $GH_ORG" bash -c "[[ \$(gh api user/memberships/orgs/$GH_ORG --jq .role) == admin ]]"
for t in "$GH_TEAM_HUMANS" "$GH_TEAM_BUILDERS" "$GH_TEAM_ORCH"; do check "Team $t exists" gh api "orgs/$GH_ORG/teams/$t"; done
check "$ORCH_GH_LOGIN is an org member"   bash -c "[[ \$(gh api orgs/$GH_ORG/memberships/$ORCH_GH_LOGIN --jq .state) == active ]]"
check "$WORKER_GH_LOGIN is an org member" bash -c "[[ \$(gh api orgs/$GH_ORG/memberships/$WORKER_GH_LOGIN --jq .state) == active ]]"

log "Agent credentials"
for p in "$BWS_PROJECT_CODE" "$BWS_PROJECT_ORCH"; do
  check "$p/GH_TOKEN"          has_secret "$p" GH_TOKEN
  check "$p/ANTHROPIC_API_KEY" has_secret "$p" ANTHROPIC_API_KEY
done

echo
if [[ $FAILED -eq 0 ]]; then log "Manual prep complete. Next: docs/02-cicd-setup.md"
else fail "Fix the FAIL items above, then re-run."; fi
