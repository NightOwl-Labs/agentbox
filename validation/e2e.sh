#!/bin/bash
# End to end validation, run on your MacBook. Follows one piece of work through the whole
# system and checks the hard stop held:
#
#   request -> orchestrator plans -> create-repo workflow -> agent-ready issue
#   -> coding agent claims, branches, pushes, opens PR -> orchestrator reviews and comments
#   -> PR is NOT approved by the orchestrator and NOT merged (ORCH_AUTO_APPROVE=false)
#
# Usage:
#   validation/e2e.sh                     files a request in the platform repo for you
#   validation/e2e.sh --watch-repo NAME   you asked by voice instead; watch the repo you named
#   validation/e2e.sh --cleanup NAME      delete a smoke test repo afterwards
set -uo pipefail
# shellcheck source=../lib/config.sh
source "$(dirname "$0")/../lib/config.sh"
unset GITHUB_TOKEN GH_TOKEN
o="$GH_ORG"; platform="$o/$GH_PLATFORM_REPO"
TIMEOUT_MIN="${TIMEOUT_MIN:-45}"
START=$(date +%s)

pass() { printf '  \033[1;32mPASS\033[0m %s (%sm)\n' "$*" $(( ($(date +%s) - START) / 60 )); }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; exit 1; }
# wait_for "description" command...: polls every 20s until the command prints something
wait_for() {
  local what="$1" out; shift
  printf '  ....  %s\r' "$what"
  while true; do
    out="$("$@" 2>/dev/null)"
    if [[ -n "$out" && "$out" != "null" && "$out" != "0" ]]; then pass "$what"; RESULT="$out"; return 0; fi
    [[ $(( $(date +%s) - START )) -gt $(( TIMEOUT_MIN * 60 )) ]] && bad "$what (timed out after ${TIMEOUT_MIN}m; check: ssh -t $ADMIN_USER@$HOST_NAME sudo agentctl status)"
    sleep 20
  done
}

if [[ "${1:-}" == "--cleanup" ]]; then
  [[ "${2:-}" == smoke-* ]] || fail "Only repos named smoke-* are deleted by this script."
  gh auth refresh -h github.com -s delete_repo >/dev/null 2>&1 || true
  gh repo delete "$o/$2" --yes && log "Deleted $o/$2"; exit 0
fi

log "Preconditions"
gh api "repos/$platform" --silent || bad "No platform repo. Finish phase 2."
pass "platform repo exists"
[[ "$(gh variable get ORCH_AUTO_APPROVE --org "$o" 2>/dev/null)" == "false" ]] && pass "hard stop on (org variable ORCH_AUTO_APPROVE=false)" || \
  bad "ORCH_AUTO_APPROVE is not false. Validate with the hard stop on."
ssh -o BatchMode=yes -o ConnectTimeout=10 "$ADMIN_USER@$HOST_NAME" true 2>/dev/null && pass "agent box reachable over Tailscale" || \
  bad "Can't reach $HOST_NAME over Tailscale."

if [[ "${1:-}" == "--watch-repo" ]]; then
  repo="${2:?name the repo you asked for}"
  log "Watching $o/$repo (requested by voice)"
else
  repo="smoke-$(date +%Y%m%d%H%M)"
  log "Filing a request in $platform for repo $repo"
  body="Validation run. Create a new repo named \`$repo\` for a tiny Python command line tool that prints \"hello from $ORG_NAME\". Plan it as exactly ONE agent-ready issue: a hello.py with a pytest test, and a GitHub Actions workflow that runs pytest. Keep it minimal."
  req="$(gh issue create -R "$platform" --title "Validation: $repo" --body "$body" --label "$LABEL_REQUEST" | sed 's#.*/##')"
  pass "request filed: $platform#$req"
  wait_for "orchestrator handled the request" \
    gh issue view "$req" -R "$platform" --json labels --jq "[.labels[].name] | map(select(. == \"$LABEL_REQUEST_DONE\")) | .[0]"
fi

wait_for "repo $o/$repo created by the create-repo workflow" gh api "repos/$o/$repo" --jq .name
wait_for "guardrails applied (ruleset requires code owner review)" \
  gh api "repos/$o/$repo/rulesets" --jq '.[] | select(.name == "agentbox-default-branch") | .id'
wait_for "orchestrator filed an $LABEL_READY issue" \
  gh issue list -R "$o/$repo" --label "$LABEL_READY" --state all --json number --jq '.[0].number'
issue="$RESULT"
wait_for "a coding agent claimed issue #$issue" \
  gh issue view "$issue" -R "$o/$repo" --json labels --jq "[.labels[].name] | map(select(. == \"$LABEL_CLAIMED\")) | .[0]"
wait_for "the coding agent opened a pull request" \
  gh pr list -R "$o/$repo" --state all --author "$WORKER_GH_LOGIN" --json number --jq '.[0].number'
pr="$RESULT"
branch="$(gh pr view "$pr" -R "$o/$repo" --json headRefName --jq .headRefName)"
[[ "$branch" == agent/* ]] && pass "PR #$pr is on agent branch $branch" || bad "PR branch $branch isn't an agent branch"
wait_for "orchestrator ($ORCH_GH_LOGIN) reviewed or commented on PR #$pr" \
  gh api "repos/$o/$repo/pulls/$pr/reviews" --jq "[.[] | select(.user.login == \"$ORCH_GH_LOGIN\")] | length"

log "Hard stop"
approved="$(gh api "repos/$o/$repo/pulls/$pr/reviews" --jq "[.[] | select(.user.login == \"$ORCH_GH_LOGIN\" and .state == \"APPROVED\")] | length")"
[[ "$approved" == "0" ]] && pass "orchestrator did not approve" || bad "orchestrator approved while the hard stop is on"
state="$(gh pr view "$pr" -R "$o/$repo" --json state --jq .state)"
[[ "$state" != "MERGED" ]] && pass "PR not merged (state $state)" || bad "PR was merged without a human"
merge="$(gh pr view "$pr" -R "$o/$repo" --json mergeStateStatus --jq .mergeStateStatus)"
log "Merge state is $merge: GitHub is waiting for a human code owner review, as designed."

cat <<EOF

End to end validation passed in $(( ($(date +%s) - START) / 60 )) minutes.
  PR:   https://github.com/$o/$repo/pull/$pr
You can approve and merge it yourself to see the rest of the flow, then clean up:
  validation/e2e.sh --cleanup $repo
EOF
