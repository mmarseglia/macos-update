# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS maintenance tool: `update.sh` upgrades macOS software, Homebrew, ASDF plugins, and Oh My Zsh. `install.sh` copies it to `/usr/local/bin` and registers a LaunchAgent so it runs on a schedule (README says Monday 3:00 AM). There is no build step or package manager; `tests/test_update.sh` runs `update.sh` against stub commands.

## Commands

```sh
zsh -n update.sh && zsh -n install.sh   # syntax check (shellcheck is not installed)
zsh tests/test_update.sh                 # stubbed tests for update.sh
zsh update.sh                            # run an update now (interactive: prompts for sudo)
zsh install.sh                           # install script + LaunchAgent (prompts for sudo)
launchctl start com.marsegm.dailyupdate  # trigger the installed LaunchAgent immediately
tail -f /usr/local/var/log/update.log /usr/local/var/log/update.err   # LaunchAgent output
```

Uninstall steps are in README.md.

## Architecture

Three pieces that must agree on paths and the label `com.marsegm.dailyupdate`:

- `update.sh` is the payload. It is copied verbatim to `/usr/local/bin/update.sh`; the repo copy is never executed by launchd.
- `com.marsegm.dailyupdate.plist` is the LaunchAgent definition that points at `/usr/local/bin/update.sh` and the two log files in `/usr/local/var/log`.
- `install.sh` wires them together: copies the script, creates world-writable log files, copies the plist into `~/Library/LaunchAgents`, rewrites the script path inside it with `sed`, then reloads it. The `sed` is currently a no-op because source and destination paths are identical; it only matters if `UPDATE_SCRIPT_DST` is changed.

`.github/workflows/archive.yml` zips exactly those three files on every push to `main` and uploads the zip as an artifact. It runs the syntax checks and `tests/test_update.sh` before zipping.

## Things to know

- Both scripts are zsh-only. Keep the `#!/usr/bin/env zsh` shebang; `update.sh` exits early if `$ZSH_VERSION` is unset.
- `update.sh` runs `sudo softwareupdate -i -a`. launchd has no TTY, so unattended runs install macOS updates only if passwordless sudo is configured for softwareupdate (e.g. a sudoers NOPASSWD rule for `/usr/sbin/softwareupdate`; checked with `sudo -n -l`); otherwise they skip and log `softwareupdate -l`. An unattended install failure is logged and the run continues; Homebrew and later steps still run.
- Both scripts use `set -e`, so any failing step (e.g. `brew upgrade` on a broken cask) aborts the rest of the run. Optional tools (asdf, Oh My Zsh) are guarded with existence checks; follow that pattern when adding new update targets.
