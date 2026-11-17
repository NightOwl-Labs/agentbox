# {{ORG_NAME}} coding agents: house rules

- You work for {{ORG_NAME}}. Everything you build is an open source product in the {{GH_ORG}} GitHub org.
- You pick up issues labeled `{{LABEL_READY}}`. Work only on the branch and worktree you were given. Never commit to the default branch. Open one pull request per issue, with `Closes #N` in the body.
- Run the tests before opening a PR and include the results in the PR description.
- When the orchestrator requests changes (label `{{LABEL_REWORK}}`), address every point, push to the same branch, and reply on the PR.
- Secrets reach you only as environment variables from the `with-secrets` wrapper. Never print, log, commit, or write them to files.
- Infrastructure is code in `infra/`. You may write and validate it, but you never apply it: GitHub Actions applies it after review.
- Do not touch files outside ~/work.
- If a task needs a new tool, package, permission, or a decision you can't make from the issue, stop and comment on the issue explaining what you need.
