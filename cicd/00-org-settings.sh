#!/bin/bash
# Org wide GitHub settings that keep agent work safe and auditable. Idempotent.
# Run on your MacBook as the org owner:  cicd/00-org-settings.sh
#
#   repos     members can't create repos (agents use the create-repo workflow); base
#             permission read; no forking of private repos
#   actions   only GitHub, verified, and listed actions run; workflow tokens are read only;
#             workflows can never approve pull requests; outside contributors need approval
#   security  GitHub recommended code security configuration on every repo, and the
#             default for new ones (secret scanning, push protection, Dependabot)
#   switch    org variable ORCH_AUTO_APPROVE, read by the platform workflows
set -euo pipefail
# shellcheck source=../lib/config.sh
source "$(dirname "$0")/../lib/config.sh"
unset GITHUB_TOKEN GH_TOKEN
o="$GH_ORG"

[[ "$(gh api "user/memberships/orgs/$o" --jq .role 2>/dev/null)" == "admin" ]] || \
  fail "Run as an owner of $o: gh auth refresh -h github.com -s admin:org,workflow"

log "Repository policy"
jq -n '{default_repository_permission: "read",
        members_can_create_repositories: false,
        members_can_create_public_repositories: false,
        members_can_create_private_repositories: false,
        members_can_fork_private_repositories: false,
        web_commit_signoff_required: false}' | gh api -X PATCH "orgs/$o" --input - --silent

log "Actions policy"
gh api -X PUT "orgs/$o/actions/permissions" -f enabled_repositories=all -f allowed_actions=selected --silent
jq -n '{github_owned_allowed: true, verified_allowed: true, patterns_allowed: [
  "aquasecurity/trivy-action@*",
  "opentofu/setup-opentofu@*",
  "superfly/flyctl-actions/*",
  "azure/login@*",
  "cloudflare/wrangler-action@*",
  "supabase/setup-cli@*"]}' | gh api -X PUT "orgs/$o/actions/permissions/selected-actions" --input - --silent
gh api -X PUT "orgs/$o/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false --silent
gh api -X PUT "orgs/$o/actions/permissions/fork-pr-contributor-approval" \
  -f approval_policy=all_external_contributors --silent 2>/dev/null || \
  warn "Couldn't set fork PR approval by API; set it in Settings > Actions > General."

log "Code security configuration"
cfg="$(gh api "orgs/$o/code-security/configurations" \
  --jq '[.[] | select(.target_type == "global" and (.name | test("recommended"; "i")))][0].id' 2>/dev/null || true)"
if [[ -n "$cfg" && "$cfg" != "null" ]]; then
  gh api -X POST "orgs/$o/code-security/configurations/$cfg/attach" -f scope=all --silent || warn "attach failed"
  gh api -X PUT "orgs/$o/code-security/configurations/$cfg/defaults" -f default_for_new_repos=all --silent || warn "default failed"
  log "  GitHub recommended configuration attached to all repos and set as default"
else
  warn "No GitHub recommended configuration found; guardrails.sh still enables security per repo."
fi

log "Auto approve switch (org variable ORCH_AUTO_APPROVE=$ORCH_AUTO_APPROVE)"
gh variable set ORCH_AUTO_APPROVE --org "$o" --visibility all --body "$ORCH_AUTO_APPROVE"

cat <<EOF

Done. Three settings have no API; set them by hand (see docs/02-cicd-setup.md, step 1):
  1. Require two factor authentication:  https://github.com/organizations/$o/settings/security
  2. Restrict classic personal access tokens and require approval of fine grained tokens:
     https://github.com/organizations/$o/settings/personal-access-tokens
  3. Members can't change repository visibility or delete repos (Member privileges):
     https://github.com/organizations/$o/settings/member_privileges
EOF
