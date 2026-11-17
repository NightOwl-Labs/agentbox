# Phase 4: Validation

Prove the whole loop works, with the hard stop on, before trusting it with real work:

> a request (by voice or issue) → the orchestrator creates a repo and files an issue → a
> coding agent picks it up, branches, commits, pushes, and opens a PR → the orchestrator
> reviews and comments → **nothing merges until a human approves**

## Checklist

- [ ] [1. Machine checks](#1-machine-checks)
- [ ] [2. Voice: ask the orchestrator from the Claude app](#2-voice-ask-the-orchestrator-from-the-claude-app)
- [ ] [3. Automated end to end run](#3-automated-end-to-end-run)
- [ ] [4. Approve as a human and clean up](#4-approve-as-a-human-and-clean-up)

---

## 1. Machine checks

```bash
ssh -t <prefix>admin@<prefix>-agentbox 'sudo ~/agentbox/mini/scripts/99-verify.sh && sudo agentctl status'
ssh -o ConnectTimeout=5 <prefix>admin@<address used in phase 3>     # must time out: LAN SSH is closed
ssh -o PreferredAuthentications=password <prefix>code@<prefix>-agentbox   # must be refused
```

All PASS, three services running, and both SSH attempts refused.

---

## 2. Voice: ask the orchestrator from the Claude app

Needs phase 3, step 5 (orchestrator signed in to your Claude subscription).

1. On your phone, open the Claude app and tap **Code**. Open the session
   **"<ORG_NAME> orchestrator"** (computer icon, green dot).
2. Tap the microphone (or your keyboard's dictation) and say something like:

   > "Create a new repo called smoke-voice-one for a tiny Python command line tool that
   > prints hello. Plan it as one agent-ready issue with a pytest test and a CI workflow."

3. The orchestrator dispatches `create-repo`, waits for the repo, and files the issue.
   Anything outside its allow list (for example an unexpected `gh api` call) shows up on
   your phone as a permission prompt for you to approve or deny.
4. On your MacBook, follow the rest of the flow automatically:

   ```bash
   validation/e2e.sh --watch-repo smoke-voice-one
   ```

<details>
<summary>No Claude subscription? Use an issue instead</summary>

The same request can come from any GitHub client, including the GitHub mobile app or a
Claude chat with a GitHub connector: open an issue in `<GH_ORG>/platform` with the label
`orchestrator` (the issue form adds it). The orchestrator's background loop picks it up
within `POLL_SECONDS`. Step 3 does exactly this for you.

</details>

---

## 3. Automated end to end run

```bash
validation/e2e.sh
```

Files a request in the platform repo and checks each stage as it happens (usually 10 to 30
minutes):

| Stage | Proves |
|---|---|
| Request labeled `orch-done` | Orchestrator loop reads requests with its own GitHub identity and API key |
| Repo created, ruleset present | Agents get repos only through `create-repo`, protected before the first push |
| An `agent-ready` issue | Orchestrator plans work as issues |
| Issue labeled `agent-claimed` | A coding agent picked it up |
| PR from `WORKER_GH_LOGIN` on an `agent/` branch | Branch, commit, push, PR by the coding identity |
| Review by `ORCH_GH_LOGIN` | A second identity reviewed and commented |
| Not approved by the orchestrator, not merged | **The hard stop held** |

If a stage times out, `ssh -t <prefix>admin@<prefix>-agentbox sudo agentctl logs worker-1`
(or `orchestrator`) shows what the agent was doing, and job transcripts are in
`~/work/logs/jobs/` of that account.

---

## 4. Approve as a human and clean up

Open the PR link the script prints. You're the code owner: review, approve, and squash
merge. That's the full lifecycle with a human at the gate. Then:

```bash
validation/e2e.sh --cleanup smoke-<timestamp>
validation/e2e.sh --cleanup smoke-voice-one
```

**Setup is complete.** Leave `ORCH_AUTO_APPROVE` off until you've watched real work flow
through and every provider has a spending cap. Turning it on is a deliberate human
decision: [Phase 2, Turning on auto approve](02-cicd-setup.md#turning-on-auto-approve).
