#!/bin/bash
# Creates the agent accounts as standard users with passwords generated in phase 1.
# Created without admin credentials, so they get no Secure Token and can never unlock
# FileVault.
source "$(dirname "$0")/lib.sh"
require_root

create_user() {
  local u="$1" full="$2" pw
  if id "$u" >/dev/null 2>&1; then
    log "$u already exists"
  else
    log "Creating standard user $u ($full)"
    pw="$(handoff "MAC_PASSWORD_$u")"
    sysadminctl -addUser "$u" -fullName "$full" -password "$pw" -shell /bin/zsh -home "/Users/$u" 2>&1 | grep -v '^$' || true
    unset pw
    id "$u" >/dev/null 2>&1 || fail "Creating $u failed."
  fi
  createhomedir -c -u "$u" >/dev/null 2>&1 || true
  if dseditgroup -o checkmember -m "$u" admin >/dev/null 2>&1; then
    warn "$u is an admin, removing"
    dseditgroup -o edit -d "$u" -t user admin
  fi
}
create_user "$CODE_USER" "$CODE_FULLNAME"
create_user "$ORCH_USER" "$ORCH_FULLNAME"

log "Locking down home folders (owner only)"
for u in "$ADMIN_USER" "${AGENT_USERS[@]}"; do chmod 700 "/Users/$u"; done

log "Keeping agent accounts off the FileVault unlock list"
for u in "${AGENT_USERS[@]}"; do
  if fdesetup list | cut -d, -f1 | grep -qx "$u"; then
    warn "$u can unlock FileVault, removing"
    fdesetup remove -user "$u"
  fi
done
fdesetup list
