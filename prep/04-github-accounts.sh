#!/bin/bash
# Sets up the GitHub identities: checks you own the org, creates the three teams, walks
# you through the one signup GitHub forbids automating, and invites the agent accounts.
# Repo access for the teams is granted later by cicd/guardrails.sh. Dry run unless --apply.
#
#   humans         you (org owner). Code owners: the only approvers while ORCH_AUTO_APPROVE=false
#   builders       WORKER_GH_LOGIN. The coding agents push branches and open PRs as this account
#   orchestrators  ORCH_GH_LOGIN. Reviews PRs, files issues, dispatches platform workflows
#
# The script never sees a password or token.
set -euo pipefail
# shellcheck source=../lib/config.sh
source "$(dirname "$0")/../lib/config.sh"
require_value WORKER_GH_LOGIN

APPLY=0; [[ "${1:-}" == "--apply" ]] && APPLY=1
unset GITHUB_TOKEN GH_TOKEN   # use your stored gh login, not a token inherited from the shell

run() { if [[ $APPLY -eq 1 ]]; then gh api "$@" --silent; else echo "  would run: gh api $*"; fi; }

me="$(gh api user --jq .login 2>/dev/null)" || fail "Log in first: gh auth login -h github.com -s admin:org --web"
role="$(gh api "user/memberships/orgs/$GH_ORG" --jq .role 2>/dev/null)" || \
  fail "Can't read your $GH_ORG membership. Run: gh auth refresh -h github.com -s admin:org"
[[ "$role" == "admin" ]] || fail "$me is '$role' in $GH_ORG; org owner required."
[[ "$me" != "$WORKER_GH_LOGIN" && "$me" != "$ORCH_GH_LOGIN" ]] || \
  fail "Run this as your org owner login, not as an agent account."
log "Signed in as $me, owner of $GH_ORG"

ensure_team() {
  if gh api "orgs/$GH_ORG/teams/$1" --silent 2>/dev/null; then log "team $1 exists"
  else run "orgs/$GH_ORG/teams" -X POST -f "name=$1" -f privacy=closed -f "description=$2"; fi
}
ensure_team "$GH_TEAM_HUMANS"   "Humans. Code owners and production approvers."
ensure_team "$GH_TEAM_BUILDERS" "Coding agents push branches and open pull requests."
ensure_team "$GH_TEAM_ORCH"     "Orchestrator agent. Reviews, files issues, never merges while the hard stop is on."
run "orgs/$GH_ORG/teams/$GH_TEAM_HUMANS/memberships/$me" -X PUT -f role=maintainer

# invite LOGIN TEAM EMAIL: invite an existing account into a team, confirming it's yours.
invite() {
  local login="$1" team="$2" email="$3" account id state ans team_id
  log "$login -> team $team"
  if ! account="$(gh api "users/$login" --jq '"\(.id) \(.created_at)"' 2>/dev/null)"; then
    warn "$login does not exist yet. Create it by hand, then re-run:"
    echo "  1. In a private window, sign up at https://github.com/signup as $login with $email"
    echo "     (the verification mail lands in your inbox, filed under the alias folder)."
    echo "  2. Use the generated password from the Bitwarden item for $login."
    echo "  3. Turn on two factor and save the recovery codes in that Bitwarden item."
    return
  fi
  id="${account%% *}"
  state="$(gh api "orgs/$GH_ORG/memberships/$login" --jq .state 2>/dev/null || true)"
  case "$state" in
    active)  run "orgs/$GH_ORG/teams/$team/memberships/$login" -X PUT -f role=member; log "  member" ;;
    pending) log "  invitation pending: as $login, accept at https://github.com/orgs/$GH_ORG/invitation" ;;
    *)
      echo "  Account: https://github.com/$login (created ${account#* })"
      if [[ $APPLY -eq 1 ]]; then
        read -r -p "  Is this the account you created? [y/N] " ans </dev/tty
        [[ "$ans" =~ ^[Yy]$ ]] || { warn "Skipping $login."; return; }
        team_id="$(gh api "orgs/$GH_ORG/teams/$team" --jq .id)"
        run "orgs/$GH_ORG/invitations" -X POST -F "invitee_id=$id" -f role=direct_member -F "team_ids[]=$team_id"
        log "  invited. As $login, accept at https://github.com/orgs/$GH_ORG/invitation, then re-run --apply."
      else
        echo "  would ask you to confirm the account, then invite it to $GH_ORG in team $team"
      fi ;;
  esac
}
invite "$ORCH_GH_LOGIN"   "$GH_TEAM_ORCH"     "orchestrator@$ORG_DOMAIN"
invite "$WORKER_GH_LOGIN" "$GH_TEAM_BUILDERS" "agents@$ORG_DOMAIN"

[[ $APPLY -eq 1 ]] || log "Dry run. Nothing changed. Re-run with --apply."
