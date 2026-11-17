#!/bin/bash
# Optional Time Machine. Formatting is destructive, so this only uses a volume that
# already exists by the name in TIME_MACHINE_VOLUME (see docs/03-mini-setup.md).
source "$(dirname "$0")/lib.sh"
require_root

if [[ -z "$TIME_MACHINE_VOLUME" ]]; then
  log "TIME_MACHINE_VOLUME is empty; skipping Time Machine. (The repo and Bitwarden hold everything irreplaceable.)"
  exit 0
fi
if [[ -d "/Volumes/$TIME_MACHINE_VOLUME" ]]; then
  log "Configuring Time Machine on $TIME_MACHINE_VOLUME"
  tmutil setdestination -a "/Volumes/$TIME_MACHINE_VOLUME" || warn "tmutil may need Full Disk Access for sshd-keygen-wrapper; set Time Machine in System Settings instead."
  tmutil enable
  tmutil destinationinfo
else
  warn "/Volumes/$TIME_MACHINE_VOLUME not found, skipping Time Machine."
fi
