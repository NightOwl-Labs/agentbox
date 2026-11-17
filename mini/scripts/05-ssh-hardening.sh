#!/bin/bash
# Keys only, named users only. Safe because mini/remote-setup.sh already logged in with
# your key before starting the bootstrap (it leaves a marker to prove it).
source "$(dirname "$0")/lib.sh"
require_root

[[ -f "$STATE_DIR/key-login-verified" ]] || \
  fail "Key login not verified. Run mini/remote-setup.sh from your MacBook; it checks key login first."

log "Installing authorized keys"
for u in "$ADMIN_USER" "${AGENT_USERS[@]}"; do
  home="/Users/$u"
  install -d -o "$u" -g staff -m 700 "$home/.ssh"
  cat "$MINI"/ssh/authorized_keys/*.pub > "$home/.ssh/authorized_keys"
  chown "$u":staff "$home/.ssh/authorized_keys"; chmod 600 "$home/.ssh/authorized_keys"
done

log "Restricting SSH to named users (com.apple.access_ssh group)"
dseditgroup -o read com.apple.access_ssh >/dev/null 2>&1 || dseditgroup -o create -q com.apple.access_ssh
for u in "$ADMIN_USER" "${AGENT_USERS[@]}"; do   # admin first so you can't lock yourself out
  dseditgroup -o edit -a "$u" -t user com.apple.access_ssh
done

log "Installing sshd hardening"
grep -q 'sshd_config.d' /etc/ssh/sshd_config || fail "sshd_config does not include sshd_config.d; edit manually."
rm -f /etc/ssh/sshd_config.d/100-nightowl.conf   # name used by earlier versions of this repo
tmp="$(mktemp)"; render "$MINI/ssh/sshd-hardening.conf" > "$tmp"
install -o root -g wheel -m 644 "$tmp" /etc/ssh/sshd_config.d/100-agentbox.conf; rm -f "$tmp"
sshd -t || fail "sshd config test failed; not restarting."
launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true
log "SSH hardened: keys only, named users only. (Your current session stays open.)"
