#!/bin/bash
# Bitwarden Secrets Manager helpers for scripts that run on your MacBook.
# The bootstrap machine account token lives in the MacBook Keychain, never in a file.
# Source after lib/config.sh.

bws_bootstrap_token() {
  if [[ -n "${BWS_ACCESS_TOKEN:-}" ]]; then printf '%s' "$BWS_ACCESS_TOKEN"; return; fi
  security find-generic-password -a "$USER" -s "$BWS_KEYCHAIN_SERVICE" -w 2>/dev/null || \
    fail "No bootstrap token. Run prep/02-bitwarden.sh first (it stores the token in your Keychain)."
}

# bws_cmd ARGS...: runs bws with the bootstrap token and JSON output.
bws_cmd() {
  command -v bws >/dev/null 2>&1 || fail "bws is not installed. Run prep/00-install-tools.sh."
  BWS_ACCESS_TOKEN="$(bws_bootstrap_token)" bws "$@" --output json
}

# bws_project_id NAME
bws_project_id() {
  local id
  id="$(bws_cmd project list | jq -r --arg n "$1" '.[] | select(.name == $n) | .id' | head -n1)"
  [[ -n "$id" ]] || fail "Bitwarden project '$1' not found or the bootstrap machine account can't see it."
  printf '%s' "$id"
}

# bws_get PROJECT KEY: prints the value, or nothing if absent.
bws_get() {
  local pid; pid="$(bws_project_id "$1")"
  bws_cmd secret list "$pid" | jq -r --arg k "$2" '[.[] | select(.key == $k)][0].value // empty'
}

# bws_put PROJECT KEY: reads the value from stdin and creates or updates the secret.
# The value is passed to bws as an argument, so it is briefly visible to processes
# running as you on the MacBook. Nothing is written to disk or shell history.
bws_put() {
  local pid id value
  pid="$(bws_project_id "$1")"
  value="$(cat)"
  [[ -n "$value" ]] || fail "Refusing to store an empty value for $2"
  id="$(bws_cmd secret list "$pid" | jq -r --arg k "$2" '[.[] | select(.key == $k)][0].id // empty')"
  if [[ -n "$id" ]]; then
    bws_cmd secret edit "$id" --value "$value" >/dev/null
    log "Updated $1/$2"
  else
    bws_cmd secret create "$2" "$value" "$pid" >/dev/null
    log "Stored $1/$2"
  fi
}

# bws_get_or_prompt PROJECT KEY "Prompt text": returns the stored value, or asks once
# (hidden input) and stores it.
bws_get_or_prompt() {
  local v; v="$(bws_get "$1" "$2")"
  if [[ -z "$v" ]]; then
    printf '%s (input hidden): ' "$3" >/dev/tty
    read -rs v </dev/tty; echo >/dev/tty
    printf '%s' "$v" | bws_put "$1" "$2" >&2
  fi
  printf '%s' "$v"
}

# random_password: 32 characters, letters and digits.
random_password() { openssl rand -base64 48 | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-32; }
