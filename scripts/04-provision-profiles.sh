#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_root

log "Installing managed Claude Code policy (hard limits for all accounts)"
install -d -o root -g wheel -m 755 "/Library/Application Support/ClaudeCode"
install -o root -g wheel -m 644 "$REPO_ROOT/policy/managed-settings.json" \
  "/Library/Application Support/ClaudeCode/managed-settings.json"

for u in "${AGENT_USERS[@]}"; do
  src="$REPO_ROOT/profiles/$u"
  home="/Users/$u"
  [[ -d "$src" ]] || fail "Missing profile folder $src"
  log "Provisioning $u"

  install -d -o "$u" -g staff -m 700 "$home/.claude" "$home/bin" "$home/work" "$home/.config" "$home/.config/bws"
  install -o "$u" -g staff -m 600 "$src/settings.json" "$home/.claude/settings.json"
  install -o "$u" -g staff -m 600 "$src/CLAUDE.md"     "$home/.claude/CLAUDE.md"
  install -o "$u" -g staff -m 600 "$src/zshrc"         "$home/.zshrc"
  install -o "$u" -g staff -m 700 "$REPO_ROOT/user/with-secrets" "$home/bin/with-secrets"
  install -o "$u" -g staff -m 700 "$REPO_ROOT/user/user-setup.sh" "$home/bin/user-setup.sh"
  install -o "$u" -g staff -m 600 "$src/secrets.manifest" "$home/.config/bws/secrets.manifest"
done

log "Profiles provisioned. Agents receive copies; the repo stays owned by $ADMIN_USER."
