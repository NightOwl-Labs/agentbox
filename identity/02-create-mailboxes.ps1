#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Creates a shared mailbox and aliases for each row in identities.csv. Idempotent.
.DESCRIPTION
  Prints the plan and changes nothing unless -Apply is passed. Shared mailboxes need
  no license and have no password anyone uses; sign-in is blocked on each one. Only
  the owner gets access. Agents never get mailbox credentials.
  Sign-in happens in your browser. This script never reads or stores a credential.
.EXAMPLE
  pwsh identity/02-create-mailboxes.ps1
.EXAMPLE
  pwsh identity/02-create-mailboxes.ps1 -Apply -AdminUpn you@contoso.com -OwnerUpn you@contoso.com
#>
[CmdletBinding()]
param(
  [switch]$Apply,
  [string]$AdminUpn,
  [string]$OwnerUpn
)
$ErrorActionPreference = 'Stop'

$domain = (Get-Content (Join-Path $PSScriptRoot 'config.env') |
  Where-Object { $_ -match '^MAIL_DOMAIN=' }) -replace '^MAIL_DOMAIN="?([^"]*)"?$', '$1'
if (-not $domain) { throw 'MAIL_DOMAIN missing from config.env' }

$rows = Import-Csv (Join-Path $PSScriptRoot 'identities.csv')

# Validate the whole manifest before touching anything.
$plan = foreach ($r in $rows) {
  [pscustomobject]@{
    Kind        = $r.kind
    DisplayName = $r.display_name
    LocalPart   = $r.primary
    Address     = "$($r.primary)@$domain"
    Aliases     = @($r.aliases -split ';' | Where-Object { $_ } | ForEach-Object { "$_@$domain" })
  }
}
$all = @($plan | ForEach-Object { $_.Address }) + @($plan | ForEach-Object { $_.Aliases })
$dupes = @($all | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
if ($dupes) { throw "Duplicate addresses in identities.csv: $($dupes -join ', ')" }
$bad = @($all | Where-Object { $_ -cnotmatch '^[a-z0-9][a-z0-9.-]*@' })
if ($bad) { throw "Invalid addresses in identities.csv: $($bad -join ', ')" }

Write-Host "Plan: $($plan.Count) shared mailboxes, $($all.Count - $plan.Count) aliases on $domain"
foreach ($p in $plan) {
  $suffix = if ($p.Aliases) { " + $($p.Aliases -join ', ')" } else { '' }
  Write-Host ("  [{0}] {1}{2}" -f $p.Kind, $p.Address, $suffix)
}

if (-not $Apply) {
  Write-Host "`nDry run. Nothing changed. Re-run with -Apply -AdminUpn <upn> -OwnerUpn <upn>."
  return
}
if (-not $AdminUpn -or -not $OwnerUpn) { throw '-Apply requires -AdminUpn and -OwnerUpn' }

function Invoke-WithRetry([scriptblock]$Action, [string]$What) {
  # New mailboxes take a while to replicate across Exchange and Entra.
  foreach ($attempt in 1..8) {
    try { return & $Action }
    catch {
      if ($attempt -eq 8) { throw }
      Write-Host "    waiting for replication: $What (attempt $attempt)"
      Start-Sleep -Seconds 20
    }
  }
}

function Find-Recipient([string]$Address) {
  try { Get-Recipient -Identity $Address -ErrorAction Stop } catch { $null }
}

Import-Module ExchangeOnlineManagement
Import-Module Microsoft.Graph.Users
Connect-ExchangeOnline -UserPrincipalName $AdminUpn -ShowBanner:$false
Connect-MgGraph -Scopes 'User.ReadWrite.All' -NoWelcome

try {
  if (-not (Get-AcceptedDomain | Where-Object DomainName -eq $domain)) {
    throw "$domain is not a verified domain in this tenant. Add it in the Microsoft 365 admin center first."
  }

  foreach ($p in $plan) {
    Write-Host "`n$($p.Address)"
    $existing = Find-Recipient $p.Address
    if ($existing -and $existing.RecipientTypeDetails -ne 'SharedMailbox') {
      Write-Warning "  already used by a $($existing.RecipientTypeDetails) ($($existing.Identity)); skipping this row"
      continue
    }
    if ($existing) { Write-Host '  mailbox exists' }
    else {
      New-Mailbox -Shared -Name $p.DisplayName -DisplayName $p.DisplayName -Alias $p.LocalPart `
        -PrimarySmtpAddress $p.Address | Out-Null
      Write-Host '  mailbox created'
    }
    $mbx = Invoke-WithRetry { Get-Mailbox -Identity $p.Address -ErrorAction Stop } 'mailbox lookup'

    foreach ($alias in $p.Aliases) {
      $holder = Find-Recipient $alias
      if ($holder -and $holder.ExternalDirectoryObjectId -eq $mbx.ExternalDirectoryObjectId) {
        Write-Host "  alias exists: $alias"
      }
      elseif ($holder) {
        Write-Warning "  alias $alias already belongs to $($holder.Identity); not moving it"
      }
      else {
        Invoke-WithRetry { Set-Mailbox -Identity $p.Address -EmailAddresses @{ add = "smtp:$alias" } -ErrorAction Stop } "alias $alias"
        Write-Host "  alias added: $alias"
      }
    }

    Invoke-WithRetry { Add-MailboxPermission -Identity $p.Address -User $OwnerUpn -AccessRights FullAccess `
        -InheritanceType All -AutoMapping $true -ErrorAction Stop | Out-Null } 'owner access'
    Invoke-WithRetry { Add-RecipientPermission -Identity $p.Address -Trustee $OwnerUpn -AccessRights SendAs `
        -Confirm:$false -ErrorAction Stop | Out-Null } 'send as'
    Write-Host '  owner access granted'

    Invoke-WithRetry { Update-MgUser -UserId $mbx.ExternalDirectoryObjectId -AccountEnabled:$false -ErrorAction Stop } 'block sign-in'
    Write-Host '  direct sign-in blocked'
  }
}
finally {
  Disconnect-ExchangeOnline -Confirm:$false | Out-Null
  Disconnect-MgGraph | Out-Null
}
Write-Host "`nDone. Re-run any time; existing mailboxes and aliases are left as they are."
