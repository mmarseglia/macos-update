#!/usr/bin/env zsh

set -e

# Variables
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE_SCRIPT_SRC="$SCRIPT_DIR/update.sh"
UPDATE_SCRIPT_DST="/usr/local/bin/update.sh"
PLIST_SRC="$SCRIPT_DIR/com.marsegm.dailyupdate.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.marsegm.dailyupdate.plist"
LOG_DIR="/usr/local/var/log"

# 1. Copy update.sh to /usr/local/bin
sudo cp "$UPDATE_SCRIPT_SRC" "$UPDATE_SCRIPT_DST"
sudo chmod +x "$UPDATE_SCRIPT_DST"

echo "Copied update.sh to $UPDATE_SCRIPT_DST."

# 2. Ensure log directory exists
sudo mkdir -p "$LOG_DIR"
sudo touch "$LOG_DIR/update.log" "$LOG_DIR/update.err"
sudo chmod 666 "$LOG_DIR/update.log" "$LOG_DIR/update.err"

echo "Log files created at $LOG_DIR."

# 3. Update plist to use correct path for update.sh
cp "$PLIST_SRC" "$PLIST_DST"
sed -i '' "s|/usr/local/bin/update.sh|$UPDATE_SCRIPT_DST|g" "$PLIST_DST"

echo "Copied and updated plist to $PLIST_DST."

# 4. Load the LaunchAgent
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"

echo "Loaded LaunchAgent."

echo "✅ Installation complete. The update will run as scheduled."
