#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_admin_not_root

log "Checking platform"
[[ "$(uname -m)" == "arm64" ]] || fail "Expected Apple silicon."
sw_vers

log "Checking admin rights"
dseditgroup -o checkmember -m "$ADMIN_USER" admin >/dev/null || fail "$ADMIN_USER is not an admin."

log "Checking FileVault"
fdesetup isactive >/dev/null || fail "FileVault is not on. Turn it on (System Settings > Privacy & Security) before continuing."

log "Checking the handoff from your MacBook"
for k in "BWS_TOKEN_$CODE_USER" "BWS_TOKEN_$ORCH_USER" "MAC_PASSWORD_$CODE_USER" "MAC_PASSWORD_$ORCH_USER" TAILSCALE_AUTHKEY; do
  handoff "$k" >/dev/null
done
[[ "$(stat -f %Lp "$HANDOFF")" == "600" ]] || fail "Handoff file must be mode 600."

log "Checking SSH public keys in repo"
ls "$MINI"/ssh/authorized_keys/*.pub >/dev/null 2>&1 || fail "No public keys in mini/ssh/authorized_keys/. SSH hardening would lock you out."

log "Checking the admin account stays LLM free"
[[ ! -e "/Users/$ADMIN_USER/.local/bin/claude" ]] || fail "Claude Code is installed for $ADMIN_USER. Remove ~/.local/bin/claude and ~/.claude: the admin account is for humans only."

log "Preflight OK"
