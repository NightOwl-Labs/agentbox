# platform

Control plane for the {{ORG_NAME}} agent workflow. Managed by the agentbox repo
(`cicd/01-platform-repo.sh`); edit there, not here.

* **Requests:** open an issue with the `{{LABEL_REQUEST}}` label (use the issue form). The
  orchestrator plans it: creates repos if needed and files `{{LABEL_READY}}` issues for
  the coding agents, then comments back here and adds `{{LABEL_REQUEST_DONE}}`.
* **create-repo workflow:** the only way agents get a new repo. Creates it and applies the
  guardrails before anyone can push.
* **guardrails workflow:** re-applies team access, rulesets, environments, labels, and
  security settings to every repo hourly.

Both workflows use the `platform-admin` environment, which only the protected default
branch can use, so the guardrails App key never reaches code on any other branch.

Issues here are public. Keep sensitive business detail out of requests.
