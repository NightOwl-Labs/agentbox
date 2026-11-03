#!/bin/bash
# Installs PowerShell and the Microsoft modules that manage mailboxes and aliases.
# Exchange Online PowerShell is required: Azure CLI and Microsoft Graph cannot add
# aliases, because proxyAddresses is read-only for them.
set -euo pipefail
cd "$(dirname "$0")"

command -v brew >/dev/null 2>&1 || { echo "Install Homebrew first: https://brew.sh"; exit 1; }

# PowerShell keeps user modules in ~/.local/share. An earlier sudo install can leave
# ~/.local owned by root, which makes the module install fail partway through.
if ! mkdir -p "$HOME/.local/share" 2>/dev/null || [[ ! -w "$HOME/.local/share" ]]; then
  echo "Can't write to ~/.local/share. It's owned by: $(stat -f %Su "$HOME/.local")" >&2
  echo "Fix it, then re-run this script:" >&2
  echo "  sudo chown -R \"\$(id -un)\":staff ~/.local" >&2
  exit 1
fi

brew bundle --file=Brewfile

pwsh -NoLogo -NoProfile -Command '
  $ErrorActionPreference = "Stop"
  foreach ($m in "ExchangeOnlineManagement", "Microsoft.Graph.Users") {
    if (Get-Module -ListAvailable -Name $m) { Write-Host "$m already installed" }
    else {
      Write-Host "Installing $m"
      Install-PSResource -Name $m -Scope CurrentUser -Repository PSGallery -TrustRepository
    }
  }
'

git -C .. config core.hooksPath .githooks
echo "Done. Next: pwsh identity/02-create-mailboxes.ps1 -AdminUpn <you> -OwnerUpn <you>"
