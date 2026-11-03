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
