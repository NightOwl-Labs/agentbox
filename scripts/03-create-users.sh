#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_root

for i in "${!AGENT_USERS[@]}"; do
  u="${AGENT_USERS[$i]}"
  full="${AGENT_FULLNAMES[$i]}"
  if id "$u" >/dev/null 2>&1; then
    log "$u already exists, skipping creation"
  else
    log "Creating standard user $u ($full)"
    log "Generate a long random password in Bitwarden, save it, then paste it at the prompt."
    sysadminctl -addUser "$u" -fullName "$full" -password - -shell /bin/zsh
  fi
  createhomedir -c -u "$u" >/dev/null 2>&1 || true

  # Make sure it is NOT an admin
  if dseditgroup -o checkmember -m "$u" admin >/dev/null 2>&1; then
    warn "$u is an admin, removing"
    dseditgroup -o edit -d "$u" -t user admin
  fi
done

log "Creating shared agent group $AGENT_GROUP"
dseditgroup -o read "$AGENT_GROUP" >/dev/null 2>&1 || \
  dseditgroup -o create -r "Night Owl agents" "$AGENT_GROUP"
for u in "${HANDOFF_MEMBERS[@]}"; do
  dseditgroup -o edit -a "$u" -t user "$AGENT_GROUP"
done
# Make sure nobody else is in the handoff group (e.g. the orchestrator)
for u in "${AGENT_USERS[@]}"; do
  # shellcheck disable=SC2076  # literal match is intended
  if [[ ! " ${HANDOFF_MEMBERS[*]} " =~ " $u " ]] && dseditgroup -o checkmember -m "$u" "$AGENT_GROUP" >/dev/null 2>&1; then
    warn "$u should not be in $AGENT_GROUP, removing"
    dseditgroup -o edit -d "$u" -t user "$AGENT_GROUP"
  fi
done

log "Locking down home folders (owner only)"
for u in "$ADMIN_USER" "${AGENT_USERS[@]}"; do
  chmod 700 "/Users/$u"
done

log "Keeping agent accounts off the FileVault unlock list"
for u in "${AGENT_USERS[@]}"; do
  if fdesetup list | cut -d, -f1 | grep -qx "$u"; then
    warn "$u can unlock FileVault, removing"
    fdesetup remove -user "$u"
  fi
done
fdesetup list
