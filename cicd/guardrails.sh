#!/bin/bash
# Applies the agentbox guardrails to one repo, several, or every repo in the org.
# Idempotent. Runs two ways with the same code:
#   * on your MacBook as the org owner:   cicd/guardrails.sh --all
#   * hourly in the platform repo, with the guardrails GitHub App token (guardrails.yml)
#
# For each repo:
#   team access   humans=admin, orchestrators=maintain, builders=write
#                 (agents get nothing on GH_EXCLUDE_REPOS; builders nothing on the platform repo)
#   settings      squash merge only, delete branches on merge, no auto merge
#   security      Dependabot alerts and fixes, secret scanning, push protection, code scanning
#   labels        the agent workflow labels
#   files         CODEOWNERS, security and IaC workflows, Dependabot config (new repos only)
#   ruleset       default branch: PR required, 1 approval, stale approvals dismissed, last
#                 push approval, linear history, no force push or deletion, secret-scan check.
#                 While ORCH_AUTO_APPROVE=false a code owner (the humans team) must approve.
#   environments  preview (open) and production (humans approve; protected branches only)
#
# Usage: cicd/guardrails.sh --all | REPO...
set -euo pipefail
# shellcheck source=../lib/config.sh
source "$(dirname "$0")/../lib/config.sh"
TEMPLATES="$AGENTBOX_ROOT/cicd/templates/repo"
RULESET_NAME="agentbox-default-branch"
o="$GH_ORG"

[[ $# -gt 0 ]] || fail "Usage: cicd/guardrails.sh --all | REPO..."
if [[ "$1" == "--all" ]]; then
  repos="$(gh repo list "$o" --no-archived --limit 1000 --json name --jq '.[].name')"
else
  repos="$*"
fi

in_list() { [[ " $2 " == *" $1 "* ]]; }
team_id() { gh api "orgs/$o/teams/$1" --jq .id; }
HUMANS_ID="$(team_id "$GH_TEAM_HUMANS")"
ORCH_USER_ID="$(gh api "users/$ORCH_GH_LOGIN" --jq .id 2>/dev/null || echo "")"
AUTO="$ORCH_AUTO_APPROVE"

grant_teams() {
  local r="$1"
  gh api -X PUT "orgs/$o/teams/$GH_TEAM_HUMANS/repos/$o/$r" -f permission=admin --silent
  if in_list "$r" "$GH_EXCLUDE_REPOS"; then
    gh api -X DELETE "orgs/$o/teams/$GH_TEAM_ORCH/repos/$o/$r" --silent 2>/dev/null || true
    gh api -X DELETE "orgs/$o/teams/$GH_TEAM_BUILDERS/repos/$o/$r" --silent 2>/dev/null || true
    return
  fi
  gh api -X PUT "orgs/$o/teams/$GH_TEAM_ORCH/repos/$o/$r" -f permission=maintain --silent
  if [[ "$r" == "$GH_PLATFORM_REPO" ]]; then
    gh api -X DELETE "orgs/$o/teams/$GH_TEAM_BUILDERS/repos/$o/$r" --silent 2>/dev/null || true
  else
    gh api -X PUT "orgs/$o/teams/$GH_TEAM_BUILDERS/repos/$o/$r" -f permission=push --silent
  fi
}

repo_settings() {
  gh api -X PATCH "repos/$o/$1" --silent \
    -F delete_branch_on_merge=true -F allow_squash_merge=true -F allow_merge_commit=false \
    -F allow_rebase_merge=false -F allow_auto_merge=false \
    -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY
}

security() {
  local r="$1" vis="$2"
  gh api -X PUT "repos/$o/$r/vulnerability-alerts" --silent 2>/dev/null || warn "$r: Dependabot alerts not enabled"
  gh api -X PUT "repos/$o/$r/automated-security-fixes" --silent 2>/dev/null || warn "$r: Dependabot fixes not enabled"
  if [[ "$vis" == "public" ]]; then
    jq -n '{security_and_analysis: {secret_scanning: {status: "enabled"},
            secret_scanning_push_protection: {status: "enabled"}}}' | \
      gh api -X PATCH "repos/$o/$r" --input - --silent 2>/dev/null || warn "$r: secret scanning not enabled"
    gh api -X PATCH "repos/$o/$r/code-scanning/default-setup" -f state=configured --silent 2>/dev/null || \
      true   # fails harmlessly until the repo has a supported language
  else
    warn "$r is private: secret scanning, code scanning, rulesets, and environment rules need a paid plan on private repos."
  fi
}

