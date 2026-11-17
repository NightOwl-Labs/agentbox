#!/bin/bash
# Sets up the Mac mini from your MacBook over SSH. Run after the manual first boot in
# docs/03-mini-setup.md (admin account created, Remote Login on).
#
#   mini/remote-setup.sh <address>        first run: <address> is the mini's LAN name or IP
#   mini/remote-setup.sh --reprovision    after a config change: sync, re-provision, restart agents
#   mini/remote-setup.sh --sync           copy the repo only
#
# What a first run does:
#   1. Installs your SSH key for the admin (you type the admin password once here).
#   2. Copies this repo (committed HEAD) to ~/agentbox on the mini. No GitHub login there.
#   3. Fetches this run's secrets from Bitwarden (bootstrap project) and hands them over in a
#      600 file that bootstrap deletes when it exits: agent account passwords, each agent's
#      Bitwarden token, and the Tailscale auth key.
#   4. Runs mini/bootstrap.sh over SSH (you type the admin password once more, for sudo).
#   5. Switches to Tailscale and confirms local network SSH is closed.
set -euo pipefail
# shellcheck source=../lib/config.sh
source "$(dirname "$0")/../lib/config.sh"
# shellcheck source=../lib/bws.sh
source "$AGENTBOX_ROOT/lib/bws.sh"

MODE=full; ADDR=""
case "${1:-}" in
  --reprovision) MODE=reprovision ;;
  --sync) MODE=sync ;;
  "") fail "Usage: mini/remote-setup.sh <mini LAN address> | --reprovision | --sync" ;;
  *) ADDR="$1" ;;
esac
[[ -n "$ADDR" ]] || ADDR="$HOST_NAME"      # after the first run, the tailnet name
TARGET="$ADMIN_USER@$ADDR"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30)

# ---- 1. Key login -----------------------------------------------------------------------
pub=""
for k in "$HOME"/.ssh/id_*.pub; do
  [[ -f "$k" ]] || continue
  if cat "$AGENTBOX_ROOT"/mini/ssh/authorized_keys/*.pub 2>/dev/null | grep -qF "$(awk '{print $2}' "$k")"; then pub="$k"; break; fi
done
[[ -n "$pub" ]] || fail "None of your ~/.ssh keys is in mini/ssh/authorized_keys/. Commit your public key first."
if ! ssh "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" true 2>/dev/null; then
  [[ "$MODE" == full ]] || fail "Can't reach $TARGET with your key. Is Tailscale running on this MacBook?"
  log "Installing your key for $ADMIN_USER (enter the $ADMIN_USER password from Bitwarden)"
  ssh-copy-id "${SSH_OPTS[@]}" -i "$pub" "$TARGET"
fi
ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$TARGET" 'mkdir -p ~/.agentbox && chmod 700 ~/.agentbox && touch ~/.agentbox/key-login-verified' || \
  fail "Key login to $TARGET still fails."
log "Key login to $TARGET works"

# ---- 2. Copy the repo -------------------------------------------------------------------
[[ -z "$(git -C "$AGENTBOX_ROOT" status --porcelain)" ]] || \
  warn "You have uncommitted changes. Only the committed HEAD is copied; commit first if you need them."
git -C "$AGENTBOX_ROOT" archive --format=tar HEAD | \
  ssh "${SSH_OPTS[@]}" "$TARGET" 'rm -rf ~/agentbox.new && mkdir -p ~/agentbox.new && tar -x -C ~/agentbox.new &&
    rm -rf ~/agentbox && mv ~/agentbox.new ~/agentbox && chmod 700 ~/agentbox'
log "Copied $(git -C "$AGENTBOX_ROOT" rev-parse --short HEAD) to $TARGET:~/agentbox"
[[ "$MODE" == sync ]] && exit 0

if [[ "$MODE" == reprovision ]]; then
  ssh -t "${SSH_OPTS[@]}" "$TARGET" 'cd ~/agentbox/mini && sudo ./scripts/04-provision-profiles.sh && sudo ./scripts/09-agent-services.sh'
  log "Re-provisioned and restarted the agents."
  exit 0
fi

# ---- 3. Hand over this run's secrets ----------------------------------------------------
log "Fetching this run's secrets from Bitwarden"
handoff_lines() {
  local u k v
  for u in "${AGENT_USERS[@]}"; do
    for k in "BWS_TOKEN_$u" "MAC_PASSWORD_$u"; do
      v="$(bws_get "$BWS_PROJECT_BOOTSTRAP" "$k")"; [[ -n "$v" ]] || fail "bootstrap/$k missing. Run prep/06-check.sh."
      printf '%s=%s\n' "$k" "$v"
    done
  done
  v="$(bws_get "$BWS_PROJECT_BOOTSTRAP" TAILSCALE_AUTHKEY)"; [[ -n "$v" ]] || fail "bootstrap/TAILSCALE_AUTHKEY missing. Run prep/03-tailscale.sh."
  printf 'TAILSCALE_AUTHKEY=%s\n' "$v"
}
handoff_lines | ssh "${SSH_OPTS[@]}" "$TARGET" 'umask 077 && cat > ~/.agentbox/handoff.env'

# ---- 4. Bootstrap -----------------------------------------------------------------------
log "Running the bootstrap on the mini (enter the $ADMIN_USER password once, for sudo)"
ssh -t "${SSH_OPTS[@]}" "$TARGET" 'cd ~/agentbox && ./mini/bootstrap.sh' || {
  ssh "${SSH_OPTS[@]}" "$TARGET" 'rm -f ~/.agentbox/handoff.env' 2>/dev/null || true
  fail "Bootstrap failed. Fix the error above and re-run; every step is safe to repeat."
}

# ---- 5. Switch to Tailscale -------------------------------------------------------------
log "Switching to Tailscale ($ADMIN_USER@$HOST_NAME)"
for _ in $(seq 1 12); do
  ssh "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$ADMIN_USER@$HOST_NAME" true 2>/dev/null && break
  sleep 5
done
ssh "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$ADMIN_USER@$HOST_NAME" true || \
  fail "Can't reach $HOST_NAME over Tailscale. Check Tailscale on this MacBook (MagicDNS on)."
if [[ "$ADDR" != "$HOST_NAME" ]]; then
  if ssh "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$TARGET" true 2>/dev/null; then
    warn "Local network SSH to $ADDR still works. Check 'sudo pfctl -a agentbox -s rules' on the mini."
  else
    log "Local network SSH to $ADDR is closed, as intended"
  fi
fi

cat <<EOF

Mac mini setup complete. The orchestrator and $WORKER_COUNT coding agents are running.
  Status:   ssh -t $ADMIN_USER@$HOST_NAME sudo agentctl status
  Logs:     ssh -t $ADMIN_USER@$HOST_NAME sudo agentctl logs orchestrator
Optional, for voice control from the Claude app (docs/03-mini-setup.md, step 5):
  ssh $ORCH_USER@$HOST_NAME   then: claude, /login, /exit
Next: docs/04-validation.md
EOF
