# Night Owl Agent Box: Mac mini Setup Runbook

Start to finish setup for the always on Mac mini (M6, 24GB memory, 256GB storage) that runs Claude Code agents for Night Owl. Everything that can be scripted is scripted. Manual steps are marked **MANUAL**.

---

## 0. Design at a glance

| Account | Type | Purpose | Apple Account | FileVault unlock |
|---|---|---|---|---|
| `nladmin` (Night Owl Admin) | Admin | Installs software, creates users, runs these scripts. No agents ever run here. | None (App Store sign in only, temporarily, for Xcode) | Yes |
| `nlcode` (Coding Agents) | Standard | Code, GitHub, Xcode, iOS builds, dev environments | Night Owl Apple ID inside Xcode only | No |
| `nlorch` (Orchestrator) | Standard | Plans work, files GitHub issues, reviews and merges PRs, later approves production deploys. Works through GitHub only. **No finance access, ever.** | None | No |
| `nlfinance` (Finance Agents) | Standard | Read only financial access, approval for nearly everything | None | No |

**How the three agent profiles relate**

* The orchestrator breaks work into GitHub issues. Worker sessions in `nlcode` pick up issues, build in their own git worktrees, and open pull requests.
* The orchestrator reviews, approves, and merges those PRs on GitHub. It never reads `nlcode`'s files directly; GitHub is the only bridge.
* Workers and the orchestrator use **different GitHub identities**, so an orchestrator approval is a real second review and branch protection holds.
* Finance is an island. Neither the orchestrator nor the coders can reach it, and it isn't on the orchestrator's handoff path.

**Golden rules**