labels() {
  local r="$1"
  gh label create "$LABEL_REQUEST"      -R "$o/$r" --force -c 5319e7 -d "Request for the orchestrator" >/dev/null
  gh label create "$LABEL_REQUEST_DONE" -R "$o/$r" --force -c c5def5 -d "Orchestrator handled this request" >/dev/null
  gh label create "$LABEL_READY"        -R "$o/$r" --force -c 0e8a16 -d "Ready for a coding agent" >/dev/null
  gh label create "$LABEL_CLAIMED"      -R "$o/$r" --force -c fbca04 -d "A coding agent is working on it" >/dev/null
  gh label create "$LABEL_PR_OPEN"      -R "$o/$r" --force -c 1d76db -d "Agent opened a pull request" >/dev/null
  gh label create "$LABEL_REWORK"       -R "$o/$r" --force -c d93f0b -d "Orchestrator requested changes" >/dev/null
  gh label create "$LABEL_BLOCKED"      -R "$o/$r" --force -c b60205 -d "Agent is stuck; needs a human" >/dev/null
}

has_file() { gh api "repos/$o/$1/contents/$2" --silent 2>/dev/null; }

seed_files() {
  local r="$1" f path
  while IFS= read -r f; do
    path="${f#"$TEMPLATES"/}"
    has_file "$r" "$path" && continue
    render "$f" | base64 | tr -d '\n' | jq -Rn --arg m "chore: add agentbox guardrail file $path" \
      '{message: $m, content: input}' | \
      gh api -X PUT "repos/$o/$r/contents/$path" --input - --silent
    log "  $r: added $path"
  done < <(find "$TEMPLATES" -type f | sort)
}

ruleset() {
  local r="$1" id checks body
  checks='[]'
  if has_file "$r" ".github/workflows/security.yml" || has_file "$r" ".github/workflows/ci.yml"; then
    checks='[{"context": "secret-scan"}]'
  fi
  body="$(jq -n --arg name "$RULESET_NAME" --argjson checks "$checks" \
    --argjson codeowner "$([[ "$AUTO" == "true" ]] && echo false || echo true)" '{
    name: $name, target: "branch", enforcement: "active", bypass_actors: [],
    conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
    rules: ([
      {type: "deletion"}, {type: "non_fast_forward"}, {type: "required_linear_history"},
      {type: "pull_request", parameters: {
        required_approving_review_count: 1, dismiss_stale_reviews_on_push: true,
        require_code_owner_review: $codeowner, require_last_push_approval: true,
        required_review_thread_resolution: true, allowed_merge_methods: ["squash"]}}
    ] + (if ($checks | length) > 0 then [{type: "required_status_checks", parameters: {
        strict_required_status_checks_policy: false, required_status_checks: $checks}}] else [] end))
  }')"
  id="$(gh api "repos/$o/$r/rulesets" --jq ".[] | select(.name == \"$RULESET_NAME\") | .id" 2>/dev/null || true)"
  if [[ -n "$id" ]]; then gh api -X PUT "repos/$o/$r/rulesets/$id" --input - --silent <<<"$body"
  else gh api -X POST "repos/$o/$r/rulesets" --input - --silent <<<"$body"; fi
}

environments() {
  local r="$1" reviewers
  gh api -X PUT "repos/$o/$r/environments/preview" --silent
  reviewers="$(jq -n --argjson h "$HUMANS_ID" '[{type: "Team", id: $h}]')"
  if [[ "$AUTO" == "true" && -n "$ORCH_USER_ID" ]]; then
    reviewers="$(jq --argjson u "$ORCH_USER_ID" '. + [{type: "User", id: $u}]' <<<"$reviewers")"
  fi
  jq -n --argjson rv "$reviewers" '{wait_timer: 0, prevent_self_review: true, reviewers: $rv,
    deployment_branch_policy: {protected_branches: true, custom_branch_policies: false}}' | \
    gh api -X PUT "repos/$o/$r/environments/production" --input - --silent
}

for r in $repos; do
  log "Guardrails: $o/$r (auto approve: $AUTO)"
  vis="$(gh api "repos/$o/$r" --jq .visibility)"
  grant_teams "$r"
  repo_settings "$r"
  security "$r" "$vis"
  labels "$r"
  if gh api "repos/$o/$r/rulesets" --jq ".[] | select(.name == \"$RULESET_NAME\") | .id" 2>/dev/null | grep -q .; then
    for f in $(cd "$TEMPLATES" && find . -type f | sed 's|^\./||'); do
      has_file "$r" "$f" || warn "  $r: missing $f; add it through a pull request"
    done
  elif ! in_list "$r" "$GH_EXCLUDE_REPOS"; then
    seed_files "$r"   # only before the ruleset exists; afterwards main takes PRs only
  fi
  ruleset "$r"
  environments "$r"
done
log "Guardrails applied."
