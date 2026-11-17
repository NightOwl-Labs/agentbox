#!/bin/bash
# Shared helpers for the Mac mini scripts. Bash 3.2 compatible.
set -euo pipefail
# shellcheck source=../../lib/config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/config.sh"
MINI="$AGENTBOX_ROOT/mini"; export MINI

# Secrets handed over by mini/remote-setup.sh for this run only. Deleted when bootstrap exits.
STATE_DIR="/Users/$ADMIN_USER/.agentbox"
HANDOFF="$STATE_DIR/handoff.env"

require_root() {
  [[ $EUID -eq 0 ]] || fail "Run with sudo."
  [[ "${SUDO_USER:-}" == "$ADMIN_USER" ]] || fail "Run from the $ADMIN_USER account (sudo as $ADMIN_USER)."
}

require_admin_not_root() {
  [[ $EUID -ne 0 ]] || fail "Run this one WITHOUT sudo, as $ADMIN_USER."
  [[ "$(whoami)" == "$ADMIN_USER" ]] || fail "Run as $ADMIN_USER."
}

# handoff NAME: prints a value from the handoff file, failing if it's missing.
handoff() {
  [[ -r "$HANDOFF" ]] || fail "No handoff file. Run mini/remote-setup.sh from your MacBook instead of calling this directly."
  local line
  line="$(grep -E "^$1=" "$HANDOFF" | head -n1)" || fail "$1 missing from the handoff. Re-run prep/06-check.sh on your MacBook."
  printf '%s' "${line#*=}"
}

as_user() { local u="$1"; shift; sudo -u "$u" -H "$@"; }
