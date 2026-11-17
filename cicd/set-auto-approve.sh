#!/bin/bash
# The hard stop. Turns orchestrator auto approve on or off everywhere it is enforced:
#   1. config.env ORCH_AUTO_APPROVE (commit it)
#   2. org variable ORCH_AUTO_APPROVE, then the guardrails rerun on every repo:
#        off: rulesets require a human code owner review; production needs a human
#        on:  the orchestrator's approval counts; it is also a production reviewer
#   3. the orchestrator's Claude Code permissions on the Mac mini (approve and merge are
#      denied while off). Run mini/remote-setup.sh --reprovision afterwards.
#
# Usage: cicd/set-auto-approve.sh on|off
set -euo pipefail
# shellcheck source=../lib/config.sh
source "$(dirname "$0")/../lib/config.sh"
unset GITHUB_TOKEN GH_TOKEN

case "${1:-}" in on) want=true ;; off) want=false ;; *) fail "Usage: cicd/set-auto-approve.sh on|off" ;; esac

if [[ "$want" == "true" ]]; then
  cat <<EOF
Turning auto approve ON means:
  * The orchestrator can approve and merge pull requests written by the coding agents.
  * Merges to main run the iac workflow, and the orchestrator can approve production
    deployments. Agents can create and change billable infrastructure with no human.
Check first: spending caps on every provider, Claude workspace limits, and that you have
watched the agents work with auto approve off.
EOF
  read -r -p "Type the org name ($GH_ORG) to confirm: " ans </dev/tty
  [[ "$ans" == "$GH_ORG" ]] || fail "Not confirmed. Nothing changed."
fi

sed -i '' -E "s/^ORCH_AUTO_APPROVE=.*/ORCH_AUTO_APPROVE=\"$want\"/" "$AGENTBOX_ROOT/config.env" 2>/dev/null || \
  sed -i -E "s/^ORCH_AUTO_APPROVE=.*/ORCH_AUTO_APPROVE=\"$want\"/" "$AGENTBOX_ROOT/config.env"
gh variable set ORCH_AUTO_APPROVE --org "$GH_ORG" --visibility all --body "$want"
gh workflow run guardrails.yml -R "$GH_ORG/$GH_PLATFORM_REPO"
log "Auto approve is now $1 on GitHub (guardrails rerunning)."
log "Next: commit config.env, then update the Mac mini:  mini/remote-setup.sh --reprovision"
