#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_admin_not_root

if ! command -v brew >/dev/null 2>&1 && [[ ! -x /opt/homebrew/bin/brew ]]; then
  log "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null || \
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"

log "Installing Brewfile packages"
brew bundle --file="$REPO_ROOT/Brewfile"

log "Installing bws $BWS_VERSION to /usr/local/bin (no Homebrew formula; agents need it on a shared path)"
if [[ "$(/usr/local/bin/bws --version 2>/dev/null || true)" != *"$BWS_VERSION"* ]]; then
  base="https://github.com/bitwarden/sdk-sm/releases/download/bws-v$BWS_VERSION"
  zip="bws-aarch64-apple-darwin-$BWS_VERSION.zip"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/$zip" "$base/$zip"
  curl -fsSL -o "$tmp/sums.txt" "$base/bws-sha256-checksums-$BWS_VERSION.txt"
  expected="$(awk -v f="$zip" '$2 == f {print $1}' "$tmp/sums.txt")"
  actual="$(shasum -a 256 "$tmp/$zip" | awk '{print $1}')"
  [[ -n "$expected" && "$expected" == "$actual" ]] || fail "bws checksum mismatch; not installing."
  unzip -q "$tmp/$zip" -d "$tmp"
  sudo install -d -o root -g wheel -m 755 /usr/local/bin
  sudo install -o root -g wheel -m 755 "$tmp/bws" /usr/local/bin/bws
fi

brew analytics off
log "Tools installed. Agent accounts can run these, but only $ADMIN_USER can install or upgrade them."
