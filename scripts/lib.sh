#!/bin/bash
# Shared helpers for agentbox scripts.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_ROOT/config.env"

log()  { printf '\033[1;34m[agentbox]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[fail]\033[0m %s\n' "$*"; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || fail "Run with sudo."
  [[ "${SUDO_USER:-}" == "$ADMIN_USER" ]] || fail "Run from the $ADMIN_USER account (sudo as $ADMIN_USER)."
}

require_admin_not_root() {
  [[ $EUID -ne 0 ]] || fail "Run this one WITHOUT sudo, as $ADMIN_USER."
  [[ "$(whoami)" == "$ADMIN_USER" ]] || fail "Run as $ADMIN_USER."
}

confirm() {
  read -r -p "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}
