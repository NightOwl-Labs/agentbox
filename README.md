# agentbox

The recipe for the always-on Night Owl Mac mini that runs Claude Code agents, plus the
email and GitHub identities those agents use. The full walkthrough, including every manual
step, is in [nightowl-agentbox-setup.md](nightowl-agentbox-setup.md).

## No secrets. Ever.

This repo holds the *names* of secrets, never values. Passwords, tokens, and keys live in
Bitwarden and are entered at a hidden prompt or a browser sign-in at run time.

Three layers enforce this: [.gitignore](.gitignore) excludes common secret files, a
[pre-commit hook](.githooks/pre-commit) scans staged changes with gitleaks, and
[CI](.github/workflows/ci.yml) scans the full history. Enable the hook in each clone:

```bash
git config core.hooksPath .githooks
```

## Step 1: Identities (on your MacBook, never the Mac mini)

Every address and agent account is defined in
[identity/identities.csv](identity/identities.csv). Edit that file to change them; the
scripts re-read it and are safe to run again.

| Script | What it does |
|---|---|
| `identity/01-install-microsoft-cli.sh` | Installs PowerShell, the Exchange Online and Microsoft Graph modules, and the repo tools |
| `identity/02-create-mailboxes.ps1` | Creates a shared mailbox and aliases per row, gives the owner access, blocks direct sign-in |
| `identity/03-github-agent-accounts.sh` | Guides signup for agent accounts, then sets up the org team, repo access, and invitation |

Scripts 02 and 03 only print their plan until you opt in:

```bash
pwsh identity/02-create-mailboxes.ps1
```

```bash
pwsh identity/02-create-mailboxes.ps1 -Apply -AdminUpn <admin-upn> -OwnerUpn <owner-upn>
```

```bash
identity/03-github-agent-accounts.sh
```

```bash
identity/03-github-agent-accounts.sh --apply
```

**Before running:** `nightowl-labs.dev` must be a verified domain in your Microsoft 365
tenant, and script 03 needs an org owner login with the `admin:org` scope. See
[section 1.7 of the runbook](nightowl-agentbox-setup.md#17-log-in-to-github-and-add-agent-accounts-manual-on-your-macbook).

**Why PowerShell:** Azure CLI and Microsoft Graph can't add mailbox aliases, so Exchange
Online PowerShell is required.

**Why GitHub signup is manual:** GitHub requires a human to create each account and forbids
automated registration. Its terms also allow one free machine account per person, which is
why only `nlorchestrator` has a login in the CSV.

## Step 2: The Mac mini

Follow section 2 of the runbook, add your SSH public key as
`ssh/authorized_keys/macbook-air.pub`, then as `nladmin`:

```bash
./bootstrap.sh
```

## Differences from the runbook

The scripts come straight from the runbook's code blocks, with these changes:

- **`bws` is installed.** The runbook uses it in `with-secrets` but never installs it, and
  Homebrew has no formula. `scripts/02-install-tools.sh` installs a pinned, checksum-verified
  release to `/usr/local/bin`, and `scripts/99-verify.sh` checks for it.
- **The `identity/` folder and secret guards are new.** The runbook doesn't cover them.
- **`agentbox` is excluded from agent team access** (`GH_TEAM_EXCLUDE_REPOS` in
  `identity/config.env`), so an agent can't edit its own limits.
