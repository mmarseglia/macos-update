# macos-update

A simple automation for keeping your macOS system, Homebrew packages, ASDF plugins, and Oh My Zsh up to date. Includes a LaunchAgent for scheduled updates and a GitHub Actions workflow to archive the project files.

## Features

- Updates macOS software, Homebrew, ASDF plugins, and Oh My Zsh
- Installs a LaunchAgent to run updates automatically (default: every Monday at 3:00 AM)
- GitHub Actions workflow to zip and archive project files

## Installation

1. Clone this repository:

   ```sh
   git clone https://github.com/yourusername/macos-update.git
   cd macos-update
   ```

2. Run the installer:

   ```sh
   zsh install.sh
   ```

   This will:
   - Copy `update.sh` to `/usr/local/bin`
   - Copy and configure the LaunchAgent plist to `~/Library/LaunchAgents`
   - Set up log files
   - Load the LaunchAgent

## Files

- `update.sh`: The update script
- `com.marsegm.dailyupdate.plist`: LaunchAgent configuration
- `install.sh`: Installer script
- `.github/workflows/archive.yml`: GitHub Actions workflow to archive files

## GitHub Actions

On every push to `main` or manual trigger, the workflow zips the main files and uploads them as an artifact.

## Uninstall

To remove the scheduled update:

```sh
launchctl unload ~/Library/LaunchAgents/com.marsegm.dailyupdate.plist
rm ~/Library/LaunchAgents/com.marsegm.dailyupdate.plist
sudo rm /usr/local/bin/update.sh
```

## License

MIT
