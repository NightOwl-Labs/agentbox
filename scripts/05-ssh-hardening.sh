#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_root

log "Installing authorized keys"
for u in "$ADMIN_USER" "${AGENT_USERS[@]}"; do
  home="/Users/$u"
  install -d -o "$u" -g staff -m 700 "$home/.ssh"
  cat "$REPO_ROOT"/ssh/authorized_keys/*.pub > "$home/.ssh/authorized_keys"
  chown "$u":staff "$home/.ssh/authorized_keys"
  chmod 600 "$home/.ssh/authorized_keys"
done

log "Restricting SSH to named users (com.apple.access_ssh group)"
dseditgroup -o read com.apple.access_ssh >/dev/null 2>&1 || dseditgroup -o create -q com.apple.access_ssh
# Admin FIRST so you can never lock yourself out
for u in "$ADMIN_USER" "${AGENT_USERS[@]}"; do
  dseditgroup -o edit -a "$u" -t user com.apple.access_ssh
done

log "Installing sshd hardening"
grep -q 'sshd_config.d' /etc/ssh/sshd_config || fail "sshd_config does not include sshd_config.d; edit manually."
install -o root -g wheel -m 644 "$REPO_ROOT/ssh/100-nightowl.conf" /etc/ssh/sshd_config.d/100-nightowl.conf
sshd -t || fail "sshd config test failed; not restarting."

warn "Before continuing: from your MacBook, confirm key login works in a NEW terminal:"
warn "  ssh $ADMIN_USER@$HOST_NAME.local"
confirm "Did key based login work?" || fail "Fix key login first. Password login is still allowed until sshd restarts."

launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true
log "SSH hardened: keys only, named users only."
