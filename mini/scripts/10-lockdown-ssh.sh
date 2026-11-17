#!/bin/bash
# Closes local network SSH now that Tailscale is up: SSH (22) and Screen Sharing (5900)
# are accepted only from tailnet addresses. Your current LAN session stays open (pf keeps
# established connections); new ones must use ssh <admin>@<HOST_NAME> over Tailscale.
source "$(dirname "$0")/lib.sh"
require_root

TS=/opt/homebrew/bin/tailscale
[[ "$("$TS" status --json 2>/dev/null | jq -r .BackendState)" == "Running" ]] || \
  fail "Tailscale isn't connected. Not locking down SSH, or you'd be locked out."
"$TS" ip -4 | grep -q '^100\.' || fail "No tailnet address. Not locking down SSH."

log "Installing pf rules: SSH only from the tailnet"
install -o root -g wheel -m 644 "$MINI/pf/agentbox.anchor"   /etc/pf.anchors/agentbox
install -o root -g wheel -m 644 "$MINI/pf/pf.agentbox.conf"  /etc/pf.agentbox.conf
pfctl -n -f /etc/pf.agentbox.conf || fail "pf rules failed to parse; nothing changed."

label="$LAUNCHD_PREFIX.pf"
cat > "/Library/LaunchDaemons/$label.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array><string>/sbin/pfctl</string><string>-E</string><string>-f</string><string>/etc/pf.agentbox.conf</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
chown root:wheel "/Library/LaunchDaemons/$label.plist"; chmod 644 "/Library/LaunchDaemons/$label.plist"
launchctl bootout "system/$label" 2>/dev/null || true
launchctl bootstrap system "/Library/LaunchDaemons/$label.plist"
sleep 1
pfctl -a agentbox -s rules
log "Local network SSH closed. Reach this machine with: ssh $ADMIN_USER@$HOST_NAME (Tailscale)"
