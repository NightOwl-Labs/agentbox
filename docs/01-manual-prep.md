# Phase 1: Manual prep

Create every account the business needs, before the Mac mini is even unboxed. Everything
here happens on your MacBook. When you finish, `prep/06-check.sh` prints all PASS and the
rest of the setup runs from stored secrets.

**Order matters:** email first (every other account signs up with an alias), then
Bitwarden and Tailscale, then GitHub (which uses both), then Claude API keys.

## Checklist

Tick these off as you go. Each links to its step.

- [ ] [0. Fill in config.env and install tools](#0-before-you-start)
- [ ] [1. Email: role addresses into one inbox](#1-email-role-addresses-into-one-inbox)
- [ ] [2. Bitwarden: vault, Secrets Manager, machine accounts](#2-bitwarden)
- [ ] [3. Tailscale: tailnet, policy, auth key](#3-tailscale)
- [ ] [4. GitHub: org, teams, agent accounts, tokens](#4-github)
- [ ] [5. Claude API keys](#5-claude-api-keys)
- [ ] [6. Cloud and hosting accounts](#6-cloud-and-hosting-accounts)
- [ ] [7. Run the check](#7-run-the-check)

| You will end with | Where it lives |
|---|---|
| Role addresses (`agents@`, `orchestrator@`, `vault@`, ...) | Aliases on your one real mailbox, each filed in its own folder |
| Human passwords (admin account, web logins, recovery codes) | Your Bitwarden Password Manager vault, folder "<ORG_NAME> agentbox" |
| Machine secrets (tokens, API keys, generated macOS passwords) | Bitwarden Secrets Manager projects `bootstrap`, `coding`, `orchestrator` |
| The bootstrap token that can read and write those projects | Your MacBook Keychain only |

---

## 0. Before you start

1. Edit [`config.env`](../config.env). The four required inputs are `ORG_NAME`,
   `ORG_DOMAIN`, `ORG_PREFIX`, and `GH_ORG`, plus `OWNER_EMAIL` (your real mailbox) and
   `WORKER_GH_LOGIN`. Every account name, host name, and folder below comes from these.
2. Install the MacBook tools:

   ```bash
   prep/00-install-tools.sh
   ```

3. Make an SSH key for the Mac mini if you don't have one, and commit the public half:

   ```bash
   ssh-keygen -t ed25519 -C "$(whoami)-macbook"
   cp ~/.ssh/id_ed25519.pub mini/ssh/authorized_keys/macbook.pub
   ```

<details>
<summary>What you need already: domain and Microsoft 365 tenant</summary>

* A registered domain (`ORG_DOMAIN`) with DNS you control.
* A Microsoft 365 tenant with that domain verified and at least one licensed user
  (`OWNER_EMAIL`). Business Basic is enough. That user is the only mailbox in this design.
* A Google Workspace variant is described in step 1 if that's what you have.

</details>

---

## 1. Email: role addresses into one inbox

Every role address is an **alias** on your one real mailbox. No shared mailboxes, no
extra licenses, no extra passwords. Mail to any alias lands in your inbox and is moved
into `Inbox/<ORG_NAME>/<group>/<address>` by an inbox rule. You can reply as the alias.

The addresses live in [`prep/identities.csv`](../prep/identities.csv). Edit it to add or
remove any; the script is safe to re-run.

```bash
pwsh prep/01-email-aliases.ps1            # dry run: prints the plan
pwsh prep/01-email-aliases.ps1 -Apply     # does it
```

`-Apply` opens two browser sign-ins: Exchange Online as a Microsoft 365 admin (aliases and
the tenant "send from alias" setting), then Microsoft Graph as `OWNER_EMAIL` (folders and
rules). If you're both, use the same account. Add `-AdminUpn <admin>` if the admin is a
different account.

**Check it:** send a test message to `vault@<ORG_DOMAIN>` from another account. It
should arrive in `Inbox/<ORG_NAME>/Accounts/vault`.

<details>
<summary>Replying as an alias in Outlook</summary>

Outlook on the web: open a new message, choose **...** then **Show From**, and type the
alias address in From. Outlook for Mac: **View** then **From**. The tenant setting can
take up to an hour to reach Outlook after the script turns it on.

</details>

<details>
<summary>Google Workspace instead of Microsoft 365 (manual)</summary>

The same shape works with Gmail labels instead of folders. With
[GAM](https://github.com/GAM-team/GAM) installed and authorized, for each row of
`identities.csv`:

```bash
gam update user OWNER_EMAIL add alias LOCAL@ORG_DOMAIN
gam user OWNER_EMAIL sendas LOCAL@ORG_DOMAIN "ORG_NAME LOCAL" treatasalias true
gam user OWNER_EMAIL label "ORG_NAME/GROUP/LOCAL"
gam user OWNER_EMAIL filter to LOCAL@ORG_DOMAIN label "ORG_NAME/GROUP/LOCAL"
```

Workspace allows 30 aliases per user, which covers the default list.

</details>

---

## 2. Bitwarden

Two parts of Bitwarden are used. The **Password Manager vault** holds anything a human
types (the admin account password, web logins, recovery codes). **Secrets Manager** holds
anything a machine reads. Bitwarden only lets you create Secrets Manager machine
accounts and their tokens in the web app, so that part is manual and everything after
it is scripted.

<details>
<summary>2a. Create the account and organization (manual, about 10 minutes)</summary>

1. Sign up at [vault.bitwarden.com](https://vault.bitwarden.com) with `vault@<ORG_DOMAIN>`.
   Strong unique master password. Turn on two step login with an authenticator app.
   Write the recovery code down offline (you'll also paste it into the vault in 2c).
2. Create a **free organization** named `<ORG_NAME>` and turn on **Secrets Manager**
   (free tier: 2 users, 3 projects, 3 machine accounts; this design uses exactly 3 and 3).
3. In Secrets Manager, create three **projects**: `bootstrap`, `coding`, `orchestrator`.
4. Create three **machine accounts** and give each project access:

   | Machine account | Access | Used by |
   |---|---|---|
   | `bootstrap` | **Can read, write** on all three projects | Your MacBook only. Never the Mac mini. |
   | `mini-code` | **Can read** on `coding` only | The coding agent profile |
   | `mini-orch` | **Can read** on `orchestrator` only | The orchestrator profile |

5. For each machine account, open **Access tokens** and create one (no expiry, or a year
   with a calendar reminder). Copy each token as you go; Bitwarden shows it once. You'll
   paste all three into the script next and can then close the tab.

</details>

**2b. Run the script.** It saves the bootstrap token in your Keychain, checks every
token sees exactly the right project, stores the two Mac mini tokens as secrets in
`bootstrap` (so mini setup can fetch them), generates the macOS agent account passwords,
and creates vault login items with generated passwords for every account you're about to
make:

```bash
prep/02-bitwarden.sh
```

**2c. Fill in the vault.** Open the folder **"<ORG_NAME> agentbox"** in your vault and
paste the Bitwarden recovery code into its item. The other items get filled as you go:
the admin password is already generated for Setup Assistant, and the FileVault recovery
key item waits for phase 3.

<details>
<summary>What the script generated, and the vault items list</summary>

Secrets Manager, project `bootstrap`:

| Secret | What it is |
|---|---|
| `BWS_TOKEN_<prefix>code` | Access token for `mini-code` |
| `BWS_TOKEN_<prefix>orch` | Access token for `mini-orch` |
| `MAC_PASSWORD_<prefix>code`, `MAC_PASSWORD_<prefix>orch` | Generated macOS account passwords |

Password Manager vault items come from [`prep/vault-items.csv`](../prep/vault-items.csv).
Rows marked `yes` get a generated password; rows that sign in with Microsoft 365 or an
email link get no password. Edit the CSV to change providers and re-run; existing items
are left alone.

</details>

---

## 3. Tailscale

Tailscale is how your MacBook and phone reach the Mac mini from anywhere. SSH is only
open on the local network for the first minutes of mini setup, then only on the tailnet.

<details>
<summary>3a. Create the tailnet and an API token (manual, about 5 minutes)</summary>

1. Sign up at [login.tailscale.com](https://login.tailscale.com) with **Microsoft** using
   `OWNER_EMAIL` (free Personal plan). This makes your Microsoft 365 account the tailnet
   identity, so there's no extra password.
2. Install Tailscale on your MacBook and phone and sign in. **Never on an employer's
   device.** That device has no path to the agent box, by design.
3. Admin console, **Settings > Keys > Generate access token**. Description `agentbox`,
   expiry 90 days. Copy it.

</details>

**3b. Run the script.** It stores the token, pushes the access policy (only your own
devices, only SSH), and creates a single use, pre-approved, tagged auth key for the Mac
mini. Tagged devices don't expire, so there's no key expiry to turn off later.

```bash
prep/03-tailscale.sh
```

The auth key lasts 7 days. If mini setup happens later than that, run
`prep/03-tailscale.sh --new-authkey` first.

---

## 4. GitHub

Three GitHub identities keep reviews honest:

| Identity | Who | Org role | Team | Used for |
|---|---|---|---|---|
| Your personal login | You | Owner | `humans` | Code owner. The only approver while the hard stop is on. Never on the Mac mini. |
| `WORKER_GH_LOGIN` | You, as a work account | Member | `builders` | Coding agents push branches and open PRs with its fine grained token |
| `ORCH_GH_LOGIN` | Machine user | Member | `orchestrators` | Orchestrator reviews and comments. A different identity from the PR author, so its review is a real second review |

<details>
<summary>4a. Create the organization and accounts (manual)</summary>

1. Create the org `GH_ORG` at [github.com/organizations/plan](https://github.com/organizations/plan)
   (Free) with your personal login, using `github@<ORG_DOMAIN>` as the billing email.
   GitHub doesn't allow creating orgs through the API.
2. If `WORKER_GH_LOGIN` doesn't exist yet, sign up for it with `agents@<ORG_DOMAIN>` and
   turn on two factor.
3. Log `gh` in as **your personal org owner login**, never an agent account:

   ```bash
   env -u GITHUB_TOKEN gh auth login -h github.com -s admin:org --web
   ```

   Choose HTTPS and "Authenticate Git with your GitHub credentials" Yes. In the browser,
   check you're signed in as the org owner and grant access to the org if offered.

</details>

**4b. Teams and agent accounts.** The script creates the three teams and walks you
through the one signup GitHub forbids automating (the orchestrator machine user, with
`orchestrator@<ORG_DOMAIN>` and the generated password from Bitwarden):

```bash
prep/04-github-accounts.sh           # dry run
prep/04-github-accounts.sh --apply   # run until both agent accounts show "member"
```

Accept each invitation while signed in as that account, then run `--apply` once more.
GitHub allows one free machine user per person; the orchestrator is the one that needs
it, because required reviewers must be real accounts.

<details>
<summary>4c. Create the two fine grained tokens (manual)</summary>

Sign in as each account, then **Settings > Developer settings > Fine grained tokens >
Generate new token**. For both: resource owner `GH_ORG`, **All repositories** (so repos
the orchestrator creates later are covered), expiry 90 days.

| Token | Repository permissions |
|---|---|
| `WORKER_GH_LOGIN` (coding) | Contents: read and write. Pull requests: read and write. Issues: read and write. Metadata: read |
| `ORCH_GH_LOGIN` (orchestrator) | Contents: read. Pull requests: read and write. Issues: read and write. Actions: read and write (to dispatch the create-repo workflow). Metadata: read |

Neither token gets Administration, Secrets, Variables, Environments, or Workflows. If
the org asks you to approve fine grained tokens, approve both at
`github.com/organizations/GH_ORG/settings/personal-access-tokens`. Keep these tabs open
for step 5's script.

</details>

---

## 5. Claude API keys

The agents on the Mac mini run headless Claude Code sessions, billed to the Claude API.
Each profile gets its own workspace and key, so spend and revocation are separate.

<details>
<summary>5a. Create workspaces and keys (manual, about 5 minutes)</summary>

1. Sign in to [console.anthropic.com](https://console.anthropic.com) with `ai@<ORG_DOMAIN>`.
   Add billing and set an organization **spend limit** you're comfortable losing.
2. **Settings > Workspaces**: create `coding` and `orchestrator`. Set a monthly spend
   limit on each.
3. In each workspace, **API keys > Create key** named `agentbox-<workspace>`. Copy it.

The `AGENT_MAX_BUDGET_USD` setting in `config.env` also caps each individual job.

</details>

**5b. Store all four agent credentials.** The script checks each GitHub token belongs to
the right account and can see the org, checks each Claude key works, then stores them in
the profile's own project:

```bash
prep/05-agent-credentials.sh
```

<details>
<summary>Optional: a Claude subscription for voice control from your phone</summary>

Validation (phase 4) includes speaking to the orchestrator from the Claude app. That uses
Claude Code Remote Control, which needs a Claude Pro, Max, Team, or Enterprise
subscription and doesn't work with API keys. Use the subscription you already have; you
sign the orchestrator profile into it once in phase 3. On Team or Enterprise, an owner
must first turn on Remote Control in the Claude Code admin settings.

</details>

---

## 6. Cloud and hosting accounts

These are only touched by GitHub Actions in phase 2, never by the Mac mini. Create the
ones you plan to use now, with the vault item `prep/02-bitwarden.sh` already generated
for each. Turn on 2FA and a **spending cap or budget alert** on every one: once auto
approve is on, agents can deploy billable infrastructure.

| Account | Sign up with | Needed for | Spend control |
|---|---|---|---|
| Cloudflare | `cloud@` | DNS, Workers, Pages, R2, D1 | Workers paid plan is opt in |
| Azure | `OWNER_EMAIL` (Microsoft 365) | Apps, databases, Terraform state | Budget with alerts (the provider script creates one) |
| Supabase | `cloud@` | Postgres, auth, storage | Spend cap on by default; keep it |
| Vercel | `cloud@` | Front ends, previews | Spend Management |
| Netlify | `cloud@` | Static sites, functions | Usage alerts |
| Fly.io | `cloud@` | Containers near users | Billing alerts |
| Railway | `cloud@` | Quick services, databases | Usage limits |
| Render | `cloud@` | Web services, cron, databases | Plan based |

<details>
<summary>Double check: accounts that are easy to miss</summary>

| Account | Why | Status |
|---|---|---|
| Domain registrar | Renewal and DNS. Turn on auto renew and registrar lock | Required |
| Microsoft 365 | The one mailbox; also your Azure and Tailscale identity | Required |
| Bitwarden | All secrets | Required |
| Tailscale | Remote access | Required |
| GitHub org + 3 identities | Code, reviews, CI/CD | Required |
| GitHub App (`<GH_ORG>-guardrails`) | Created in phase 2 by script | Phase 2 |
| Anthropic Console | Agent API keys and spend limits | Required |
| Claude subscription | Voice control through Remote Control | Optional |
| Apple Account + Developer Program + D-U-N-S | iOS publishing. Nothing in setup depends on it | Later |
| Google Play Console | Android publishing | Later |
| Payment processor (for example Stripe) | Selling anything | Later |
| Status page or uptime monitor | Knowing when production is down | Later |

</details>

---

## 7. Run the check

```bash
prep/06-check.sh
```

All PASS means manual prep is complete. Next: [Phase 2, CI/CD setup](02-cicd-setup.md).
