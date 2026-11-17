#!/bin/bash
# Starts the agents as launchd services that survive logouts and reboots:
#   <prefix>.orchestrator           orchestrator loop        (ORCH_USER)
#   <prefix>.worker-1 .. worker-N   coding agent loops       (CODE_USER)
#   <prefix>.remote-control         orchestrator Remote Control session at boot (ORCH_USER),
#                                   only once you've signed that profile into Claude
# Also installs /usr/local/bin/agentctl for the admin: status, logs, pause, restart.
source "$(dirname "$0")/lib.sh"
require_root

ENV_FILE=/usr/local/etc/agentbox.env
install -d -o root -g wheel -m 755 /usr/local/etc
cat > "$ENV_FILE" <<EOF
# Written by agentbox 09-agent-services.sh. Names only.
LAUNCHD_PREFIX="$LAUNCHD_PREFIX"
CODE_USER="$CODE_USER"
ORCH_USER="$ORCH_USER"
WORKER_COUNT="$WORKER_COUNT"
EOF
chmod 644 "$ENV_FILE"
install -o root -g wheel -m 755 "$MINI/admin/agentctl" /usr/local/bin/agentctl

# plist LABEL USER COMMAND KEEPALIVE(true|false) LOGNAME
plist() {
  local label="$1" u="$2" cmd="$3" keep="$4" logname="$5" home="/Users/$2"
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>UserName</key><string>$u</string>
  <key>GroupName</key><string>staff</string>
  <key>ProgramArguments</key>
  <array>
    <string>$home/bin/with-secrets</string>
    <string>$cmd</string>
  </array>
  <key>WorkingDirectory</key><string>$home/work</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>$home</string>
    <key>USER</key><string>$u</string>
    <key>PATH</key><string>$home/bin:$home/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><$keep/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$home/work/logs/$logname.log</string>
  <key>StandardErrorPath</key><string>$home/work/logs/$logname.log</string>
</dict>
</plist>
EOF
}

# load LABEL USER COMMAND KEEPALIVE LOGNAME: (re)installs and (re)starts one service
load() {
  local label="$1" path="/Library/LaunchDaemons/$1.plist" tmp
  tmp="$(mktemp)"; plist "$@" > "$tmp"
  plutil -lint "$tmp" >/dev/null || fail "Bad plist for $label"
  launchctl bootout "system/$label" 2>/dev/null || true
  install -o root -g wheel -m 644 "$tmp" "$path"; rm -f "$tmp"
  launchctl bootstrap system "$path"
  log "  started $label"
}

log "Starting agent services"
load "$LAUNCHD_PREFIX.orchestrator" "$ORCH_USER" "/Users/$ORCH_USER/bin/agent-loop orchestrator" true orchestrator
i=1
while [[ $i -le $WORKER_COUNT ]]; do
  load "$LAUNCHD_PREFIX.worker-$i" "$CODE_USER" "/Users/$CODE_USER/bin/agent-loop worker $i" true "worker-$i"
  i=$((i + 1))
done
# Remove services for workers above WORKER_COUNT
for p in /Library/LaunchDaemons/"$LAUNCHD_PREFIX".worker-*.plist; do
  [[ -e "$p" ]] || continue
  n="${p##*.worker-}"; n="${n%.plist}"
  if [[ "$n" -gt "$WORKER_COUNT" ]]; then
    launchctl bootout "system/$LAUNCHD_PREFIX.worker-$n" 2>/dev/null || true; rm -f "$p"; log "  removed worker-$n"
  fi
done
# The remote control starter runs once at boot (tmux keeps the session alive).
load "$LAUNCHD_PREFIX.remote-control" "$ORCH_USER" "/Users/$ORCH_USER/bin/remote-control start" false remote-control

sleep 5
agentctl status || true
