#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_root

TS=/opt/homebrew/bin/tailscale
TSD=/opt/homebrew/bin/tailscaled
[[ -x "$TSD" ]] || fail "tailscaled not installed; run 02-install-tools.sh"

if ! launchctl print system/com.tailscale.tailscaled >/dev/null 2>&1; then
  log "Installing tailscaled as a system daemon"
  "$TSD" install-system-daemon
fi

log "Bringing Tailscale up. A login URL will appear; open it on your MacBook and approve."
"$TS" up --hostname="$HOST_NAME" || true
"$TS" status

log "MANUAL in the Tailscale admin console:"
log "  1. Machines > $HOST_NAME > Disable key expiry."
log "  2. Access controls: paste the policy from section 5.2 of the runbook."
