#!/usr/bin/env zsh

set -e

if [ -z "$ZSH_VERSION" ]; then
  echo "Please run this script with zsh."
  exit 1
fi

echo "🔧 Updating macOS software..."
sudo softwareupdate -i -a

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
