#!/bin/bash
# Creates a product repo in the org and applies the guardrails before anyone can push.
# Runs in the platform repo's create-repo workflow with the guardrails App token, which is
# how agents get new repos without ever holding admin rights: org members can't create
# repos, and a repo's creator would otherwise become its admin.
#
# Usage: cicd/create-repo.sh NAME [DESCRIPTION]
set -euo pipefail
# shellcheck source=../lib/config.sh
source "$(dirname "$0")/../lib/config.sh"

name="${1:-}"; desc="${2:-}"
[[ "$name" =~ ^[a-z0-9][a-z0-9-]{1,62}$ ]] || fail "Repo name must be lowercase letters, digits, and dashes: '$name'"
in_reserved=" $GH_EXCLUDE_REPOS $GH_PLATFORM_REPO .github "
[[ "$in_reserved" != *" $name "* ]] || fail "'$name' is reserved."

if gh api "repos/$GH_ORG/$name" --silent 2>/dev/null; then
  log "$GH_ORG/$name already exists; re-applying guardrails only"
else
  # Public by default: products are open source, and free plan protections need public repos.
  jq -n --arg n "$name" --arg d "$desc" '{name: $n, description: $d, visibility: "public",
    auto_init: true, has_wiki: false, has_projects: false, delete_branch_on_merge: true}' | \
    gh api -X POST "orgs/$GH_ORG/repos" --input - --silent
  log "Created $GH_ORG/$name"
fi
"$AGENTBOX_ROOT/cicd/guardrails.sh" "$name"
echo "url=https://github.com/$GH_ORG/$name" >> "${GITHUB_OUTPUT:-/dev/null}"