1. No secrets in the setup repo. Ever. The repo holds only the *names* of secrets.
2. Your personal Matt account and personal iCloud never touch this machine.
3. The work laptop has no path to this box (not on Tailscale, no SSH keys).
4. Agents never move money. Production deploys only happen through GitHub Actions after approval (yours at first, later the orchestrator's for routine releases).
5. The admin owns the rules. Agents get copies of their configs and cannot loosen their own hard limits.

**Where things live**

| Thing | Location |
|---|---|
| Account passwords (`nladmin`, `nlcode`, `nlorch`, `nlfinance`), FileVault recovery key, Bitwarden recovery code | Your personal Bitwarden vault |
| Agent secrets (API keys, tokens, App Store Connect key) | Bitwarden Secrets Manager: projects `coding`, `orchestrator`, and `finance`, one machine account each |
| Production deploy credentials (Azure, Power Platform, Salesforce, Cloudflare) | GitHub environment secrets / OIDC, never on the Mac mini |
| Machine recipe | Private repo `nightowl-labs/agentbox` (layout in section 3) |

---

## 1. Prerequisites (before or while setting up)

### 1.1 Business identity (MANUAL)

1. Create the Night Owl Apple ID at account.apple.com using a role address such as `apple@nightowl-labs.dev`. Turn on two factor with your phone.
2. Sign in at developer.apple.com/enroll/duns-lookup with that Apple ID. Look up the LLC using the legal name and address exactly as registered with the Minnesota Secretary of State. Request a D-U-N-S number if none exists (free, about 5 business days, then a day or two for Apple to see it).
3. Enroll in the Apple Developer Program **as an organization**: LLC legal name, D-U-N-S, nightowl-labs.dev website, and confirm authority to bind the LLC. $99/year.

### 1.2 Bitwarden (MANUAL)

1. Create a free Bitwarden account with a role address (for example `vault@nightowl-labs.dev`). Strong unique master password. Turn on two step login with an authenticator app. Save the recovery code somewhere offline.
2. Create a **free organization** named "Night Owl" and activate **Secrets Manager** (free tier: 2 users, 3 projects, 3 machine accounts).
3. In Secrets Manager create (this uses all 3 projects and 3 machine accounts on the free tier):
   * Project `coding` and machine account `mini-code` with **read** access to `coding` only.
   * Project `orchestrator` and machine account `mini-orch` with **read** access to `orchestrator` only.
   * Project `finance` and machine account `mini-finance` with **read** access to `finance` only.
4. Generate an access token for each machine account. Keep the tokens in your personal vault until section 6.

### 1.3 Tailscale (MANUAL)

1. Create a Tailscale account (free personal plan) with your Night Owl identity.
2. Install Tailscale on your MacBook Air and iPhone and sign in. Do **not** install it on the work laptop.

### 1.4 Setup repo (MANUAL, on your MacBook Air)

Create a **private** repo in the Night Owl GitHub org (suggested: `agentbox`) and add the files from section 3. Add your MacBook's SSH public key (`~/.ssh/id_ed25519.pub`) as `ssh/authorized_keys/macbook-air.pub`. If you don't have one yet:

```bash
ssh-keygen -t ed25519 -C "matt-macbook-air"
```

### 1.5 Hardware

* Battery backup (small UPS) plugged in and connected by USB to the Mac mini.
* External drive A: Time Machine. External drive B: shared handoff drive.
* Ethernet connected (more reliable than Wi-Fi for an always on box).

### 1.6 GitHub identities (MANUAL)

The orchestrator's approval only counts if it comes from a different GitHub identity than the one that opened the PR.

| Identity | Used by | Access |
|---|---|---|
| Your Night Owl GitHub account | `nlcode` workers, via a **fine grained token** | Night Owl org repos only: Contents read/write, Pull requests read/write, Issues read/write. No admin, no secrets, no workflows write. |
| `nightowl-orchestrator` (a dedicated machine user) | `nlorch` | Org member with **Maintain** role on Night Owl repos (enough to review and merge, not to change settings or delete repos). Its own fine grained token or classic token with `repo` scope. |
| You (personal login) | You only | Org owner. Keep owner rights off both tokens. |

Notes:

1. GitHub allows one free machine user per person; the orchestrator is the one that needs it, because required reviewers and environment approvers must be real accounts.
2. Create the machine user with a role address such as `orchestrator@nightowl-labs.dev`, turn on two factor, store its password and 2FA recovery codes in your personal Bitwarden vault.
3. Store each token in its Bitwarden project (`coding` gets the worker token, `orchestrator` gets the orchestrator token). Set token expirations and rotate quarterly.

---

## 2. First boot: Setup Assistant (MANUAL, at the Mac mini)

1. Language, region, network.
2. **Skip** Migration Assistant.
3. **Skip** signing in with an Apple Account.
4. Create the first account:
   * Full name: `Night Owl Admin`
   * Account name: `nladmin`
   * Password: long and random, save it to your personal Bitwarden vault.
5. FileVault: **turn on**, choose **"Create a recovery key and do not use my iCloud account"**. Save the recovery key to your personal Bitwarden vault.
6. Decline location services, analytics, Siri, and Screen Time.
7. Install all macOS updates (System Settings > General > Software Update) and reboot.
8. **Install Xcode** (needed for iOS builds and gives the command line tools):
   * Open App Store, use **Store > Sign In** (this signs into the App Store only, not iCloud) with the Night Owl Apple ID.
   * Install Xcode, launch it once as `nladmin` to accept the license and install components.
   * **Store > Sign Out.**
9. Grant Terminal Full Disk Access (System Settings > Privacy & Security > Full Disk Access > add Terminal). Some scripts below need it. Remove it again at the end (section 8).
10. Clone the setup repo. Easiest: copy it over on a USB stick, or use HTTPS with a GitHub fine grained token that has read only access to that one repo:

```bash
mkdir -p ~/src && cd ~/src
git clone https://github.com/nightowl-labs/agentbox.git
cd agentbox
```

---

## 3. Setup repo layout

```
agentbox/
├── README.md
├── config.env
├── Brewfile
├── bootstrap.sh
├── scripts/
│   ├── lib.sh
│   ├── 00-preflight.sh
│   ├── 01-system-settings.sh
│   ├── 02-install-tools.sh
│   ├── 03-create-users.sh
│   ├── 04-provision-profiles.sh
│   ├── 05-ssh-hardening.sh
│   ├── 06-tailscale.sh
│   ├── 07-drives-and-backups.sh
│   └── 99-verify.sh
├── policy/
│   └── managed-settings.json
├── ssh/
│   ├── 100-nightowl.conf
│   └── authorized_keys/
│       └── macbook-air.pub
├── profiles/
│   ├── nlcode/
│   │   ├── settings.json
│   │   ├── CLAUDE.md
│   │   ├── zshrc
│   │   └── secrets.manifest
│   ├── nlorch/
│   │   ├── settings.json
│   │   ├── CLAUDE.md
│   │   ├── zshrc
│   │   └── secrets.manifest
│   └── nlfinance/
│       ├── settings.json
│       ├── CLAUDE.md
│       ├── zshrc
│       └── secrets.manifest
└── user/
    ├── user-setup.sh
    └── with-secrets
```

All scripts are idempotent: safe to run again after a failure or a change.

### 3.1 `config.env`

```bash
# Night Owl agent box configuration. No secrets in this file.
ADMIN_USER="nladmin"

AGENT_USERS=("nlcode" "nlorch" "nlfinance")
AGENT_FULLNAMES=("Coding Agents" "Orchestrator" "Finance Agents")

# Group for the shared handoff drive. The orchestrator is deliberately NOT a
# member: it works through GitHub only and must never see finance output.
AGENT_GROUP="nlagents"
HANDOFF_MEMBERS=("nlcode" "nlfinance")

# Machine names
COMPUTER_NAME="Night Owl Mini"
HOST_NAME="nightowl-mini"

# External volumes (names you give them when formatting)
TM_VOLUME="NightOwl-TM"
SHARE_VOLUME="NightOwl-Share"
```

### 3.2 `scripts/lib.sh`

```bash
#!/bin/bash
# Shared helpers for agentbox scripts.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_ROOT/config.env"

log()  { printf '\033[1;34m[agentbox]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[fail]\033[0m %s\n' "$*"; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || fail "Run with sudo."
  [[ "${SUDO_USER:-}" == "$ADMIN_USER" ]] || fail "Run from the $ADMIN_USER account (sudo as $ADMIN_USER)."
}

require_admin_not_root() {
  [[ $EUID -ne 0 ]] || fail "Run this one WITHOUT sudo, as $ADMIN_USER."
  [[ "$(whoami)" == "$ADMIN_USER" ]] || fail "Run as $ADMIN_USER."
}

confirm() {
  read -r -p "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}
```

### 3.3 `bootstrap.sh`

```bash
#!/bin/bash
# Runs the full machine setup in order. Run as nladmin:  ./bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")"

./scripts/00-preflight.sh
sudo ./scripts/01-system-settings.sh
./scripts/02-install-tools.sh            # Homebrew must NOT run as root
sudo ./scripts/03-create-users.sh
sudo ./scripts/04-provision-profiles.sh
sudo ./scripts/05-ssh-hardening.sh
sudo ./scripts/06-tailscale.sh
sudo ./scripts/07-drives-and-backups.sh
sudo ./scripts/99-verify.sh

echo
echo "Bootstrap complete. Next: per profile setup (section 6 of the runbook)."
```

### 3.4 `scripts/00-preflight.sh`

```bash
#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_admin_not_root

log "Checking platform"
[[ "$(uname -m)" == "arm64" ]] || fail "Expected Apple silicon."
sw_vers

log "Checking admin rights"
dseditgroup -o checkmember -m "$ADMIN_USER" admin >/dev/null || fail "$ADMIN_USER is not an admin."

log "Checking FileVault"
fdesetup isactive >/dev/null || fail "FileVault is not on. Turn it on before continuing."

log "Checking Xcode"
xcode-select -p >/dev/null 2>&1 || warn "Xcode / command line tools not found. Install Xcode first (section 2 step 8)."

log "Checking SSH public keys in repo"
ls "$REPO_ROOT"/ssh/authorized_keys/*.pub >/dev/null 2>&1 || fail "No public keys in ssh/authorized_keys/. SSH hardening would lock you out."

log "Preflight OK"
```

### 3.5 `scripts/01-system-settings.sh`

```bash
#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_root

log "Setting computer name"
scutil --set ComputerName "$COMPUTER_NAME"
scutil --set HostName "$HOST_NAME"
scutil --set LocalHostName "$HOST_NAME"

log "Power: never sleep, restart after power failure, wake on network"
pmset -a sleep 0 disksleep 0 displaysleep 10 powernap 0 womp 1 autorestart 1

log "Firewall on, stealth mode on"
FW=/usr/libexec/ApplicationFirewall/socketfilterfw
$FW --setglobalstate on
$FW --setstealthmode on

log "Automatic security updates (download and install security responses, not full macOS upgrades)"
SU=/Library/Preferences/com.apple.SoftwareUpdate
defaults write $SU AutomaticCheckEnabled -bool true
defaults write $SU AutomaticDownload -bool true
defaults write $SU CriticalUpdateInstall -bool true
defaults write $SU ConfigDataInstall -bool true

log "Turning on Remote Login (SSH)"
if ! systemsetup -setremotelogin on 2>/dev/null; then
  warn "Could not enable Remote Login from the script (Terminal may need Full Disk Access)."
  warn "Turn it on in System Settings > General > Sharing > Remote Login."
fi

log "Disabling guest account"
defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false

log "Showing name and password fields at login (no user list)"
defaults write /Library/Preferences/com.apple.loginwindow SHOWFULLNAME -bool true

log "Done. MANUAL: System Settings > General > Sharing > Screen Sharing ON, 'Allow access for: Only these users' > nladmin, nlcode, nlfinance."
log "MANUAL: Control Center > Fast User Switching: Show in Menu Bar (lets each profile hold its own GUI session)."
```

### 3.6 `Brewfile`

```ruby
# CLI tools available to every account (installed by nladmin into /opt/homebrew).
brew "git"
brew "gh"
brew "jq"
brew "tmux"
brew "node"
brew "python"
brew "tailscale"      # headless daemon (see 06-tailscale.sh)

# Browsers for agent profiles (each user gets its own browser profile/data)
cask "google-chrome"
```

### 3.7 `scripts/02-install-tools.sh`

```bash
#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_admin_not_root

if ! command -v brew >/dev/null 2>&1 && [[ ! -x /opt/homebrew/bin/brew ]]; then
  log "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null || \
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"

log "Installing Brewfile packages"
brew bundle --file="$REPO_ROOT/Brewfile"

brew analytics off
log "Tools installed. Agent accounts can run these, but only $ADMIN_USER can install or upgrade them."
```

### 3.8 `scripts/03-create-users.sh`

Passwords are typed at the prompt (paste from Bitwarden) and never stored in the repo or shell history. Because the script does not pass admin credentials, the new accounts do not get a Secure Token, which keeps them off the FileVault unlock list.

```bash
#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_root

for i in "${!AGENT_USERS[@]}"; do
  u="${AGENT_USERS[$i]}"
  full="${AGENT_FULLNAMES[$i]}"
  if id "$u" >/dev/null 2>&1; then
    log "$u already exists, skipping creation"
  else
    log "Creating standard user $u ($full)"
    log "Generate a long random password in Bitwarden, save it, then paste it at the prompt."
    sysadminctl -addUser "$u" -fullName "$full" -password - -shell /bin/zsh
  fi
  createhomedir -c -u "$u" >/dev/null 2>&1 || true

  # Make sure it is NOT an admin
  if dseditgroup -o checkmember -m "$u" admin >/dev/null 2>&1; then
    warn "$u is an admin, removing"
    dseditgroup -o edit -d "$u" -t user admin
  fi
done

log "Creating shared agent group $AGENT_GROUP"
dseditgroup -o read "$AGENT_GROUP" >/dev/null 2>&1 || \
  dseditgroup -o create -r "Night Owl agents" "$AGENT_GROUP"
for u in "${HANDOFF_MEMBERS[@]}"; do
  dseditgroup -o edit -a "$u" -t user "$AGENT_GROUP"
done
# Make sure nobody else is in the handoff group (e.g. the orchestrator)
for u in "${AGENT_USERS[@]}"; do
  if [[ ! " ${HANDOFF_MEMBERS[*]} " =~ " $u " ]] && dseditgroup -o checkmember -m "$u" "$AGENT_GROUP" >/dev/null 2>&1; then
    warn "$u should not be in $AGENT_GROUP, removing"
    dseditgroup -o edit -d "$u" -t user "$AGENT_GROUP"
  fi
done

log "Locking down home folders (owner only)"
for u in "$ADMIN_USER" "${AGENT_USERS[@]}"; do
  chmod 700 "/Users/$u"
done

log "Keeping agent accounts off the FileVault unlock list"
for u in "${AGENT_USERS[@]}"; do
  if fdesetup list | cut -d, -f1 | grep -qx "$u"; then
    warn "$u can unlock FileVault, removing"
    fdesetup remove -user "$u"
  fi
done
fdesetup list
```

### 3.9 `policy/managed-settings.json`

Installed root owned at `/Library/Application Support/ClaudeCode/managed-settings.json`. Managed settings apply to every account and cannot be overridden by user or project settings, so these are the hard limits agents cannot loosen. (Check current Claude Code docs for setting names if Claude Code reports an unknown key.)

```json
{
  "permissions": {
    "disableBypassPermissionsMode": "disable",
    "deny": [
      "Bash(sudo:*)",
      "Bash(git push --force:*)",
      "Bash(git push -f:*)",
      "Bash(git push --force-with-lease:*)",
      "Bash(git push origin main:*)",
      "Bash(git push origin master:*)",
      "Bash(security find-generic-password:*)",
      "Bash(security dump-keychain:*)",
      "Read(~/.config/bws/**)",
      "Read(~/.ssh/**)",
      "Read(**/.env)",
      "Read(**/.env.*)",
      "Edit(~/.claude/settings.json)",
      "Edit(~/.zshrc)"
    ]
  }
}
```

### 3.10 `profiles/nlcode/settings.json`

```json
{
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(git add:*)",
      "Bash(git commit:*)",
      "Bash(git switch:*)",
      "Bash(git checkout:*)",
      "Bash(git worktree:*)",
      "Bash(git fetch:*)",
      "Bash(git pull:*)",
      "Bash(git push:*)",
      "Bash(gh pr create:*)",
      "Bash(gh pr view:*)",
      "Bash(gh run view:*)",
      "Bash(npm test:*)",
      "Bash(npm run:*)",
      "Bash(npx:*)",
      "Bash(swift build:*)",
      "Bash(swift test:*)",
      "Bash(xcodebuild:*)",
      "Bash(xcrun simctl:*)"
    ],
    "ask": [
      "Bash(npm install:*)",
      "Bash(pip install:*)",
      "Bash(curl:*)",
      "Bash(rm -rf:*)",
      "Bash(gh pr merge:*)",
      "Bash(gh release:*)",
      "WebFetch"
    ],
    "deny": [
      "Bash(gh repo delete:*)",
      "Bash(gh secret:*)"
    ]
  }
}
```

`git push` is allowed so agents can push feature branches and open PRs. GitHub branch protection (section 9) is what stops anything reaching `main`.

### 3.11 `profiles/nlfinance/settings.json`

```json
{
  "permissions": {
    "defaultMode": "default",
    "allow": [
      "Read",
      "Grep",
      "Glob"
    ],
    "ask": [
      "Bash",
      "Edit",
      "Write",
      "WebFetch",
      "WebSearch"
    ],
    "deny": [
      "Bash(git push:*)",
      "Bash(curl:*)",
      "Bash(wget:*)"
    ]
  }
}
```

"Money movement blocked" is enforced in layers, not by a single setting: read only bank credentials wherever the bank offers them, MFA stays on your phone, every browser action asks for approval, and the finance CLAUDE.md forbids it.

### 3.12 `profiles/nlcode/CLAUDE.md`

```markdown
# Night Owl coding agents: house rules

- You work for Night Owl LLC. Everything built is a Night Owl open source product under the Night Owl GitHub org.
- Work on a feature branch or git worktree. Never commit to main. Open a pull request for every change.
- Run the tests before opening a PR and include the results in the PR description.
- Secrets come only from the `with-secrets` wrapper as environment variables. Never print, log, commit, or write secrets to files.
- Use dev environments only (Power Apps developer environment, Salesforce scratch orgs, Cloudflare preview deploys). Production deploys happen only through GitHub Actions after human approval.
- Do not touch files outside ~/work unless asked.
- If a task needs a new tool, package, or permission, stop and ask.
```

### 3.13 `profiles/nlfinance/CLAUDE.md`

```markdown
# Night Owl finance agents: house rules

- Read only by default. Your job is to gather, reconcile, and summarize, not to act.
- NEVER initiate, approve, schedule, or modify any payment, transfer, trade, payee, or account setting. If a task seems to require it, stop and explain what the human should do.
- Never enter credentials into a page. If a login is needed, stop and ask the human.
- Never send financial data anywhere outside this machine unless the human names the destination in the chat.
- Write outputs to ~/work/reports or the shared handoff drive only.
```

### 3.14 `profiles/<profile>/zshrc` (same for all agent profiles)

```bash
# Managed by agentbox. Changes are overwritten on re-provision.
eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
umask 077                     # new files private to this account
export HISTFILE="$HOME/.zsh_history"
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
```

### 3.15 `profiles/nlcode/secrets.manifest`

Names only, documenting what lives in the `coding` Bitwarden project. Never values.

```
GITHUB_TOKEN                 # fine grained, Night Owl org repos only
APP_STORE_CONNECT_KEY_ID
APP_STORE_CONNECT_ISSUER_ID
APP_STORE_CONNECT_KEY_P8     # contents of the .p8 key
AZURE_DEV_*                  # dev environment only
SF_DEV_*                     # scratch org / dev hub only
CLOUDFLARE_DEV_API_TOKEN     # preview deploy scope only
```

`profiles/nlfinance/secrets.manifest`:

```
# Read only API credentials only. Website logins stay with the human.
```

### 3.16 `user/with-secrets`

Runs a command with this profile's Bitwarden secrets injected as environment variables, so secrets never land in files or in the agent's chat.

```bash
#!/bin/bash
# Usage: with-secrets "npm run deploy:preview"
set -euo pipefail
TOKEN_FILE="$HOME/.config/bws/token"
[[ -r "$TOKEN_FILE" ]] || { echo "No Bitwarden token for $(whoami). Run user-setup.sh."; exit 1; }
BWS_ACCESS_TOKEN="$(cat "$TOKEN_FILE")" exec bws run -- "$*"
```

### 3.17 `scripts/04-provision-profiles.sh`

```bash
#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_root

log "Installing managed Claude Code policy (hard limits for all accounts)"
install -d -o root -g wheel -m 755 "/Library/Application Support/ClaudeCode"
install -o root -g wheel -m 644 "$REPO_ROOT/policy/managed-settings.json" \
  "/Library/Application Support/ClaudeCode/managed-settings.json"

for u in "${AGENT_USERS[@]}"; do
  src="$REPO_ROOT/profiles/$u"
  home="/Users/$u"
  [[ -d "$src" ]] || fail "Missing profile folder $src"
  log "Provisioning $u"

  install -d -o "$u" -g staff -m 700 "$home/.claude" "$home/bin" "$home/work" "$home/.config" "$home/.config/bws"
  install -o "$u" -g staff -m 600 "$src/settings.json" "$home/.claude/settings.json"
  install -o "$u" -g staff -m 600 "$src/CLAUDE.md"     "$home/.claude/CLAUDE.md"
  install -o "$u" -g staff -m 600 "$src/zshrc"         "$home/.zshrc"
  install -o "$u" -g staff -m 700 "$REPO_ROOT/user/with-secrets" "$home/bin/with-secrets"
  install -o "$u" -g staff -m 700 "$REPO_ROOT/user/user-setup.sh" "$home/bin/user-setup.sh"
  install -o "$u" -g staff -m 600 "$src/secrets.manifest" "$home/.config/bws/secrets.manifest"
done

log "Profiles provisioned. Agents receive copies; the repo stays owned by $ADMIN_USER."
```

### 3.18 `ssh/100-nightowl.conf`

```
# Night Owl SSH hardening. Installed to /etc/ssh/sshd_config.d/
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
MaxAuthTries 3
AllowUsers nladmin nlcode nlorch nlfinance

# Optional tighter rule for finance: only from your MacBook's Tailscale IP.
# Replace 100.x.y.z after section 5, then re-run 05-ssh-hardening.sh.
# AllowUsers nladmin nlcode nlorch nlfinance@100.x.y.z
```

### 3.19 `scripts/05-ssh-hardening.sh`

```bash
#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_root

log "Installing authorized keys"
for u in "$ADMIN_USER" "${AGENT_USERS[@]}"; do
  home="/Users/$u"
  install -d -o "$u" -g staff -m 700 "$home/.ssh"
  cat "$REPO_ROOT"/ssh/authorized_keys/*.pub > "$home/.ssh/authorized_keys"
  chown "$u":staff "$home/.ssh/authorized_keys"
  chmod 600 "$home/.ssh/authorized_keys"
done

log "Restricting SSH to named users (com.apple.access_ssh group)"
dseditgroup -o read com.apple.access_ssh >/dev/null 2>&1 || dseditgroup -o create -q com.apple.access_ssh
# Admin FIRST so you can never lock yourself out
for u in "$ADMIN_USER" "${AGENT_USERS[@]}"; do
  dseditgroup -o edit -a "$u" -t user com.apple.access_ssh
done

log "Installing sshd hardening"
grep -q 'sshd_config.d' /etc/ssh/sshd_config || fail "sshd_config does not include sshd_config.d; edit manually."
install -o root -g wheel -m 644 "$REPO_ROOT/ssh/100-nightowl.conf" /etc/ssh/sshd_config.d/100-nightowl.conf
sshd -t || fail "sshd config test failed; not restarting."

warn "Before continuing: from your MacBook, confirm key login works in a NEW terminal:"
warn "  ssh $ADMIN_USER@$HOST_NAME.local"
confirm "Did key based login work?" || fail "Fix key login first. Password login is still allowed until sshd restarts."

launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true
log "SSH hardened: keys only, named users only."
```

### 3.20 `scripts/06-tailscale.sh`

Uses the headless `tailscaled` daemon so Tailscale is up as soon as the Mac boots and FileVault is unlocked, without anyone logged into a desktop session.

```bash
#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_root

TS=/opt/homebrew/bin/tailscale
TSD=/opt/homebrew/bin/tailscaled
[[ -x "$TSD" ]] || fail "tailscaled not installed; run 02-install-tools.sh"

if ! launchctl print system/com.tailscale.tailscaled >/dev/null 2>&1; then
  log "Installing tailscaled as a system daemon"
  "$TSD" install-system-daemon
fi

log "Bringing Tailscale up. A login URL will appear; open it on your MacBook and approve."
"$TS" up --hostname="$HOST_NAME" || true
"$TS" status

log "MANUAL in the Tailscale admin console:"
log "  1. Machines > $HOST_NAME > Disable key expiry."
log "  2. Access controls: paste the policy from section 5.2 of the runbook."
```

### 3.21 `scripts/07-drives-and-backups.sh`

Formatting is destructive, so the script only works with volumes that already exist by name. Format the drives first (section 4.2).

```bash
#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_root

if [[ -d "/Volumes/$TM_VOLUME" ]]; then
  log "Configuring Time Machine on $TM_VOLUME"
  tmutil setdestination -a "/Volumes/$TM_VOLUME" || warn "tmutil needs Full Disk Access for Terminal."
  tmutil enable
  tmutil destinationinfo
else
  warn "/Volumes/$TM_VOLUME not found, skipping Time Machine."
fi

if [[ -d "/Volumes/$SHARE_VOLUME" ]]; then
  log "Configuring shared handoff drive $SHARE_VOLUME"
  diskutil enableOwnership "/Volumes/$SHARE_VOLUME"
  for d in inbox outbox; do
    install -d -o "$ADMIN_USER" -g "$AGENT_GROUP" -m 2770 "/Volumes/$SHARE_VOLUME/$d"
  done
  log "Agents in group $AGENT_GROUP can read/write inbox and outbox; nobody else can."
else
  warn "/Volumes/$SHARE_VOLUME not found, skipping handoff drive."
fi
```

### 3.22 `scripts/99-verify.sh`

```bash
#!/bin/bash
source "$(dirname "$0")/lib.sh"
require_root

pass() { printf '  \033[1;32mPASS\033[0m %s\n' "$*"; }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; FAILED=1; }
FAILED=0

log "Verifying"
fdesetup isactive >/dev/null && pass "FileVault on" || bad "FileVault off"

for u in "${AGENT_USERS[@]}"; do
  id "$u" >/dev/null 2>&1 && pass "$u exists" || bad "$u missing"
  dseditgroup -o checkmember -m "$u" admin >/dev/null 2>&1 && bad "$u is admin" || pass "$u is standard"
  fdesetup list | cut -d, -f1 | grep -qx "$u" && bad "$u can unlock FileVault" || pass "$u cannot unlock FileVault"
  [[ "$(stat -f %Lp "/Users/$u")" == "700" ]] && pass "$u home is 700" || bad "$u home not 700"
done

for a in "${AGENT_USERS[@]}"; do
  for b in "${AGENT_USERS[@]}"; do
    [[ "$a" == "$b" ]] && continue
    if sudo -u "$a" ls "/Users/$b" >/dev/null 2>&1; then bad "$a can read /Users/$b"; else pass "$a cannot read /Users/$b"; fi
  done
  if sudo -u "$a" ls "/Users/$ADMIN_USER" >/dev/null 2>&1; then bad "$a can read admin home"; else pass "$a cannot read admin home"; fi
done

sshd -T 2>/dev/null | grep -qi '^passwordauthentication no' && pass "SSH password login off" || bad "SSH password login on"
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -q enabled && pass "Firewall on" || bad "Firewall off"
pmset -g | grep -Eq '^ *sleep +0' && pass "System sleep disabled" || bad "System sleep enabled"
dseditgroup -o checkmember -m nlorch "$AGENT_GROUP" >/dev/null 2>&1 && bad "nlorch is in the handoff group" || pass "nlorch kept off the handoff drive"
[[ -f "/Library/Application Support/ClaudeCode/managed-settings.json" ]] && pass "Claude Code managed policy installed" || bad "Managed policy missing"
/opt/homebrew/bin/tailscale status >/dev/null 2>&1 && pass "Tailscale connected" || bad "Tailscale not connected"

[[ $FAILED -eq 0 ]] && log "All checks passed." || fail "Some checks failed."
```

### 3.23 `user/user-setup.sh` (run inside each agent account)

```bash
#!/bin/bash
# Run once as the agent user (nlcode or nlfinance) over SSH or Screen Sharing.
set -euo pipefail
me="$(whoami)"
echo "Setting up $me"

# 1. Claude Code (native installer, per user, into ~/.local/bin)
if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
fi

# 2. Bitwarden Secrets Manager token for THIS profile's machine account
if [[ ! -s "$HOME/.config/bws/token" ]]; then
  echo "Paste the access token for machine account mini-${me#nl} (input hidden):"
  read -rs token
  umask 077
  printf '%s' "$token" > "$HOME/.config/bws/token"
  unset token
fi
chmod 600 "$HOME/.config/bws/token"

# 3. Git identity (coding profile)
if [[ "$me" == "nlcode" ]]; then
  git config --global user.name  "Night Owl Agents"
  git config --global user.email "agents@nightowl-labs.dev"
  git config --global init.defaultBranch main
  git config --global push.autoSetupRemote true
  if ! gh auth status >/dev/null 2>&1; then
    echo "Paste the WORKER fine grained GitHub token (input hidden):"
    read -rs ghtoken
    printf '%s' "$ghtoken" | gh auth login --with-token
    unset ghtoken
  fi
  gh auth setup-git
fi

# 4. Orchestrator: GitHub identity is the nightowl-orchestrator machine user
if [[ "$me" == "nlorch" ]]; then
  git config --global user.name  "Night Owl Orchestrator"
  git config --global user.email "orchestrator@nightowl-labs.dev"
  git config --global init.defaultBranch main
  if ! gh auth status >/dev/null 2>&1; then
    echo "Paste the nightowl-orchestrator GitHub token (input hidden):"
    read -rs ghtoken
    printf '%s' "$ghtoken" | gh auth login --with-token
    unset ghtoken
  fi
  gh auth status
fi

echo
echo "Next: run 'claude' once and complete login."
echo "Then test secrets: with-secrets 'env | grep -c .'"
```

### 3.24 Orchestrator profile files

#### `profiles/nlorch/settings.json`

Merging is allowed. Anything that reaches production or changes repo settings asks first. When you're ready for the orchestrator to approve routine production deploys, move the `pending_deployments` rule from `ask` to `allow` (and add `nightowl-orchestrator` as an environment reviewer, section 9).

```json
{
  "permissions": {
    "defaultMode": "default",
    "allow": [
      "Read",
      "Grep",
      "Glob",
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(git fetch:*)",
      "Bash(git pull:*)",
      "Bash(git clone:*)",
      "Bash(git switch:*)",
      "Bash(git checkout:*)",
      "Bash(gh issue:*)",
      "Bash(gh pr list:*)",
      "Bash(gh pr view:*)",
      "Bash(gh pr diff:*)",
      "Bash(gh pr checks:*)",
      "Bash(gh pr checkout:*)",
      "Bash(gh pr review:*)",
      "Bash(gh pr comment:*)",
      "Bash(gh pr merge:*)",
      "Bash(gh run list:*)",
      "Bash(gh run view:*)",
      "Bash(gh run watch:*)",
      "Bash(npm test:*)",
      "Bash(npm run test:*)",
      "Bash(swift test:*)"
    ],
    "ask": [
      "Bash(gh pr close:*)",
      "Bash(gh workflow run:*)",
      "Bash(gh run rerun:*)",
      "Bash(gh release:*)",
      "Bash(gh api repos/*/actions/runs/*/pending_deployments:*)",
      "Bash(gh api:*)",
      "Edit",
      "Write",
      "WebFetch"
    ],
    "deny": [
      "Bash(gh pr merge --admin:*)",
      "Bash(gh pr merge * --admin:*)",
      "Bash(git push:*)",
      "Bash(gh repo delete:*)",
      "Bash(gh repo edit:*)",
      "Bash(gh secret:*)",
      "Bash(gh variable:*)",
      "Bash(gh auth token:*)",
      "Read(/Volumes/NightOwl-Share/**)"
    ]
  }
}
```

The orchestrator reviews and merges but does not write code or push. If it wants a change, it asks for it in the PR or files an issue for the workers. `--admin` merges are denied because they bypass branch protection.

#### `profiles/nlorch/CLAUDE.md`

```markdown
# Night Owl orchestrator: house rules

- You coordinate Night Owl engineering through GitHub. You do not write code or push commits.
- Break work into small GitHub issues with clear acceptance criteria and the label `agent-ready`. Workers in the coding profile pick these up.
- Review every PR against its issue: tests pass, scope matches, no secrets, no unexplained dependencies. Request changes with specific comments when needed.
- Approve and squash merge only when checks are green and the PR fully meets the issue. Never merge your own work, never use --admin, never disable checks.
- Production: you may request or prepare deployments. Approving a production deployment always needs explicit human confirmation unless the house rules are updated.
- You have no access to finance systems or the finance profile. If a task touches money, banking, or personal financial data, stop and tell the human.
- Keep a running summary in ~/work/orchestrator-log.md: issues filed, PRs merged, anything blocked.
- Use subagents for parallel review; use smaller models for routine checks and the main model for planning and final approval.
```

#### `profiles/nlorch/secrets.manifest`

```
GITHUB_ORCHESTRATOR_TOKEN    # nightowl-orchestrator machine user, Night Owl org only
# Production deploy credentials are NOT here. They live in GitHub environments.
```

#### `profiles/nlorch/zshrc`

Same as section 3.14.

---

## 4. Run the bootstrap (on the Mac mini, as nladmin)

### 4.1 Make scripts executable and run

```bash
cd ~/src/agentbox
chmod +x bootstrap.sh scripts/*.sh user/*
./bootstrap.sh
```

You will be prompted for: the `nladmin` password (sudo), each agent account's password (paste from Bitwarden), confirming SSH key login from your MacBook, and approving Tailscale in a browser.

### 4.2 Format the external drives (MANUAL, destructive)

Do this before `07-drives-and-backups.sh`, or re-run that script afterward.

```bash
diskutil list external          # find the disk identifiers, e.g. disk4, disk5
# DOUBLE CHECK the identifiers. This erases the drives.
sudo diskutil eraseDisk APFS NightOwl-TM    /dev/diskN
sudo diskutil eraseDisk APFS NightOwl-Share /dev/diskM
sudo ./scripts/07-drives-and-backups.sh
```

For an encrypted Time Machine disk, also tick "Encrypt backups" in System Settings > General > Time Machine.

### 4.3 Manual settings the script prints

* System Settings > General > Sharing > **Screen Sharing** on, allow only `nladmin`, `nlcode`, `nlfinance`.
* Control Center > **Fast User Switching** in menu bar.

---

## 5. Remote access

### 5.1 From your MacBook Air

Add to `~/.ssh/config` on the MacBook:

```
Host mini-admin
  HostName nightowl-mini
  User nladmin
Host mini-code
  HostName nightowl-mini
  User nlcode
Host mini-orch
  HostName nightowl-mini
  User nlorch
Host mini-finance
  HostName nightowl-mini
  User nlfinance
```

`nightowl-mini` resolves through Tailscale MagicDNS anywhere, and `nightowl-mini.local` works at home. Screen Sharing: Finder > Go > Connect to Server > `vnc://nightowl-mini`, then pick which account to log in as.

From iPhone: an SSH app (for example Termius or Blink) using a key generated on the phone; add that public key to `ssh/authorized_keys/` and re-run `sudo ./scripts/05-ssh-hardening.sh`.

### 5.2 Tailscale access policy (MANUAL, admin console > Access controls)

```json
{
  "tagOwners": {
    "tag:agentbox": ["autogroup:admin"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["tag:agentbox:22,5900"]
    }
  ]
}
```

Then tag the Mac mini with `tag:agentbox` (Machines > nightowl-mini > Edit ACL tags) and disable its key expiry. Only your own signed in devices can reach SSH (22) and Screen Sharing (5900). The work laptop is never added to the tailnet.

Optional: once you know your MacBook's Tailscale IP (`tailscale ip -4` on the MacBook), restrict `nlfinance` to it using the commented line in `ssh/100-nightowl.conf`.

---

## 6. Per profile setup

### 6.1 Coding profile (`ssh mini-code`)

```bash
~/bin/user-setup.sh
claude            # complete login once, then /exit
```

Then, via Screen Sharing logged in as `nlcode`:

1. Open Xcode > Settings > Accounts > add the **Night Owl Apple ID**. Let Xcode manage signing for the Night Owl team.
2. Create an App Store Connect API key (App Store Connect > Users and Access > Integrations) and store its three values in the `coding` Bitwarden project.
3. Open Chrome, create a profile named "Night Owl Coding," sign in only to GitHub and dev consoles.

### 6.2 Finance profile (`ssh mini-finance`)

```bash
~/bin/user-setup.sh
claude
```

Via Screen Sharing logged in as `nlfinance`:

1. Chrome profile "Night Owl Finance." Sign in to bank sites yourself; use read only or view only users where the bank offers them.
2. MFA stays on your phone. Do not save bank passwords in the browser.
3. Put only read only API credentials (if any) in the `finance` Bitwarden project.

### 6.3 Orchestrator profile (`ssh mini-orch`)

```bash
~/bin/user-setup.sh       # paste the mini-orch Bitwarden token, then the orchestrator GitHub token
claude                    # complete login once, then /exit
gh auth status            # should show nightowl-orchestrator
```

No Screen Sharing or browser setup needed; the orchestrator works headless through `gh`.

Test the separation before trusting it:

```bash
ls /Users/nlcode          # Permission denied
ls /Users/nlfinance       # Permission denied
ls /Volumes/NightOwl-Share/inbox   # Permission denied
gh pr merge 1 --admin     # should be blocked by Claude Code if run by an agent, and by branch protection
```

### 6.4 Running agents day to day

**Orchestrator** (planning on the main model):

```bash
ssh mini-orch
tmux new -A -s orch
claude
# e.g. "Plan the receipt app MVP as agent-ready issues in nightowl-labs/receipt-app,
#       then review and merge PRs as they come in."
```

**Workers** (build from issues; cheaper models via subagents):

```bash
ssh mini-code
tmux new -A -s agents     # attach or create a persistent session
claude                    # "Pick up the next agent-ready issue in receipt-app and open a PR."
# detach: Ctrl-b then d. Agents keep running after you disconnect.
```

Run several workers at once by opening more tmux windows, each in its own git worktree:

```bash
git worktree add ../myapp-feature-x -b feature-x
cd ../myapp-feature-x && claude
```

Anything that needs secrets runs through the wrapper:

```bash
with-secrets "npm run test:integration"
```

---

## 7. FileVault and reboots

* **Planned restart** (updates): as `nladmin`, run `sudo fdesetup authrestart`. The Mac restarts and skips the FileVault unlock screen once.
* **Unplanned restart** (power loss beyond the UPS): the Mac waits at the FileVault unlock screen. Nothing runs, including Tailscale, until `nladmin` unlocks it. Recent macOS versions can unlock FileVault over SSH from the local network; test `ssh nladmin@nightowl-mini.local` right after a reboot while you are home. If it doesn't work, unlock at the machine or over Screen Sharing on the local network.
* Configure the UPS: System Settings > Battery (or Energy) > UPS options, shut down cleanly at low battery.

---

## 8. Final hardening (MANUAL)

1. Remove Full Disk Access from Terminal for `nladmin` (System Settings > Privacy & Security).
2. Run `sudo ./scripts/99-verify.sh` and confirm all PASS.
3. Reboot, unlock, and re-run the verify script.
4. Confirm from your MacBook: `ssh -o PreferredAuthentications=password mini-code` is refused.
5. Confirm from `nlcode`: `ls /Users/nlfinance` and `sudo -v` both fail.
6. Back up: the repo is in GitHub, passwords and keys are in Bitwarden. Nothing else on this machine is irreplaceable.

---

## 9. Deployment model (GitHub, not the Mac mini)

Production credentials never live on the Mac mini. Agents open pull requests; GitHub Actions deploys after you approve.

1. **Branch protection** (or a ruleset) on `main` in every Night Owl repo: require PRs, require **1 approving review**, require passing checks, dismiss stale approvals on new commits, block force pushes, and do not allow bypass for the orchestrator. Worker PRs are opened by your Night Owl account and approved by `nightowl-orchestrator`, so the approval is a genuine second review.
2. **GitHub environments**: a `production` environment per platform with required reviewers and **"Prevent self-review"** on.
   * **Stage 1 (now):** you are the only reviewer.
   * **Stage 2 (later):** add `nightowl-orchestrator` as a reviewer for routine releases, move the `pending_deployments` rule to `allow` in `profiles/nlorch/settings.json`, update its CLAUDE.md, re-run `04-provision-profiles.sh`. Keep yourself as the only reviewer for anything sensitive (database migrations, auth, billing) by using a separate `production-critical` environment.
3. **Azure**: OIDC federated credentials from GitHub to the Night Owl subscription, scoped to specific resource groups. No stored secrets.
4. **Power Platform**: service principal (app registration) with the Power Platform GitHub Actions, limited to target environments.
5. **Salesforce**: Night Owl developer org plus a locked down connected app with JWT auth for the pipeline.
6. **Cloudflare**: narrowly scoped API tokens per project, stored as GitHub environment secrets.
7. **Dev only on the box**: Power Apps developer environment, Salesforce scratch orgs, Cloudflare preview deploys. Those keys go in the `coding` Bitwarden project.

---

## 10. Maintenance

| When | What |
|---|---|
| Weekly | `ssh mini-admin`, then `brew update && brew upgrade`, check `tmutil latestbackup` |
| Monthly | Install macOS updates with `sudo fdesetup authrestart`; run `99-verify.sh` |
| On any config change | Edit the repo on your MacBook, push, `git pull` as `nladmin`, re-run the relevant script |
| Quarterly | Rotate Bitwarden machine account tokens and GitHub tokens; review Tailscale devices |
| If an agent misbehaves | `sudo pkill -u <profile>` as admin, revoke that profile's Bitwarden token and GitHub token, review logs. For the orchestrator, also remove `nightowl-orchestrator` from environment reviewers until resolved. |

### Rebuild from scratch

1. Erase the Mac mini, run Setup Assistant (section 2).
2. Clone the repo, run `./bootstrap.sh`.
3. Run `user-setup.sh` in each profile with fresh Bitwarden tokens.
