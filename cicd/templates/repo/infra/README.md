# infra

Infrastructure as code for this repo. Added by agentbox guardrails.

* One directory per provider or stack, for example `infra/azure`, `infra/cloudflare`,
  `infra/supabase`, `infra/fly`.
* A directory with `*.tf` files is planned on every pull request and applied after merge
  by `.github/workflows/iac.yml`, using OpenTofu. A directory with `fly.toml` is deployed
  with `flyctl`.
* Apply runs in the `production` environment and waits for an approved reviewer.
* Credentials are never in this repo. They come from the GitHub environment, filled in by
  `cicd/connect-provider.sh` in the agentbox repo.
* Keep Terraform state remote (the Azure provider script can create a state storage
  account). Never commit `*.tfstate`.
