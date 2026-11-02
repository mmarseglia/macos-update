#!/usr/bin/env zsh

set -e

if [ -z "$ZSH_VERSION" ]; then
  echo "Please run this script with zsh."
  exit 1
fi

echo "🔧 Updating macOS software..."
if [ -t 0 ]; then
  sudo softwareupdate -i -a
elif sudo -n -l /usr/sbin/softwareupdate >/dev/null 2>&1; then
  # Unattended: a failed install is logged but must not block the other updates.
  sudo -n softwareupdate -i -a || echo "softwareupdate install failed (exit $?); continuing" >&2
else
  echo "Skipping: no terminal for the sudo password. Pending updates:"
  softwareupdate -l 2>&1 || true
fi

echo
echo "🍺 Updating Homebrew and packages..."
brew update
brew upgrade
brew cleanup

echo
echo "📦 Updating ASDF and plugins..."
if type asdf > /dev/null 2>&1; then
  asdf plugin update --all
else
  echo "ASDF is not installed or 'asdf' command not found."
fi

echo
echo "💡 Updating Oh My Zsh..."
if [ -d "$HOME/.oh-my-zsh" ]; then
  "$HOME/.oh-my-zsh/tools/upgrade.sh" -v silent
else
  echo "Oh My Zsh is not installed."
fi

echo
echo "✅ All updates completed."
