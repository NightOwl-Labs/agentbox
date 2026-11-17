#!/bin/bash
# Per agent account: installs Claude Code (for that account only, never the admin), sets
# its git identity and GitHub credential helper, and proves its Bitwarden secrets work
# and belong to the right GitHub account.
source "$(dirname "$0")/lib.sh"
require_root

setup_agent() {
  local u="$1" git_name="$2" git_email="$3" gh_login="$4" who
  log "Setting up $u"
  as_user "$u" /bin/bash -c 'command -v claude >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/claude" ]] || curl -fsSL https://claude.ai/install.sh | bash' \
    || fail "Claude Code install failed for $u"
  as_user "$u" "/Users/$u/.local/bin/claude" --version

  as_user "$u" git config --global user.name "$git_name"
  as_user "$u" git config --global user.email "$git_email"
  as_user "$u" git config --global init.defaultBranch main
  as_user "$u" git config --global push.autoSetupRemote true
  # gh reads GH_TOKEN from the environment that with-secrets provides; nothing is stored.
  as_user "$u" git config --global credential.https://github.com.helper '!/opt/homebrew/bin/gh auth git-credential'

  who="$(as_user "$u" "/Users/$u/bin/with-secrets" '/opt/homebrew/bin/gh api user --jq .login')" || \
    fail "$u can't read its Bitwarden secrets or GitHub rejected its token."
  [[ "$who" == "$gh_login" ]] || fail "$u's GH_TOKEN belongs to $who, expected $gh_login."
  as_user "$u" "/Users/$u/bin/with-secrets" 'test -n "$ANTHROPIC_API_KEY"' || fail "$u has no ANTHROPIC_API_KEY."
  log "  $u: Claude Code installed, GitHub as $who, API key present"
}
setup_agent "$CODE_USER" "$ORG_NAME Agents"       "agents@$ORG_DOMAIN"       "$WORKER_GH_LOGIN"
setup_agent "$ORCH_USER" "$ORG_NAME Orchestrator" "orchestrator@$ORG_DOMAIN" "$ORCH_GH_LOGIN"
