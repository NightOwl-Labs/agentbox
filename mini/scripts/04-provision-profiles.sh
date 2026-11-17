#!/bin/bash
# Installs the managed Claude Code policy (hard limits for every account) and gives each
# agent rendered copies of its config. Agents get copies; the repo stays with the admin.
source "$(dirname "$0")/lib.sh"
require_root

log "Installing managed Claude Code policy"
install -d -o root -g wheel -m 755 "/Library/Application Support/ClaudeCode"
install -o root -g wheel -m 644 "$MINI/policy/managed-settings.json" \
  "/Library/Application Support/ClaudeCode/managed-settings.json"

# The hard stop, as Claude Code permissions. Deny rules beat allow rules.
HARD_STOP_DENY='[
  "Bash(gh pr merge:*)",
  "Bash(gh pr review --approve:*)", "Bash(gh pr review -a:*)",
  "Bash(gh pr review * --approve*)", "Bash(gh pr review * -a *)",
  "Bash(gh api *event=APPROVE*)",
  "Bash(gh api repos/*/actions/runs/*/pending_deployments:*)"
]'
# shellcheck disable=SC2034  # APPROVAL_RULE is read by render through TEMPLATE_VARS
if [[ "$ORCH_AUTO_APPROVE" == "true" ]]; then
  APPROVAL_RULE="auto approve is ON. Approve and squash merge only when every check is green and the PR fully meets its issue. You may approve routine production deployments."
else
  APPROVAL_RULE="the hard stop is ON (ORCH_AUTO_APPROVE=false). Never approve or merge. When a PR is ready, post a review comment saying it is ready for human approval. Humans approve merges and production deployments."
fi
TEMPLATE_VARS="$TEMPLATE_VARS APPROVAL_RULE"

provision() {
  local u="$1" profile="$2" home="/Users/$1" tmp
  local src="$MINI/profiles/$profile"
  log "Provisioning $u ($profile)"
  install -d -o "$u" -g staff -m 700 "$home/.claude" "$home/bin" "$home/work" "$home/work/logs" \
    "$home/.config" "$home/.config/bws" "$home/.config/agentbox" "$home/.config/agentbox/prompts"

  tmp="$(mktemp)"
  if [[ "$profile" == "orch" && "$ORCH_AUTO_APPROVE" != "true" ]]; then
    jq --argjson d "$HARD_STOP_DENY" '.permissions.deny += $d' "$src/settings.json" > "$tmp"
  elif [[ "$profile" == "orch" ]]; then
    jq '.permissions.ask -= ["Bash(gh api repos/*/actions/runs/*/pending_deployments:*)"]
        | .permissions.allow += ["Bash(gh api repos/*/actions/runs/*/pending_deployments:*)"]' "$src/settings.json" > "$tmp"
  else
    cp "$src/settings.json" "$tmp"
  fi
  install -o "$u" -g staff -m 600 "$tmp" "$home/.claude/settings.json"
  render "$src/CLAUDE.md" > "$tmp";              install -o "$u" -g staff -m 600 "$tmp" "$home/.claude/CLAUDE.md"
  render "$MINI/profiles/agent.env" > "$tmp";    install -o "$u" -g staff -m 600 "$tmp" "$home/.config/agentbox/agent.env"
  install -o "$u" -g staff -m 600 "$MINI/profiles/zshrc"         "$home/.zshrc"
  install -o "$u" -g staff -m 600 "$src/secrets.manifest"        "$home/.config/bws/secrets.manifest"
  install -o "$u" -g staff -m 700 "$MINI/user/with-secrets"      "$home/bin/with-secrets"
  install -o "$u" -g staff -m 700 "$MINI/user/agent-loop"        "$home/bin/agent-loop"
  [[ "$profile" == "orch" ]] && install -o "$u" -g staff -m 700 "$MINI/user/remote-control" "$home/bin/remote-control"
  for p in "$MINI"/prompts/*.md; do
    render "$p" > "$tmp"; install -o "$u" -g staff -m 600 "$tmp" "$home/.config/agentbox/prompts/$(basename "$p")"
  done

  # This profile's Bitwarden machine account token, from the handoff (never from the repo).
  if [[ -f "$HANDOFF" ]]; then
    handoff "BWS_TOKEN_$u" > "$tmp"
    install -o "$u" -g staff -m 600 "$tmp" "$home/.config/bws/token"
  fi
  rm -f "$tmp"
}
provision "$CODE_USER" code
provision "$ORCH_USER" orch
log "Profiles provisioned (auto approve: $ORCH_AUTO_APPROVE)."
