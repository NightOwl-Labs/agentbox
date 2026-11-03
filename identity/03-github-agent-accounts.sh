#!/bin/bash
# Adds the agent GitHub accounts in identities.csv to the org. Dry run unless --apply.
#
# GitHub requires a human to create each account and forbids automated signup, and it
# has no API for it, so this script walks you through signup and automates the rest:
# team, repo permission, and org invitation. It never sees a password or token.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=/dev/null
source ./config.env

APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

# Use your stored gh login, not a token inherited from the shell.
unset GITHUB_TOKEN GH_TOKEN

log()  { printf '\033[1;34m[github]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[fail]\033[0m %s\n' "$*"; exit 1; }
run()  { # Mutating calls go through here so a dry run cannot change anything.
  if [[ $APPLY -eq 1 ]]; then gh api "$@" --silent; else echo "  would run: gh api $*"; fi
}

role="$(gh api "user/memberships/orgs/$GH_ORG" --jq .role 2>/dev/null)" || \
  fail "Can't read your $GH_ORG membership. Log in with the org owner account, then: gh auth refresh -h github.com -s admin:org"
[[ "$role" == "admin" ]] || fail "$(gh api user --jq .login) is '$role' in $GH_ORG; org owner required."

repos="$(gh repo list "$GH_ORG" --no-archived --limit 500 --json name --jq '.[].name')"

while IFS=, read -r _kind key _display primary _aliases login team permission || [[ -n "${key:-}" ]]; do
  [[ "$key" == "key" || -z "$login" ]] && continue
  email="$primary@$MAIL_DOMAIN"
  log "$key: $login ($email)"

  if ! account="$(gh api "users/$login" --jq '"\(.id) \(.created_at)"' 2>/dev/null)"; then
    warn "$login does not exist yet. Create it by hand, then re-run:"
    echo "  1. Sign up at https://github.com/signup as $login with $email"
    echo "     (verification mail arrives in the shared mailbox)."
    echo "  2. Turn on two factor. Save the password and recovery codes in your personal Bitwarden vault."
    continue
  fi
  id="${account%% *}"

  if ! gh api "orgs/$GH_ORG/teams/$team" --silent 2>/dev/null; then
    run "orgs/$GH_ORG/teams" -X POST -f "name=$team" -f privacy=closed
  fi
  while IFS= read -r repo; do
    [[ -z "$repo" || " $GH_TEAM_EXCLUDE_REPOS " == *" $repo "* ]] && continue
    run "orgs/$GH_ORG/teams/$team/repos/$GH_ORG/$repo" -X PUT -f "permission=$permission"
  done <<< "$repos"

  state="$(gh api "orgs/$GH_ORG/memberships/$login" --jq .state 2>/dev/null || true)"
  case "$state" in
    active)
      run "orgs/$GH_ORG/teams/$team/memberships/$login" -X PUT -f role=member
      log "$login is an org member" ;;
    pending)
      log "$login has a pending invitation: accept it at https://github.com/orgs/$GH_ORG/invitation" ;;
    *)
      # Login names are first come, first served: don't invite a stranger.
      echo "  Account: https://github.com/$login (created ${account#* })"
      if [[ $APPLY -eq 1 ]]; then
        read -r -p "  Is this the account you created? [y/N] " ans </dev/tty
        [[ "$ans" =~ ^[Yy]$ ]] || { warn "Skipping $login."; continue; }
        team_id="$(gh api "orgs/$GH_ORG/teams/$team" --jq .id)"
        run "orgs/$GH_ORG/invitations" -X POST -F "invitee_id=$id" -f role=direct_member -F "team_ids[]=$team_id"
        log "Invited. As $login, accept at https://github.com/orgs/$GH_ORG/invitation"
      else
        echo "  would ask you to confirm the account, then invite it to $GH_ORG in team $team"
      fi ;;
  esac
done < identities.csv

[[ $APPLY -eq 1 ]] || log "Dry run. Nothing changed. Re-run with --apply."
