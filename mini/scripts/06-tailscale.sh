#!/bin/bash
# Joins the tailnet with the single use, pre-approved, tagged auth key from phase 1.
# Headless tailscaled runs as a system daemon, so Tailscale is up as soon as FileVault
# is unlocked, with nobody logged in. Tagged devices never expire.
source "$(dirname "$0")/lib.sh"
require_root

TS=/opt/homebrew/bin/tailscale
TSD=/opt/homebrew/bin/tailscaled
[[ -x "$TSD" ]] || fail "tailscaled not installed; run 02-install-tools.sh"

if ! launchctl print system/com.tailscale.tailscaled >/dev/null 2>&1; then
  log "Installing tailscaled as a system daemon"
  "$TSD" install-system-daemon
  sleep 3
fi

state="$("$TS" status --json 2>/dev/null | jq -r .BackendState 2>/dev/null || echo unknown)"
if [[ "$state" == "Running" ]]; then
  log "Tailscale already connected"
else
  log "Joining the tailnet as $HOST_NAME ($TAILSCALE_TAG)"
  keyfile="$(mktemp)"; chmod 600 "$keyfile"
  handoff TAILSCALE_AUTHKEY > "$keyfile"
  "$TS" up --auth-key="file:$keyfile" --hostname="$HOST_NAME" --advertise-tags="$TAILSCALE_TAG" --timeout=60s
  rm -f "$keyfile"
fi
"$TS" status | head -n 5
log "Tailscale IP: $("$TS" ip -4)"
