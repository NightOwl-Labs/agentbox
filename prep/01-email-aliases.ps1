#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Makes every role address in identities.csv an alias of ONE real mailbox, lets that
  mailbox send as any alias, and files each address into its own folder. Idempotent.
.DESCRIPTION
  No shared mailboxes, no extra licenses, no extra passwords. Every address receives
  into OWNER_EMAIL's inbox, and an inbox rule moves it to Inbox/<folder>/<address> so
  you can see at a glance who a message was for. Replies can be sent from the alias
  (Exchange "send from alias", turned on tenant wide).

  Prints the plan and changes nothing unless -Apply is passed. Sign-in happens in your
  browser; this script never reads or stores a credential.

  Two sign-ins happen with -Apply:
    1. Exchange Online, as a Microsoft 365 admin: adds aliases, enables send from alias.
    2. Microsoft Graph, as the OWNER mailbox: creates folders and inbox rules.
  If you are both, use the same account for both.
.EXAMPLE
  pwsh prep/01-email-aliases.ps1
.EXAMPLE
  pwsh prep/01-email-aliases.ps1 -Apply
.EXAMPLE
  pwsh prep/01-email-aliases.ps1 -Apply -AdminUpn admin@example.onmicrosoft.com
#>
[CmdletBinding()]
param(
  [switch]$Apply,
  [string]$AdminUpn
)
$ErrorActionPreference = 'Stop'

# Read config.env through bash so derived values match every other script.
$root = Split-Path $PSScriptRoot -Parent
$cfg = & bash -c "source '$root/lib/config.sh' >/dev/null && printf '%s\n%s\n%s' `"`$ORG_NAME`" `"`$ORG_DOMAIN`" `"`$OWNER_EMAIL`""
if ($LASTEXITCODE -ne 0) { throw 'config.env failed validation (see message above).' }
$orgName, $domain, $owner = $cfg -split "`n"
if (-not $owner) { throw 'Set OWNER_EMAIL in config.env (the one real mailbox every alias lands in).' }
if (-not $AdminUpn) { $AdminUpn = $owner }

$rows = Import-Csv (Join-Path $PSScriptRoot 'identities.csv')
$plan = foreach ($r in $rows) {
  [pscustomobject]@{
    Address = "$($r.local_part)@$domain"
    Folder  = $r.folder
    Purpose = $r.purpose
  }
}
$dupes = @($plan.Address | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
if ($dupes) { throw "Duplicate addresses in identities.csv: $($dupes -join ', ')" }
$bad = @($plan.Address | Where-Object { $_ -cnotmatch '^[a-z0-9][a-z0-9.-]*@' })
if ($bad) { throw "Invalid addresses in identities.csv: $($bad -join ', ')" }

Write-Host "Plan: $($plan.Count) aliases on $owner, filed under Inbox/$orgName/<folder>/<address>"
foreach ($p in $plan) { Write-Host ("  {0,-34} -> {1}/{2}" -f $p.Address, $p.Folder, ($p.Address -split '@')[0]) }
Write-Host '  + tenant setting: send from alias ON'

if (-not $Apply) {
  Write-Host "`nDry run. Nothing changed. Re-run with -Apply."
  return
}

# ---- 1. Exchange Online: aliases and send from alias --------------------------------
Import-Module ExchangeOnlineManagement
Connect-ExchangeOnline -UserPrincipalName $AdminUpn -ShowBanner:$false
try {
  if (-not (Get-AcceptedDomain | Where-Object DomainName -eq $domain)) {
    throw "$domain is not a verified domain in this tenant. Add it in the Microsoft 365 admin center first."
  }
  $mbx = Get-Mailbox -Identity $owner -ErrorAction Stop

  if (-not (Get-OrganizationConfig).SendFromAliasEnabled) {
    Set-OrganizationConfig -SendFromAliasEnabled $true
    Write-Host 'Send from alias: enabled (can take up to an hour to reach Outlook)'
  } else { Write-Host 'Send from alias: already enabled' }

  foreach ($p in $plan) {
    $holder = $null
    try { $holder = Get-Recipient -Identity $p.Address -ErrorAction Stop } catch { }
    if ($holder -and $holder.ExternalDirectoryObjectId -eq $mbx.ExternalDirectoryObjectId) {
      Write-Host "  alias exists: $($p.Address)"
    } elseif ($holder) {
      Write-Warning "  $($p.Address) already belongs to $($holder.Identity) ($($holder.RecipientTypeDetails)); not moving it"
    } else {
      Set-Mailbox -Identity $owner -EmailAddresses @{ add = "smtp:$($p.Address)" }
      Write-Host "  alias added: $($p.Address)"
    }
  }
} finally {
  Disconnect-ExchangeOnline -Confirm:$false | Out-Null
}

# ---- 2. Microsoft Graph, as the owner: folders and inbox rules ----------------------
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Mail
Write-Host "`nSign in to Microsoft Graph as $owner (folders and rules live in that mailbox)."
Connect-MgGraph -Scopes 'Mail.ReadWrite', 'MailboxSettings.ReadWrite' -NoWelcome
try {
  $me = (Get-MgContext).Account
  if ($me -ne $owner) { throw "Graph is signed in as $me, expected $owner." }

  function Get-OrCreateFolder([string]$ParentId, [string]$Name) {
    $safe = $Name.Replace("'", "''")
    $f = Get-MgUserMailFolderChildFolder -UserId $owner -MailFolderId $ParentId -Filter "displayName eq '$safe'" -All |
      Select-Object -First 1
    if (-not $f) {
      $f = New-MgUserMailFolderChildFolder -UserId $owner -MailFolderId $ParentId -BodyParameter @{ displayName = $Name }
      Write-Host "  folder created: $Name"
    }
    return $f
  }

  $inbox = Get-MgUserMailFolder -UserId $owner -MailFolderId 'inbox'
  $orgFolder = Get-OrCreateFolder $inbox.Id $orgName
  $rules = @(Get-MgUserMailFolderMessageRule -UserId $owner -MailFolderId 'inbox' -All)
  $seq = 10
  foreach ($p in $plan) {
    $group = Get-OrCreateFolder $orgFolder.Id $p.Folder
    $leaf = Get-OrCreateFolder $group.Id (($p.Address -split '@')[0])
    $ruleName = "agentbox: $($p.Address)"
    $body = @{
      displayName = $ruleName
      sequence    = $seq
      isEnabled   = $true
      # headerContains matches the alias in To/Cc headers; the resolved recipient is
      # always the owner, so recipient conditions can't tell aliases apart.
      conditions  = @{ headerContains = @($p.Address) }
      actions     = @{ moveToFolder = $leaf.Id; stopProcessingRules = $true }
    }
    $existing = $rules | Where-Object DisplayName -eq $ruleName | Select-Object -First 1
    if ($existing) {
      Update-MgUserMailFolderMessageRule -UserId $owner -MailFolderId 'inbox' -MessageRuleId $existing.Id -BodyParameter $body | Out-Null
      Write-Host "  rule updated: $($p.Address)"
    } else {
      New-MgUserMailFolderMessageRule -UserId $owner -MailFolderId 'inbox' -BodyParameter $body | Out-Null
      Write-Host "  rule created: $($p.Address)"
    }
    $seq += 1
  }
} finally {
  Disconnect-MgGraph | Out-Null
}

Write-Host "`nDone. Test: send a message to $($plan[0].Address) and check Inbox/$orgName/$($plan[0].Folder)."
Write-Host 'To reply as an alias in Outlook, show the From field and type the alias address.'
