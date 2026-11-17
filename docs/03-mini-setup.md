# Phase 3: Mac mini setup

Turn the Mac mini on, create one human admin account at the keyboard, and run everything
else from your MacBook over SSH. When `mini/remote-setup.sh` finishes, the orchestrator and
two coding agents are running as services, every secret came from Bitwarden, and SSH is only
reachable over Tailscale.

Xcode and Apple accounts are deliberately skipped. Nothing here depends on them; iOS
publishing can be added later.

## Checklist

- [ ] [1. Roles on this machine](#1-roles-on-this-machine) (read once)
- [ ] [2. First boot at the Mac mini](#2-first-boot-at-the-mac-mini) (manual, about 20 minutes)
- [ ] [3. Run remote setup from your MacBook](#3-run-remote-setup-from-your-macbook)
- [ ] [4. Confirm the agents are running](#4-confirm-the-agents-are-running)
- [ ] [5. Optional: enable voice control](#5-optional-enable-voice-control)

---

## 1. Roles on this machine

| Account | Who | What it can do | What it can never do |
|---|---|---|---|
| `<prefix>admin` | **Humans only** | Installs software, creates accounts, owns the rules, unlocks FileVault | Run an LLM. Claude Code is never installed here and no API key or Bitwarden token ever lives here, so the human admin keeps control even if every agent misbehaves |
| `<prefix>orch` | Orchestrator agent | Plans work as GitHub issues, dispatches repo creation, reviews and comments on PRs | Write code, push, create repos directly, approve or merge while the hard stop is on, read other homes |
| `<prefix>code` | Two coding agents | Branch, commit, push feature branches, open PRs | Merge, approve, apply infrastructure, touch production credentials, read other homes |

**Golden rules**

1. No secrets in this repo. Ever. It holds only the names of secrets.
2. No personal accounts or personal iCloud touch this machine.
3. Employer owned devices have no path to this box (not on the tailnet, no SSH keys).
4. Agents never hold cloud or production credentials. Infrastructure changes only through
   GitHub Actions, after approval (humans only, until a human turns on auto approve).
5. The admin owns the rules. Agents get root owned limits (managed Claude Code policy) and
   copies of their configs, and can't loosen either.

---

## 2. First boot at the Mac mini

<details open>
<summary>Manual steps at the keyboard</summary>

**Hardware first:** Ethernet connected (more reliable than Wi-Fi), a small UPS connected by
USB if you have one. External drives are optional.

1. Press the power button. Choose language, region, and your network.
2. **Skip** Migration Assistant ("Not now").
3. **Skip** signing in with an Apple Account ("Set up later", then "Skip").
4. Create the first account. This is the human admin:
   * Full name: `<ORG_NAME> Admin`
   * Account name: `<prefix>admin` (for example `nladmin`; must match `ADMIN_USER`, which is
     `ORG_PREFIX` + `admin`)
   * Password: the generated one in the Bitwarden item **"Agent box admin"**
5. **FileVault: turn on**, and choose **"Create a recovery key and do not use my iCloud
   account"**. Paste the recovery key into the Bitwarden item **"Agent box FileVault
   recovery key"** before continuing.
6. Decline Location Services, analytics, Siri, and Screen Time.
7. Install all macOS updates: System Settings > General > Software Update. Reboot.
8. Turn on **Remote Login** so your MacBook can reach it: System Settings > General >
   Sharing > Remote Login, on, "Allow access for: Only these users" with just the admin.
   This is **temporary local network access**: setup closes it to everything but Tailscale
   as its last step. Don't forward port 22 on your router.
9. Note the address shown under Remote Login (for example `Admins-Mac-mini.local`
   or an IP like `192.168.1.50`).

That's the last time you need the keyboard, unless the power fails (see Operating).

</details>

---

## 3. Run remote setup from your MacBook

From this repo, with Tailscale running on the MacBook and everything committed:

```bash
mini/remote-setup.sh <address from step 9>
```

You type the admin password twice: once so your SSH key can be installed, once for sudo.
Everything else comes from Bitwarden.

<details>
<summary>What it does, step by step</summary>

| Step | Where | What |
|---|---|---|
| Key login | MacBook | Installs your SSH key for the admin, proves key login works |
| Copy repo | MacBook to mini | `git archive HEAD` to `~/agentbox`. The mini never logs in to GitHub |
| Handoff | MacBook to mini | Fetches agent passwords, the two agent Bitwarden tokens, and the Tailscale auth key from `bootstrap`, writes them to a 600 file that bootstrap deletes when it exits |
| 00 preflight | mini | Apple silicon, admin rights, FileVault on, handoff present, admin is LLM free |
| 01 system | mini | Name `<prefix>-agentbox`, never sleep, restart after power loss, firewall, security updates |
| 02 tools | mini | Homebrew (which brings the Command Line Tools, so no Xcode), git, gh, jq, tmux, node, python, tailscale, bws |
| 03 users | mini | `<prefix>code` and `<prefix>orch` as standard users with generated passwords, homes 700, off the FileVault unlock list |
| 04 profiles | mini | Managed Claude Code policy; each agent's settings, house rules, prompts, and its own Bitwarden token. The orchestrator's settings deny approve and merge while the hard stop is on |
| 05 SSH | mini | Keys only, named users only |
| 06 Tailscale | mini | Joins with the tagged, pre-approved auth key. No browser step, no key expiry |
| 07 backups | mini | Time Machine if `TIME_MACHINE_VOLUME` is set |
| 08 agents | mini | Installs Claude Code in each agent account only; git identity; proves each agent's secrets work and its GitHub token is the right account |
| 09 services | mini | launchd services: orchestrator, worker-1, worker-2, remote control. Installs `agentctl` |
| 10 lockdown | mini | pf rules: SSH (and Screen Sharing) only from tailnet addresses. Refuses if Tailscale isn't up |
| 99 verify | mini | PASS or FAIL for every check above |
| Switch | MacBook | Reconnects over Tailscale and confirms local network SSH is now closed |

Every step is idempotent. If one fails, fix the cause and run the same command again.

</details>

<details>
<summary>Optional: Time Machine drive (destructive)</summary>

Before running remote setup, at the mini or over SSH as the admin:

```bash
diskutil list external                 # find the disk, for example disk4. DOUBLE CHECK.
sudo diskutil eraseDisk APFS <PREFIX>-TM /dev/diskN
```

Set `TIME_MACHINE_VOLUME="<PREFIX>-TM"` in `config.env` and commit. For encrypted backups
also tick "Encrypt backups" in System Settings > General > Time Machine.

</details>

---

## 4. Confirm the agents are running

```bash
ssh -t <prefix>admin@<prefix>-agentbox sudo agentctl status
```

You should see `orchestrator`, `worker-1`, and `worker-2` in state `running`, each log
ending in `started as <login> in <GH_ORG>`. Three Claude agent services are now polling
GitHub; they start a headless Claude Code session for each job they pick up.

<details>
<summary>agentctl reference</summary>

| Command | What it does |
|---|---|
| `sudo agentctl status` | Services, last log line, remote control session |
| `sudo agentctl logs worker-1` | Follow one service's log |
| `sudo agentctl pause` / `resume` | Agents finish their current job, then take no new work |
| `sudo agentctl restart [service]` | Restart one or all |
| `sudo agentctl stop` | Stop everything now, including running Claude sessions |

Job transcripts are in `~/work/logs/jobs/` in each agent account.

</details>

---

## 5. Optional: enable voice control

To talk to the orchestrator from the Claude app on your phone (validation step 2), sign the
orchestrator profile into your Claude subscription once. Remote Control doesn't accept API
keys; the background loops keep using the orchestrator's API key.

```bash
ssh <prefix>orch@<prefix>-agentbox
claude                 # then type /login, sign in with your Claude account in the browser, /exit
touch ~/.config/agentbox/remote-control-enabled && ~/bin/remote-control start
```

In the Claude app, open **Code**: a session named **"<ORG_NAME> orchestrator"** with a
green dot appears. It restarts automatically after a reboot.

---

## Operating

<details>
<summary>Reboots and FileVault</summary>

* **Planned restart** (updates): `ssh -t <prefix>admin@<prefix>-agentbox sudo fdesetup authrestart`.
  The Mac restarts and skips the FileVault unlock screen once. Agents start on boot.
* **Unplanned restart** (power loss beyond the UPS): the Mac waits at the FileVault unlock
  screen and nothing runs, Tailscale included. Recent macOS can unlock FileVault over SSH
  from the local network before boot (the pf rules aren't loaded yet): try
  `ssh <prefix>admin@<prefix>-agentbox.local` from home. Otherwise unlock at the keyboard.
* Configure the UPS: System Settings > Energy > UPS options, shut down at low battery.

</details>

<details>
<summary>Changing config, upgrading, rotating</summary>

| When | What |
|---|---|
| Any config or profile change | Commit on the MacBook, then `mini/remote-setup.sh --reprovision` |
| Weekly | `ssh <prefix>admin@<prefix>-agentbox`, then `brew update && brew upgrade`; agents' Claude Code updates itself |
| Monthly | macOS updates with `sudo fdesetup authrestart`; `sudo ~/agentbox/mini/scripts/99-verify.sh` |
| Every 90 days | Rotate GitHub tokens and Claude keys: `prep/05-agent-credentials.sh --rotate`, then `sudo agentctl restart` |
| Yearly | Rotate Bitwarden machine tokens: new tokens in the web app, delete `BWS_TOKEN_*` in `bootstrap`, `prep/02-bitwarden.sh`, then re-run remote setup |

</details>

<details>
<summary>If an agent misbehaves</summary>

1. `ssh -t <prefix>admin@<prefix>-agentbox sudo agentctl stop`
2. Revoke that profile's GitHub token (github.com settings of that account) and its Claude
   key (console workspace). Optionally revoke its Bitwarden machine token.
3. Read `~/work/logs` and `~/work/logs/jobs` in that account, and its GitHub activity.
4. If auto approve was on: `cicd/set-auto-approve.sh off`.

</details>

<details>
<summary>Break glass: locked out of SSH</summary>

At the keyboard, log in as the admin, then `sudo pfctl -a agentbox -F rules` reopens local
network SSH until the next boot. Fix Tailscale (`sudo tailscale up`), then
`sudo ~/agentbox/mini/scripts/10-lockdown-ssh.sh`.

</details>

<details>
<summary>Rebuild from scratch</summary>

1. Erase the Mac mini and redo step 2.
2. On the MacBook: `ssh-keygen -R <prefix>-agentbox` and `ssh-keygen -R <old address>`.
3. `prep/03-tailscale.sh --new-authkey`, remove the old machine in the Tailscale admin console.
4. `mini/remote-setup.sh <address>`.

Nothing on the mini is irreplaceable: the recipe is in GitHub and every secret is in Bitwarden.

</details>

Next: [Phase 4, Validation](04-validation.md).
