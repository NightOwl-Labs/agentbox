#!/bin/bash
# Bitwarden setup, scripted as far as Bitwarden allows.
#
# Bitwarden only lets you create machine accounts and their access tokens in the web
# app (docs/01-manual-prep.md, step 2). Everything after that is here:
#   1. Saves the bootstrap machine account token in your MacBook Keychain.
#   2. Checks the three Secrets Manager projects and each token's access.
#   3. Stores the two Mac mini machine account tokens as secrets in the bootstrap
#      project, so mini setup can install them without you pasting anything.
#   4. Generates passwords for the macOS agent accounts and stores them there too.
#   5. Creates login items with generated passwords in your Password Manager vault for
#      every web account you will sign up for next (prep/vault-items.csv).
# Safe to re-run: existing secrets and vault items are left alone.
#
# Usage: prep/02-bitwarden.sh [--reset-token]
set -euo pipefail
# shellcheck source=../lib/config.sh
source "$(dirname "$0")/../lib/config.sh"
# shellcheck source=../lib/bws.sh
source "$AGENTBOX_ROOT/lib/bws.sh"

for t in bws bw jq security; do command -v "$t" >/dev/null 2>&1 || fail "$t missing. Run prep/00-install-tools.sh."; done

# ---- 1. Bootstrap token in Keychain ---------------------------------------------------
if [[ "${1:-}" == "--reset-token" ]]; then
  security delete-generic-password -a "$USER" -s "$BWS_KEYCHAIN_SERVICE" >/dev/null 2>&1 || true
fi
if ! security find-generic-password -a "$USER" -s "$BWS_KEYCHAIN_SERVICE" >/dev/null 2>&1; then
  log "Paste the access token for the 'bootstrap' machine account."
  log "It is saved in your login Keychain as '$BWS_KEYCHAIN_SERVICE' and never written to a file."
  security add-generic-password -a "$USER" -s "$BWS_KEYCHAIN_SERVICE" -U -w
fi

# ---- 2. Projects and access -----------------------------------------------------------
log "Checking Secrets Manager projects"
for p in "$BWS_PROJECT_BOOTSTRAP" "$BWS_PROJECT_CODE" "$BWS_PROJECT_ORCH"; do
  bws_project_id "$p" >/dev/null && log "  $p: visible to bootstrap"
done

# check_token USER PROJECT: the machine token must see exactly its own project.
check_token() {
  local token="$1" want="$2" seen
  seen="$(BWS_ACCESS_TOKEN="$token" bws project list --output json 2>/dev/null | jq -r '[.[].name] | sort | join(",")')" || \
    fail "That token was rejected by Bitwarden."
  [[ "$seen" == "$want" ]] || fail "Token should see only '$want' but sees '$seen'. Fix its project access in the web app."
}

# ---- 3. Mac mini machine account tokens -----------------------------------------------
store_machine_token() {
  local project="$2" machine="$3" key="BWS_TOKEN_$1" token
  if [[ -n "$(bws_get "$BWS_PROJECT_BOOTSTRAP" "$key")" ]]; then
    log "  $key already stored"; return
  fi
  printf 'Paste the access token for machine account %s (read only on %s) (input hidden): ' "$machine" "$project" >/dev/tty
  read -rs token </dev/tty; echo >/dev/tty
  check_token "$token" "$project"
  printf '%s' "$token" | bws_put "$BWS_PROJECT_BOOTSTRAP" "$key"
}
log "Storing the Mac mini machine account tokens"
store_machine_token "$CODE_USER" "$BWS_PROJECT_CODE" "mini-code"
store_machine_token "$ORCH_USER" "$BWS_PROJECT_ORCH" "mini-orch"

# ---- 4. macOS agent account passwords -------------------------------------------------
log "Generating macOS agent account passwords"
for u in "${AGENT_USERS[@]}"; do
  key="MAC_PASSWORD_$u"
  if [[ -n "$(bws_get "$BWS_PROJECT_BOOTSTRAP" "$key")" ]]; then log "  $key already stored"
  else random_password | bws_put "$BWS_PROJECT_BOOTSTRAP" "$key"; fi
done

# ---- 5. Password Manager login items --------------------------------------------------
log "Creating login items in your Bitwarden vault (Password Manager)"
status="$(bw status | jq -r .status)"
if [[ "$status" == "unauthenticated" ]]; then BW_SESSION="$(bw login "vault@$ORG_DOMAIN" --raw)"
else BW_SESSION="$(bw unlock --raw)"; fi
export BW_SESSION
bw sync >/dev/null

folder_name="$ORG_NAME agentbox"
folder_id="$(bw list folders --search "$folder_name" | jq -r --arg n "$folder_name" '.[] | select(.name == $n) | .id' | head -n1)"
if [[ -z "$folder_id" ]]; then
  folder_id="$(bw get template folder | jq --arg n "$folder_name" '.name = $n' | bw encode | bw create folder | jq -r .id)"
  log "  folder created: $folder_name"
fi
existing="$(bw list items --folderid "$folder_id" | jq -r '.[].name')"

render "$AGENTBOX_ROOT/prep/vault-items.csv" | tail -n +2 | \
while IFS=, read -r name username local_part url gen notes; do
  [[ -z "$name" ]] && continue
  if grep -qxF "$name" <<<"$existing"; then log "  exists: $name"; continue; fi
  email=""; [[ -n "$local_part" ]] && email="$local_part@$ORG_DOMAIN"
  [[ -z "$username" ]] && username="$email"
  password=""; [[ "$gen" == "yes" ]] && password="$(bw generate -ulns --length 32)"
  bw get template item | jq \
    --arg name "$name" --arg folder "$folder_id" --arg user "$username" --arg pw "$password" \
    --arg url "$url" --arg notes "$notes${email:+ Email: $email}" \
    '.type = 1 | .name = $name | .folderId = $folder | .notes = $notes |
     .login = {username: $user, password: (if $pw == "" then null else $pw end),
               uris: (if $url == "" then [] else [{uri: $url, match: null}] end), totp: null} |
     .fields = [] | .secureNote = null | .card = null | .identity = null' \
    | bw encode | bw create item >/dev/null
  log "  created: $name"
done

bw lock >/dev/null
log "Done. Use the generated passwords as you create each account in the next steps."
