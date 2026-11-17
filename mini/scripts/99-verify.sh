#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_root

pass() { printf '  \033[1;32mPASS\033[0m %s\n' "$*"; }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; FAILED=1; }
FAILED=0
ok() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$what"; else bad "$what"; fi; }
no() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$what"; else pass "$what"; fi; }

log "Machine"
ok "FileVault on" fdesetup isactive
ok "Firewall on" bash -c "/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -q enabled"
ok "System sleep disabled" bash -c "pmset -g | grep -Eq '^ *sleep +0'"
ok "SSH password login off" bash -c "sshd -T 2>/dev/null | grep -qi '^passwordauthentication no'"
ok "SSH limited to the tailnet (pf anchor loaded)" bash -c "pfctl -a agentbox -s rules 2>/dev/null | grep -q 'port = 22'"
ok "Tailscale connected" bash -c "[[ \$(/opt/homebrew/bin/tailscale status --json | jq -r .BackendState) == Running ]]"
ok "bws installed" test -x /usr/local/bin/bws
ok "Claude Code managed policy installed" test -f "/Library/Application Support/ClaudeCode/managed-settings.json"

log "Admin account is human only"
no "No Claude Code for $ADMIN_USER" test -e "/Users/$ADMIN_USER/.local/bin/claude"
no "No Claude config for $ADMIN_USER" test -e "/Users/$ADMIN_USER/.claude/settings.json"
no "No Bitwarden token for $ADMIN_USER" test -e "/Users/$ADMIN_USER/.config/bws/token"

log "Agent accounts"
for u in "${AGENT_USERS[@]}"; do
  ok "$u exists" id "$u"
  no "$u is not an admin" dseditgroup -o checkmember -m "$u" admin
  no "$u cannot unlock FileVault" bash -c "fdesetup list | cut -d, -f1 | grep -qx $u"
  ok "$u home is 700" bash -c "[[ \$(stat -f %Lp /Users/$u) == 700 ]]"
  ok "$u has Claude Code" test -x "/Users/$u/.local/bin/claude"
  ok "$u Bitwarden token is 600" bash -c "[[ \$(stat -f %Lp /Users/$u/.config/bws/token) == 600 ]]"
  no "$u cannot read admin home" sudo -u "$u" ls "/Users/$ADMIN_USER"
done
no "$CODE_USER cannot read $ORCH_USER home" sudo -u "$CODE_USER" ls "/Users/$ORCH_USER"
no "$ORCH_USER cannot read $CODE_USER home" sudo -u "$ORCH_USER" ls "/Users/$CODE_USER"
if [[ "$ORCH_AUTO_APPROVE" != "true" ]]; then
  ok "Hard stop: orchestrator may not merge" bash -c "jq -e '.permissions.deny | index(\"Bash(gh pr merge:*)\")' /Users/$ORCH_USER/.claude/settings.json"
fi

log "Agent services"
ok "orchestrator running" bash -c "launchctl print system/$LAUNCHD_PREFIX.orchestrator | grep -q 'state = running'"
i=1; while [[ $i -le $WORKER_COUNT ]]; do
  ok "worker-$i running" bash -c "launchctl print system/$LAUNCHD_PREFIX.worker-$i | grep -q 'state = running'"
  i=$((i + 1))
done

[[ $FAILED -eq 0 ]] && log "All checks passed." || fail "Some checks failed."
