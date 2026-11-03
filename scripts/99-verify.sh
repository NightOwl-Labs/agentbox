#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_root

pass() { printf '  \033[1;32mPASS\033[0m %s\n' "$*"; }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; FAILED=1; }
FAILED=0

log "Verifying"
fdesetup isactive >/dev/null && pass "FileVault on" || bad "FileVault off"

for u in "${AGENT_USERS[@]}"; do
  id "$u" >/dev/null 2>&1 && pass "$u exists" || bad "$u missing"
  dseditgroup -o checkmember -m "$u" admin >/dev/null 2>&1 && bad "$u is admin" || pass "$u is standard"
  fdesetup list | cut -d, -f1 | grep -qx "$u" && bad "$u can unlock FileVault" || pass "$u cannot unlock FileVault"
  [[ "$(stat -f %Lp "/Users/$u")" == "700" ]] && pass "$u home is 700" || bad "$u home not 700"
done

for a in "${AGENT_USERS[@]}"; do
  for b in "${AGENT_USERS[@]}"; do
    [[ "$a" == "$b" ]] && continue
    if sudo -u "$a" ls "/Users/$b" >/dev/null 2>&1; then bad "$a can read /Users/$b"; else pass "$a cannot read /Users/$b"; fi
  done
  if sudo -u "$a" ls "/Users/$ADMIN_USER" >/dev/null 2>&1; then bad "$a can read admin home"; else pass "$a cannot read admin home"; fi
done

sshd -T 2>/dev/null | grep -qi '^passwordauthentication no' && pass "SSH password login off" || bad "SSH password login on"
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -q enabled && pass "Firewall on" || bad "Firewall off"
pmset -g | grep -Eq '^ *sleep +0' && pass "System sleep disabled" || bad "System sleep enabled"
dseditgroup -o checkmember -m nlorch "$AGENT_GROUP" >/dev/null 2>&1 && bad "nlorch is in the handoff group" || pass "nlorch kept off the handoff drive"
[[ -f "/Library/Application Support/ClaudeCode/managed-settings.json" ]] && pass "Claude Code managed policy installed" || bad "Managed policy missing"
[[ -x /usr/local/bin/bws ]] && pass "bws installed" || bad "bws missing"
/opt/homebrew/bin/tailscale status >/dev/null 2>&1 && pass "Tailscale connected" || bad "Tailscale not connected"

[[ $FAILED -eq 0 ]] && log "All checks passed." || fail "Some checks failed."
