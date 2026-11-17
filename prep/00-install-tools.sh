#!/bin/bash
# Installs the MacBook tools every later script needs: PowerShell with the Exchange and
# Graph modules, gh, bw, bws, gitleaks. Safe to re-run.
set -euo pipefail
# shellcheck source=../lib/config.sh
source "$(dirname "$0")/../lib/config.sh"
cd "$AGENTBOX_ROOT/prep"

[[ "$(uname -s)" == "Darwin" ]] || fail "Run this on your MacBook."
command -v brew >/dev/null 2>&1 || fail "Install Homebrew first: https://brew.sh"

# PowerShell keeps user modules in ~/.local/share. An earlier sudo install can leave
# ~/.local owned by root, which makes the module install fail partway through.
if ! mkdir -p "$HOME/.local/share" 2>/dev/null || [[ ! -w "$HOME/.local/share" ]]; then
  echo "Can't write to ~/.local/share. It's owned by: $(stat -f %Su "$HOME/.local")" >&2
  echo "Fix it, then re-run:  sudo chown -R \"\$(id -un)\":staff ~/.local" >&2
  exit 1
fi

log "Installing Homebrew packages"
brew bundle --file=Brewfile

log "Installing PowerShell modules"
pwsh -NoLogo -NoProfile -Command '
  $ErrorActionPreference = "Stop"
  foreach ($m in "ExchangeOnlineManagement", "Microsoft.Graph.Authentication", "Microsoft.Graph.Mail") {
    if (Get-Module -ListAvailable -Name $m) { Write-Host "  $m already installed" }
    else {
      Write-Host "  Installing $m"
      Install-PSResource -Name $m -Scope CurrentUser -Repository PSGallery -TrustRepository
    }
  }
'

if [[ "$(bws --version 2>/dev/null || true)" != *"$BWS_VERSION"* ]]; then
  log "Installing bws $BWS_VERSION (checksum verified)"
  arch="$(uname -m)"; [[ "$arch" == "arm64" ]] && arch="aarch64"
  base="https://github.com/bitwarden/sdk-sm/releases/download/bws-v$BWS_VERSION"
  zip="bws-$arch-apple-darwin-$BWS_VERSION.zip"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/$zip" "$base/$zip"
  curl -fsSL -o "$tmp/sums.txt" "$base/bws-sha256-checksums-$BWS_VERSION.txt"
  expected="$(awk -v f="$zip" '$2 == f {print $1}' "$tmp/sums.txt")"
  actual="$(shasum -a 256 "$tmp/$zip" | awk '{print $1}')"
  [[ -n "$expected" && "$expected" == "$actual" ]] || fail "bws checksum mismatch; not installing."
  unzip -q "$tmp/$zip" -d "$tmp"
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$tmp/bws" "$HOME/.local/bin/bws"
  [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || warn "Add ~/.local/bin to your PATH so bws is found."
fi

git -C "$AGENTBOX_ROOT" config core.hooksPath .githooks
log "Done. Next: pwsh prep/01-email-aliases.ps1"
