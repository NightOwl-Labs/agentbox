#!/bin/bash
# Run once as the agent user (nlcode, nlorch, or nlfinance) over SSH or Screen Sharing.
set -euo pipefail
me="$(whoami)"
echo "Setting up $me"

# 1. Claude Code (native installer, per user, into ~/.local/bin)
if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
fi

# 2. Bitwarden Secrets Manager token for THIS profile's machine account
if [[ ! -s "$HOME/.config/bws/token" ]]; then
  echo "Paste the access token for machine account mini-${me#nl} (input hidden):"
  read -rs token
  umask 077
  printf '%s' "$token" > "$HOME/.config/bws/token"
  unset token
fi
chmod 600 "$HOME/.config/bws/token"

# 3. Git identity (coding profile)
if [[ "$me" == "nlcode" ]]; then
  git config --global user.name  "Night Owl Agents"
  git config --global user.email "agents@nightowl-labs.dev"
  git config --global init.defaultBranch main
  git config --global push.autoSetupRemote true
  if ! gh auth status >/dev/null 2>&1; then
    echo "Paste the WORKER fine grained GitHub token (input hidden):"
    read -rs ghtoken
    printf '%s' "$ghtoken" | gh auth login --with-token
    unset ghtoken
  fi
  gh auth setup-git
fi

# 4. Orchestrator: GitHub identity is the nightowl-orchestrator machine user
if [[ "$me" == "nlorch" ]]; then
  git config --global user.name  "Night Owl Orchestrator"
  git config --global user.email "orchestrator@nightowl-labs.dev"
  git config --global init.defaultBranch main
  if ! gh auth status >/dev/null 2>&1; then
    echo "Paste the nightowl-orchestrator GitHub token (input hidden):"
    read -rs ghtoken
    printf '%s' "$ghtoken" | gh auth login --with-token
    unset ghtoken
  fi
  gh auth status
fi

echo
echo "Next: run 'claude' once and complete login."
echo "Then test secrets: with-secrets 'env | grep -c .'"
