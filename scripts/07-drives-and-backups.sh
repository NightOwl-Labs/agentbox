#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_root

if [[ -d "/Volumes/$TM_VOLUME" ]]; then
  log "Configuring Time Machine on $TM_VOLUME"
  tmutil setdestination -a "/Volumes/$TM_VOLUME" || warn "tmutil needs Full Disk Access for Terminal."
  tmutil enable
  tmutil destinationinfo
else
  warn "/Volumes/$TM_VOLUME not found, skipping Time Machine."
fi

if [[ -d "/Volumes/$SHARE_VOLUME" ]]; then
  log "Configuring shared handoff drive $SHARE_VOLUME"
  diskutil enableOwnership "/Volumes/$SHARE_VOLUME"
  for d in inbox outbox; do
    install -d -o "$ADMIN_USER" -g "$AGENT_GROUP" -m 2770 "/Volumes/$SHARE_VOLUME/$d"
  done
  log "Agents in group $AGENT_GROUP can read/write inbox and outbox; nobody else can."
else
  warn "/Volumes/$SHARE_VOLUME not found, skipping handoff drive."
fi
