#!/bin/bash
# Installs PowerShell and the Microsoft modules that manage mailboxes and aliases.
# Exchange Online PowerShell is required: Azure CLI and Microsoft Graph cannot add
# aliases, because proxyAddresses is read-only for them.
set -euo pipefail
cd "$(dirname "$0")"

command -v brew >/dev/null 2>&1 || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
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
