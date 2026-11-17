#!/bin/bash
# Creates the guardrails GitHub App and the platform repo, and keeps the platform repo in
# sync with this one. Re-run after changing config.env, guardrails.sh, or the templates.
#
#   1. GitHub App "<GH_ORG>-guardrails" from a manifest: you click Create and Install,
#      the script does the rest. Its ID and key are stored in Bitwarden (bootstrap).
#   2. Repo GH_ORG/platform with the request issue form, create-repo and guardrails
#      workflows, and a copy of the scripts and templates they run.
#   3. Environment platform-admin (protected branches only) holding the App key.
#   4. Applies the guardrails to every repo right away.
set -euo pipefail
# shellcheck source=../lib/config.sh
source "$(dirname "$0")/../lib/config.sh"
# shellcheck source=../lib/bws.sh
source "$AGENTBOX_ROOT/lib/bws.sh"
unset GITHUB_TOKEN GH_TOKEN
o="$GH_ORG"; repo="$o/$GH_PLATFORM_REPO"
APP_NAME="$o-guardrails"

[[ "$(gh api "user/memberships/orgs/$o" --jq .role 2>/dev/null)" == "admin" ]] || \
  fail "Run as an owner of $o: gh auth refresh -h github.com -s admin:org,workflow"

# ---- 1. GitHub App -------------------------------------------------------------------
app_id="$(bws_get "$BWS_PROJECT_BOOTSTRAP" GUARDRAILS_APP_ID)"
if [[ -z "$app_id" ]]; then
  log "Creating the GitHub App $APP_NAME from a manifest"
  manifest="$(jq -n --arg name "$APP_NAME" --arg url "https://github.com/$o" '{
    name: $name, url: $url, public: false, redirect_url: $url,
    hook_attributes: {url: $url, active: false},
    default_permissions: {
      administration: "write", contents: "write", environments: "write", issues: "write",
      metadata: "read", pull_requests: "write", workflows: "write", actions_variables: "read",
      vulnerability_alerts: "write", security_events: "write", members: "read"},
    default_events: []}')"
  page="$(mktemp -t agentbox-app).html"
  cat > "$page" <<EOF
<!doctype html><meta charset="utf-8"><title>Create $APP_NAME</title>
<form id="f" method="post" action="https://github.com/organizations/$o/settings/apps/new?state=agentbox">
<input type="hidden" name="manifest" value='$(printf '%s' "$manifest" | sed "s/'/\&#39;/g")'>
<p>Creating the guardrails GitHub App for $o. If nothing happens, press
<button type="submit">Continue to GitHub</button></p></form>
<script>document.getElementById('f').submit()</script>
EOF
  open "$page"
  echo "In the browser: check the org is $o, click 'Create GitHub App'."
  echo "GitHub then opens https://github.com/$o?code=XXXX&state=agentbox"
  read -r -p "Paste that whole address (or just the code): " answer </dev/tty
  code="$(sed -E 's/.*[?&]code=([^&]+).*/\1/' <<<"$answer")"
  rm -f "$page"
  conv="$(gh api -X POST "app-manifests/$code/conversions")" || fail "Code expired or invalid (it lasts one hour). Re-run."
  app_id="$(jq -r .id <<<"$conv")"; slug="$(jq -r .slug <<<"$conv")"
  jq -r .pem <<<"$conv" | bws_put "$BWS_PROJECT_BOOTSTRAP" GUARDRAILS_APP_PRIVATE_KEY
  printf '%s' "$app_id" | bws_put "$BWS_PROJECT_BOOTSTRAP" GUARDRAILS_APP_ID
  printf '%s' "$slug"   | bws_put "$BWS_PROJECT_BOOTSTRAP" GUARDRAILS_APP_SLUG
fi
slug="$(bws_get "$BWS_PROJECT_BOOTSTRAP" GUARDRAILS_APP_SLUG)"
if ! gh api "orgs/$o/installations" --jq ".installations[].app_slug" | grep -qx "$slug"; then
  open "https://github.com/apps/$slug/installations/new"
  echo "Install $slug on $o with access to ALL repositories (so new repos are covered)."
  until gh api "orgs/$o/installations" --jq ".installations[].app_slug" | grep -qx "$slug"; do sleep 5; done
fi
log "App $slug installed (id $app_id)"

# ---- 2. Platform repo ----------------------------------------------------------------
if ! gh api "repos/$repo" --silent 2>/dev/null; then
  gh repo create "$repo" --public --add-readme --description "$ORG_NAME agent control plane: requests, repo creation, guardrails"
  log "Created $repo"
fi

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
gh repo clone "$repo" "$work/p" -- --quiet
dst="$work/p"
mkdir -p "$dst/lib" "$dst/cicd/templates"
cp "$AGENTBOX_ROOT/config.env" "$dst/config.env"
cp "$AGENTBOX_ROOT/lib/config.sh" "$dst/lib/config.sh"
cp "$AGENTBOX_ROOT/cicd/guardrails.sh" "$AGENTBOX_ROOT/cicd/create-repo.sh" "$dst/cicd/"
rm -rf "$dst/cicd/templates/repo"; cp -R "$AGENTBOX_ROOT/cicd/templates/repo" "$dst/cicd/templates/repo"
(cd "$AGENTBOX_ROOT/cicd/templates/platform" && find . -type f) | while IFS= read -r f; do
  mkdir -p "$dst/$(dirname "$f")"
  render "$AGENTBOX_ROOT/cicd/templates/platform/$f" > "$dst/$f"
done
git -C "$dst" add -A
if git -C "$dst" diff --cached --quiet; then
  log "Platform repo already up to date"
else
  git -C "$dst" -c user.name="agentbox" -c user.email="github@$ORG_DOMAIN" commit -qm "Sync from agentbox $(git -C "$AGENTBOX_ROOT" rev-parse --short HEAD)"
  if git -C "$dst" push -q origin HEAD 2>/dev/null; then
    log "Pushed platform files"
  else
    branch="agentbox-sync-$(date +%Y%m%d%H%M%S)"
    git -C "$dst" push -q origin "HEAD:refs/heads/$branch"
    gh pr create -R "$repo" --head "$branch" --title "Sync from agentbox" \
      --body "Generated by cicd/01-platform-repo.sh. Review and merge to update the platform workflows."
    log "Main is protected: opened a pull request for the update. Merge it to finish."
  fi
fi

# ---- 3. Environment and secrets ------------------------------------------------------
jq -n '{deployment_branch_policy: {protected_branches: true, custom_branch_policies: false}}' | \
  gh api -X PUT "repos/$repo/environments/platform-admin" --input - --silent
bws_get "$BWS_PROJECT_BOOTSTRAP" GUARDRAILS_APP_PRIVATE_KEY | \
  gh secret set GUARDRAILS_APP_PRIVATE_KEY --env platform-admin -R "$repo"
gh variable set GUARDRAILS_APP_ID -R "$repo" --body "$app_id"
log "platform-admin environment ready"

# ---- 4. Guardrails everywhere --------------------------------------------------------
"$AGENTBOX_ROOT/cicd/guardrails.sh" --all
log "Done. From now on the guardrails workflow in $repo re-applies these every hour."
