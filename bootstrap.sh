#!/bin/bash
# Runs the full machine setup in order. Run as nladmin:  ./bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")"

./scripts/00-preflight.sh
sudo ./scripts/01-system-settings.sh
./scripts/02-install-tools.sh            # Homebrew must NOT run as root
sudo ./scripts/03-create-users.sh
sudo ./scripts/04-provision-profiles.sh
sudo ./scripts/05-ssh-hardening.sh
sudo ./scripts/06-tailscale.sh
sudo ./scripts/07-drives-and-backups.sh
sudo ./scripts/99-verify.sh

echo
echo "Bootstrap complete. Next: per profile setup (section 6 of the runbook)."
