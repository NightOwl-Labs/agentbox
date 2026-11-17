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

log "Automatic security updates (security responses, not full macOS upgrades)"
SU=/Library/Preferences/com.apple.SoftwareUpdate
defaults write $SU AutomaticCheckEnabled -bool true
defaults write $SU AutomaticDownload -bool true
defaults write $SU CriticalUpdateInstall -bool true
defaults write $SU ConfigDataInstall -bool true

log "Remote Login stays on (step 10 limits it to the tailnet)"
systemsetup -setremotelogin on >/dev/null 2>&1 || true

log "Disabling guest account; name and password fields at login"
defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
defaults write /Library/Preferences/com.apple.loginwindow SHOWFULLNAME -bool true
