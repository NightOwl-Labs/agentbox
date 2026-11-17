#!/bin/bash
# Loads config.env, checks the inputs, and derives every other name from them.
# Sourced by all scripts (MacBook, Mac mini, and CI). Bash 3.2 compatible (macOS /bin/bash).

# shellcheck disable=SC2034  # values are used by the scripts that source this file
AGENTBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AGENTBOX_ROOT
# shellcheck source=/dev/null
source "${AGENTBOX_CONFIG:-$AGENTBOX_ROOT/config.env}"

log()  { printf '\033[1;34m[agentbox]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }
confirm() { local ans; read -r -p "$1 [y/N] " ans </dev/tty; [[ "$ans" =~ ^[Yy]$ ]]; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# ---- Validate inputs -------------------------------------------------------
[[ -n "${ORG_NAME:-}" ]]   || fail "ORG_NAME is not set in config.env"
[[ -n "${ORG_DOMAIN:-}" ]] || fail "ORG_DOMAIN is not set in config.env"
[[ -n "${GH_ORG:-}" ]]     || fail "GH_ORG is not set in config.env"
[[ "${ORG_PREFIX:-}" =~ ^[a-z]{2,6}$ ]] || fail "ORG_PREFIX must be 2 to 6 lowercase letters"
[[ "$ORG_DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]] || fail "ORG_DOMAIN looks wrong: $ORG_DOMAIN"
[[ "${ORCH_AUTO_APPROVE:-false}" =~ ^(true|false)$ ]] || fail "ORCH_AUTO_APPROVE must be true or false"

# ---- Defaults for optional values -----------------------------------------
# CI passes the org variable ORCH_AUTO_APPROVE here, so the switch has one source of truth
# on GitHub even though config.env is committed.
[[ -n "${ORCH_AUTO_APPROVE_OVERRIDE:-}" ]] && ORCH_AUTO_APPROVE="$ORCH_AUTO_APPROVE_OVERRIDE"
: "${ORCH_GH_LOGIN:=${ORG_PREFIX}orchestrator}"
: "${ORCH_AUTO_APPROVE:=false}"
: "${WORKER_COUNT:=2}"
: "${POLL_SECONDS:=60}"
: "${AGENT_MAX_TURNS:=60}"
: "${AGENT_MAX_BUDGET_USD:=5}"
: "${TIME_MACHINE_VOLUME:=}"
: "${BWS_VERSION:=2.1.0}"

# ---- Derived names ---------------------------------------------------------
ADMIN_USER="${ORG_PREFIX}admin"     # Human only. No LLM is ever installed here.
ORCH_USER="${ORG_PREFIX}orch"       # Orchestrator agent profile
CODE_USER="${ORG_PREFIX}code"       # Coding agent profile (runs WORKER_COUNT workers)
AGENT_USERS=("$CODE_USER" "$ORCH_USER")
ADMIN_FULLNAME="$ORG_NAME Admin"
CODE_FULLNAME="$ORG_NAME Coding Agents"
ORCH_FULLNAME="$ORG_NAME Orchestrator"

HOST_NAME="${ORG_PREFIX}-agentbox"  # Hostname on the LAN (.local) and on the tailnet (MagicDNS)
COMPUTER_NAME="$ORG_NAME Agent Box"
# Reverse DNS label for launchd jobs, e.g. dev.example
LAUNCHD_PREFIX="$(printf '%s' "$ORG_DOMAIN" | awk -F. '{for (i=NF; i>0; i--) printf "%s%s", $i, (i>1 ? "." : "")}').agentbox"

TAILSCALE_TAG="tag:agentbox"

# Bitwarden Secrets Manager projects (free tier: 3 projects, 3 machine accounts)
BWS_PROJECT_BOOTSTRAP="bootstrap"   # MacBook only. Read/write. Never on the Mac mini.
BWS_PROJECT_CODE="coding"           # Read only, machine account mini-code
BWS_PROJECT_ORCH="orchestrator"     # Read only, machine account mini-orch
BWS_KEYCHAIN_SERVICE="agentbox-bws-bootstrap"   # MacBook Keychain item holding the bootstrap token

# GitHub
GH_TEAM_HUMANS="humans"             # Code owners. The only approvers while ORCH_AUTO_APPROVE=false
GH_TEAM_ORCH="orchestrators"        # Maintain on product repos
GH_TEAM_BUILDERS="builders"         # Write on product repos (the worker account)
GH_PLATFORM_REPO="platform"         # Inbox issues, create-repo and guardrails workflows
GH_EXCLUDE_REPOS="agentbox"         # Agents get no access: the admin owns the rules

# Labels that drive the agent workflow
LABEL_REQUEST="orchestrator"        # A human request for the orchestrator (platform repo)
LABEL_REQUEST_DONE="orch-done"
LABEL_READY="agent-ready"           # Orchestrator tags an issue for coding
LABEL_CLAIMED="agent-claimed"
LABEL_PR_OPEN="agent-pr-open"
LABEL_REWORK="agent-rework"         # Orchestrator requested changes on a PR
LABEL_BLOCKED="agent-blocked"

# Every variable a template may reference as {{NAME}}
TEMPLATE_VARS="ORG_NAME ORG_DOMAIN ORG_PREFIX GH_ORG OWNER_EMAIL WORKER_GH_LOGIN ORCH_GH_LOGIN \
ORCH_AUTO_APPROVE WORKER_COUNT POLL_SECONDS AGENT_MAX_TURNS AGENT_MAX_BUDGET_USD \
ADMIN_USER ORCH_USER CODE_USER HOST_NAME COMPUTER_NAME LAUNCHD_PREFIX TAILSCALE_TAG \
GH_TEAM_HUMANS GH_TEAM_ORCH GH_TEAM_BUILDERS GH_PLATFORM_REPO \
LABEL_REQUEST LABEL_REQUEST_DONE LABEL_READY LABEL_CLAIMED LABEL_PR_OPEN LABEL_REWORK LABEL_BLOCKED"

# render SRC: prints SRC with every {{NAME}} replaced by the value of NAME.
render() {
  local args=() v val
  for v in $TEMPLATE_VARS; do
    val="${!v}"
    val="$(printf '%s' "$val" | sed -e 's/[\\|&]/\\&/g')"
    args+=(-e "s|{{$v}}|$val|g")
  done
  sed "${args[@]}" "$1"
  if grep -q '{{[A-Z_]*}}' <(sed "${args[@]}" "$1"); then
    warn "Unrendered placeholder left in $1"
  fi
}

# require_value NAME: fails if a config value the current step needs is empty.
require_value() { [[ -n "${!1:-}" ]] || fail "$1 is empty in config.env, and this step needs it."; }
