#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_admin_not_root

log "Checking platform"
[[ "$(uname -m)" == "arm64" ]] || fail "Expected Apple silicon."
sw_vers

log "Checking admin rights"
dseditgroup -o checkmember -m "$ADMIN_USER" admin >/dev/null || fail "$ADMIN_USER is not an admin."

log "Checking FileVault"
fdesetup isactive >/dev/null || fail "FileVault is not on. Turn it on before continuing."

log "Checking Xcode"
xcode-select -p >/dev/null 2>&1 || warn "Xcode / command line tools not found. Install Xcode first (section 2 step 8)."

log "Checking SSH public keys in repo"
ls "$REPO_ROOT"/ssh/authorized_keys/*.pub >/dev/null 2>&1 || fail "No public keys in ssh/authorized_keys/. SSH hardening would lock you out."

log "Preflight OK"
