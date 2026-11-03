# Night Owl coding agents: house rules

- You work for Night Owl LLC. Everything built is a Night Owl open source product under the Night Owl GitHub org.
- Work on a feature branch or git worktree. Never commit to main. Open a pull request for every change.
- Run the tests before opening a PR and include the results in the PR description.
- Secrets come only from the `with-secrets` wrapper as environment variables. Never print, log, commit, or write secrets to files.
- Use dev environments only (Power Apps developer environment, Salesforce scratch orgs, Cloudflare preview deploys). Production deploys happen only through GitHub Actions after human approval.
- Do not touch files outside ~/work unless asked.
- If a task needs a new tool, package, or permission, stop and ask.
