#!/bin/bash
# Runs the full Mac mini setup in order, as the admin account. Started by
# mini/remote-setup.sh over SSH (you type the admin password once, for sudo).
# Every step is idempotent: safe to re-run after a failure or a config change.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=scripts/lib.sh
source scripts/lib.sh
require_admin_not_root

cleanup() {
  rm -f "$HANDOFF"
  [[ -n "${KEEPALIVE:-}" ]] && kill "$KEEPALIVE" 2>/dev/null
  return 0
}
trap cleanup EXIT

./scripts/00-preflight.sh
log "sudo is needed for most steps; enter the $ADMIN_USER password once."
sudo -v
( while true; do sudo -n true; sleep 50; done ) 2>/dev/null & KEEPALIVE=$!

sudo ./scripts/01-system-settings.sh
./scripts/02-install-tools.sh              # Homebrew must NOT run as root
sudo ./scripts/03-create-users.sh
sudo ./scripts/04-provision-profiles.sh
sudo ./scripts/05-ssh-hardening.sh
sudo ./scripts/06-tailscale.sh
sudo ./scripts/07-backups.sh
sudo ./scripts/08-agent-users.sh
sudo ./scripts/09-agent-services.sh
sudo ./scripts/10-lockdown-ssh.sh
sudo ./scripts/99-verify.sh

log "Bootstrap complete. From now on reach this machine over Tailscale: ssh $ADMIN_USER@$HOST_NAME"
