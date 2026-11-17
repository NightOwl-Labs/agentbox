# Phase 2: CI/CD setup

Make GitHub the safe, auditable path to production **before** any agent runs. After this
phase, every repo in the org (including the ones agents create later) is protected the
same way, and cloud credentials live only in GitHub environments.

Everything runs on your MacBook as the org owner. Give `gh` the scopes it needs once:

```bash
env -u GITHUB_TOKEN gh auth refresh -h github.com -s admin:org,workflow
```

## Checklist

- [ ] [1. Org settings](#1-org-settings)
- [ ] [2. Platform repo and guardrails App](#2-platform-repo-and-guardrails-app)
- [ ] [3. Connect providers to a repo](#3-connect-providers-to-a-repo)
- [ ] [4. Confirm the hard stop](#4-confirm-the-hard-stop)

## How the pieces fit

| Piece | What it does | Who can change it |
|---|---|---|
| Org settings | Members can't create repos; Actions are allow listed and read only; workflows can't approve PRs | Org owners |
| `platform` repo | Request inbox (issues), `create-repo` and `guardrails` workflows | Code owners (humans) |
| `<GH_ORG>-guardrails` App | The only identity with admin rights over repos; used only by the platform workflows | Org owners |
| Ruleset on every default branch | PR, 1 approval, code owner review while the hard stop is on, linear history, required `secret-scan` | The guardrails App, hourly |
| `preview` and `production` environments | Provider credentials; production waits for an approved reviewer | The guardrails App and `connect-provider.sh` |
| `ORCH_AUTO_APPROVE` | The hard stop. `false` means only humans approve merges and deploys | Humans, with `cicd/set-auto-approve.sh` |

---

## 1. Org settings

```bash
cicd/00-org-settings.sh
```

Sets the repository policy, the Actions allow list and read only workflow tokens, blocks
workflows from approving pull requests, attaches GitHub's recommended code security
configuration to every repo, and creates the org variable `ORCH_AUTO_APPROVE`.

<details>
<summary>Manual: three org settings with no API</summary>

1. **Require two factor authentication** for everyone:
   `Settings > Authentication security > Require two factor authentication`.
2. **Personal access tokens:** `Settings > Personal access tokens`. Restrict access with
   classic tokens, and require administrator approval for fine grained tokens. Approve
   the two agent tokens from phase 1 if they show as pending.
3. **Member privileges:** turn off "Allow members to change repository visibilities",
   "Allow members to delete or transfer repositories", and "Allow members to create teams".

</details>

<details>
<summary>Why members can't create repos</summary>

On GitHub, whoever creates a repo becomes its admin, and an admin can remove its
protections. So agents never create repos directly: the orchestrator dispatches the
`create-repo` workflow, and the guardrails App creates the repo and protects it before
any agent can push.

</details>

---

## 2. Platform repo and guardrails App

```bash
cicd/01-platform-repo.sh
```

1. Opens your browser to create the GitHub App `<GH_ORG>-guardrails` from a manifest.
   Click **Create GitHub App**, then paste the address GitHub sends you back to. The
   script converts it and stores the App ID and private key in Bitwarden.
2. Opens the App's install page: install it on the org with **All repositories**.
3. Creates the public `platform` repo with the request form and the two workflows, and an
   environment `platform-admin` (protected branches only) holding the App key.
4. Runs the guardrails on every repo in the org.

Re-run any time you change `config.env`, `cicd/guardrails.sh`, or the templates. Once the
platform repo's main is protected, the script opens a pull request for you to merge.

<details>
<summary>What the guardrails apply to each repo</summary>

| Area | Setting |
|---|---|
| Team access | `humans` admin, `orchestrators` maintain, `builders` write. Agents get nothing on `agentbox`; builders nothing on `platform` |
| Merging | Squash only, delete branch on merge, no auto merge |
| Ruleset | PR required, 1 approval, stale approvals dismissed, last push must be approved by someone else, conversations resolved, linear history, no force push or deletion, `secret-scan` required. Code owner review required while `ORCH_AUTO_APPROVE=false` |
| Files (new repos) | `CODEOWNERS` (humans team), `security.yml` (gitleaks, Trivy IaC scan, dependency review), `iac.yml`, `dependabot.yml`, `infra/README.md` |
| Security | Dependabot alerts and fixes, secret scanning with push protection, CodeQL default setup |
| Labels | `orchestrator`, `orch-done`, `agent-ready`, `agent-claimed`, `agent-pr-open`, `agent-rework`, `agent-blocked` |
| Environments | `preview` (open). `production`: humans team as reviewers, prevent self review, protected branches only |

Rulesets, environment rules, and secret scanning are free on public repos. Private repos
need GitHub Team or higher; the script warns when it sees one.

</details>

<details>
<summary>Manual alternative: create the App by hand</summary>

If the manifest flow is blocked, create it at
`github.com/organizations/<GH_ORG>/settings/apps/new` with no webhook and these
permissions. Repository: Administration, Contents, Environments, Issues, Pull requests,
Workflows, Dependabot alerts, Code scanning alerts (all read and write); Variables and
Metadata (read). Organization: Members (read). Generate a private key, then store it:

```bash
source lib/config.sh; source lib/bws.sh
bws_put bootstrap GUARDRAILS_APP_ID <<< "<app id>"
bws_put bootstrap GUARDRAILS_APP_SLUG <<< "<app slug>"
bws_put bootstrap GUARDRAILS_APP_PRIVATE_KEY < ~/Downloads/<key>.pem && rm ~/Downloads/<key>.pem
```

Then re-run `cicd/01-platform-repo.sh`.

</details>

---

## 3. Connect providers to a repo

Each product repo provisions its own infrastructure from `infra/<provider>/` directories
(OpenTofu, or `fly.toml` for Fly.io). The seeded `iac.yml` plans on pull requests in the
`preview` environment and applies after merge in `production`. This step puts each
provider's credentials into those two environments:

```bash
cicd/connect-provider.sh <provider> <repo>
```

Account level tokens are kept in Bitwarden (`bootstrap`) so you paste each one once.
Azure and Fly are fully scripted; the others need one token from their dashboard first.

<details>
<summary>Azure (scripted, OIDC, no stored secret)</summary>

**Manual once:** an Azure subscription you can create app registrations and role
assignments in (Owner, or Contributor plus User Access Administrator).

```bash
cicd/connect-provider.sh azure <repo> --location eastus --budget 25
```

Creates resource group `rg-<repo>`, an app registration with federated credentials for
this repo's `preview` and `production` environments only, Contributor on that resource
group only, a Terraform state storage account, and a monthly budget. Sets
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` as environment variables.
Add email alerts to the budget in Cost Management.

</details>

<details>
<summary>Cloudflare (scripted after one token)</summary>

**Manual once:** `dash.cloudflare.com > My Profile > API Tokens > Create Token`, template
**Create Additional Tokens**. This "token creator" can only mint other tokens. The script
asks for it once.

```bash
cicd/connect-provider.sh cloudflare <repo>
```

Mints a per repo token (Workers, KV, R2, D1, Pages, DNS on your account, one year expiry)
and sets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.

</details>

<details>
<summary>Supabase</summary>

**Manual once:** create a Supabase organization just for agent products (tokens see every
project in the account). `Account > Access Tokens > Generate new token`. Keep the default
spend cap on.

```bash
cicd/connect-provider.sh supabase <repo>
```

Sets `SUPABASE_ACCESS_TOKEN` and `SUPABASE_ORG_ID`. Use the `supabase/supabase` OpenTofu
provider in `infra/supabase/`.

</details>

<details>
<summary>Vercel</summary>

**Manual once:** create a team. `Account Settings > Tokens > Create`, scope: that team,
expiry 1 year. Turn on Spend Management.

```bash
cicd/connect-provider.sh vercel <repo>
```

Sets `VERCEL_API_TOKEN` and `VERCEL_TEAM_ID`. Use the `vercel/vercel` provider.

</details>

<details>
<summary>Netlify</summary>

**Manual once:** `User settings > Applications > Personal access tokens > New`, expiry
1 year. Set usage alerts on the team.

```bash
cicd/connect-provider.sh netlify <repo>
```

Sets `NETLIFY_API_TOKEN` and `NETLIFY_ACCOUNT_SLUG`. Use the `netlify/netlify` provider.

</details>

<details>
<summary>Fly.io (scripted)</summary>

**Manual once:** sign up and add a payment method with billing alerts.

```bash
cicd/connect-provider.sh fly <repo> --org <org-slug>
```

Signs you in with `flyctl` if needed and mints an org scoped deploy token named for the
repo. Sets `FLY_API_TOKEN`. Put `fly.toml` in `infra/fly/`; the workflow deploys it.

</details>

<details>
<summary>Railway</summary>

**Manual once per repo:** create the project, then `Project Settings > Tokens > Create`
for the production environment. Project tokens are scoped to one project, which is what
you want. Set usage limits on the workspace.

```bash
cicd/connect-provider.sh railway <repo>
```

Sets `RAILWAY_TOKEN`. Use the community `terraform-community-providers/railway` provider.

</details>

<details>
<summary>Render</summary>

**Manual once:** create a workspace just for agent products (API keys see the whole
account). `Account Settings > API Keys > Create`.

```bash
cicd/connect-provider.sh render <repo>
```

Sets `RENDER_API_KEY` and `RENDER_OWNER_ID`. Use the `render-oss/render` provider.

</details>

---

## 4. Confirm the hard stop

`ORCH_AUTO_APPROVE` is `false` in `config.env` and in the org variable. Check a repo:

```bash
gh api repos/<GH_ORG>/platform/rulesets --jq '.[].name'          # agentbox-default-branch
gh api repos/<GH_ORG>/platform/rulesets/$(gh api repos/<GH_ORG>/platform/rulesets --jq '.[0].id') \
  --jq '.rules[] | select(.type=="pull_request") | .parameters.require_code_owner_review'   # true
```

### Turning on auto approve

Leave it off until you've watched agents work end to end (phase 4) and every provider has
a spending cap. When humans decide they're ready:

```bash
cicd/set-auto-approve.sh on        # asks you to type the org name
git commit -am "Turn on orchestrator auto approve" && mini/remote-setup.sh --reprovision
```

That updates the org variable and reruns the guardrails (the orchestrator's approval now
counts, and it becomes a production reviewer), and lets the orchestrator profile approve
and merge. `cicd/set-auto-approve.sh off` reverses all of it.

Next: [Phase 3, Mac mini setup](03-mini-setup.md).
