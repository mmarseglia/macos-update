# CLAUDE.md

A macOS maintenance tool: `update.sh` upgrades macOS software, Homebrew, ASDF plugins, and Oh My Zsh; `install.sh` installs it as a weekly LaunchAgent (the label says `dailyupdate`; the schedule lives in the plist). No build step or package manager.

## Commands

```sh
zsh -n update.sh && zsh -n install.sh   # syntax check (shellcheck is not installed)
zsh tests/test_update.sh                 # stubbed tests: the safe way to exercise update.sh
zsh update.sh                            # real update of this Mac (prompts for sudo)
zsh install.sh                           # real install of script + LaunchAgent (prompts for sudo)
launchctl start com.marsegm.dailyupdate  # trigger the installed LaunchAgent now
tail -f /usr/local/var/log/update.log /usr/local/var/log/update.err   # LaunchAgent output
```

Verify changes with the first two lines; the next two change the real system. Uninstall steps are in README.md.

## Architecture

Three files that must agree on paths and the label `com.marsegm.dailyupdate`:

- `update.sh` is the payload. launchd runs the installed copy at `/usr/local/bin/update.sh`, so a repo edit takes effect on the schedule only after `install.sh` re-runs.
- `com.marsegm.dailyupdate.plist` points at that copy and the two logs in `/usr/local/var/log`. It also sets `PATH` for unattended runs (Homebrew + system dirs). launchd reads no shell profile, so a tool reachable only through `~/.zshrc` (e.g. asdf shims) is invisible there and its existence guard skips it.
- `install.sh` copies the script, creates world-writable logs, copies the plist into `~/Library/LaunchAgents`, rewrites the script path with `sed` (a no-op unless `UPDATE_SCRIPT_DST` changes), and reloads it.

`.github/workflows/archive.yml` runs the syntax check and tests, then zips exactly those three files on every push to `main`. A new file the install needs must be added to its `zip` line.

## Failure handling

Both scripts are zsh with `set -e`: a failing step (e.g. `brew upgrade` on a broken cask) aborts the rest of the run. Keep the `#!/usr/bin/env zsh` shebang; `update.sh` exits if `$ZSH_VERSION` is unset.

- **Optional tools** (asdf, Oh My Zsh) sit behind existence checks that print a skip message. Guard every new update target the same way.
- **softwareupdate** is the one step allowed to fail. With a TTY it runs `sudo softwareupdate -i -a`. In an unattended run (no TTY) it installs only if `sudo -n -l /usr/sbin/softwareupdate` passes (a NOPASSWD sudoers rule), logging a failed install and continuing. Otherwise it logs `softwareupdate -l` and moves on.
- `tests/test_update.sh` stubs `sudo`, `brew`, and `softwareupdate` to imitate these cases (cached credentials, scoped NOPASSWD, no TTY). When the sudo logic changes, update the `sudo` stub to match.
