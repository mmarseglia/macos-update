# Launchd sudo skip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make scheduled (launchd) runs of `update.sh` reach the Homebrew, ASDF and Oh My Zsh steps instead of aborting at `sudo softwareupdate`.

**Architecture:** Replace the single `sudo softwareupdate -i -a` line with a three-way branch: interactive TTY → prompt as today; no TTY but cached sudo → `sudo -n`; otherwise skip the install and log pending updates. Add the repo's first test, a zsh script that runs `update.sh` against stub commands on `PATH`, and run it in CI.

**Tech Stack:** zsh, launchd, GitHub Actions (`macos-latest`). No new dependencies.

**Spec:** No separate spec doc; the requirements are the diagnosis below.

## Background (the diagnosis this plan implements)

The installed LaunchAgent `com.marsegm.dailyupdate` (Mondays 03:00) last ran 2026-10-26 03:04. `/usr/local/var/log/update.err` contains `sudo: a terminal is required to read the password` and `sudo: a password is required`; `update.log` contains only `🔧 Updating macOS software...`. Because of `set -e`, the failing first step aborts the script, so `brew update` / `brew upgrade` / `brew cleanup` have never run from launchd. The repo copies of `update.sh` and the plist are byte-identical to the installed ones.

## Global Constraints

- Keep the `#!/usr/bin/env zsh` shebang, `set -e`, and the `$ZSH_VERSION` guard in `update.sh`.
- Keep `set -e` semantics for every other step: a failing `brew` command must still abort the run.
- Interactive runs (`zsh update.sh` in a terminal) must behave exactly as before: `sudo softwareupdate -i -a` with a password prompt.
- No new tools or dependencies; `shellcheck` is not installed. Tests use only zsh and macOS base utilities (`script`, `mktemp`).
- Label `com.marsegm.dailyupdate`, script path `/usr/local/bin/update.sh` and log paths stay unchanged.
- Skip message text (exact): `Skipping: no terminal for the sudo password. Pending updates:`

## Review Focus

1. **No TTY, no cached sudo (the launchd case):** script must exit 0 and call `brew update`, `brew upgrade`, `brew cleanup`. Covered by `test_no_tty_skips_softwareupdate` (Task 1).
2. **`softwareupdate -l` exits non-zero** (no network, catalog error): must not abort the run under `set -e`. Covered by `test_list_failure_is_not_fatal` (Task 1).
3. **No TTY but sudo cached / NOPASSWD configured:** should install macOS updates non-interactively with `sudo -n`, never hang on a prompt. Covered by `test_cached_sudo_installs` (Task 1).
4. **Interactive terminal run:** unchanged `sudo softwareupdate -i -a` (no `-n`). Covered by `test_tty_prompts_sudo` (Task 1).
5. **`brew upgrade` fails** (broken cask): the run must still abort non-zero, i.e. the fix must not have weakened `set -e` globally. Covered by `test_brew_failure_still_aborts` (Task 1).

---

### Task 1: Non-fatal softwareupdate step, with tests

**Files:**
- Create: `tests/test_update.sh`
- Modify: `update.sh:10-11` (the `🔧 Updating macOS software...` block)

**Interfaces:**
- Consumes: nothing.
- Produces: `tests/test_update.sh`, runnable as `zsh tests/test_update.sh` from the repo root; prints `PASS <name>` / `FAIL <name>` per test and exits non-zero if any test fails. Task 2 calls exactly this command.

- [ ] **Step 1: Write the test harness and the five tests in `tests/test_update.sh`**

Harness, per test:
- `tmp=$(mktemp -d)`; put stub executables in `$tmp/bin`; run `update.sh` with `PATH="$tmp/bin:/usr/bin:/bin"` and `HOME="$tmp/home"` (empty dir, so the asdf and Oh My Zsh branches take their "not installed" paths).
- Every stub appends `"<name> $*"` as one line to `$tmp/calls`.
- Stubs: `brew` (exit 0, or exit 1 when invoked as `brew upgrade` and `BREW_UPGRADE_FAILS=1`); `softwareupdate` (exit 0, or exit 1 when `SWU_LIST_FAILS=1` and `$1 = -l`); `sudo` (logs, then mimics real sudo: if `SUDO_CACHED = 1` → drop a leading `-n` and `exec "$@"`; else if `$1 = -n` → exit 1; else if `[ -t 0 ]` → `exec "$@"` (stands in for a successful password prompt); else print `sudo: a terminal is required to read the password` to stderr and exit 1).
- No-TTY runs: `zsh update.sh < /dev/null`. TTY run: `script -q /dev/null zsh update.sh` (gives a pty so `[ -t 0 ]` is true).
- Capture the exit status and combined output; assert with small helpers `assert_called "<line>"`, `assert_not_called "<line>"`, `assert_status <n>`, `assert_output_contains "<text>"`.

Tests and assertions:

```text
test_no_tty_skips_softwareupdate   (< /dev/null, SUDO_CACHED unset)
  status 0
  called: "softwareupdate -l", "brew update", "brew upgrade", "brew cleanup"
  not called: "softwareupdate -i -a"
  output contains: "Skipping: no terminal for the sudo password. Pending updates:"
  output contains: "✅ All updates completed."

test_list_failure_is_not_fatal     (< /dev/null, SWU_LIST_FAILS=1)
  status 0
  called: "softwareupdate -l", "brew upgrade"

test_cached_sudo_installs          (< /dev/null, SUDO_CACHED=1)
  status 0
  called: "sudo -n softwareupdate -i -a", "softwareupdate -i -a", "brew upgrade"
  not called: "softwareupdate -l"

test_tty_prompts_sudo              (script -q /dev/null ..., SUDO_CACHED unset)
  status 0
  called: "sudo softwareupdate -i -a"
  not called: "sudo -n softwareupdate -i -a"

test_brew_failure_still_aborts     (< /dev/null, BREW_UPGRADE_FAILS=1)
  status non-zero
  called: "brew upgrade"
  not called: "brew cleanup"
  output does not contain: "✅ All updates completed."
```

Note: the `sudo -n true` probe also appears in `$tmp/calls` as `sudo -n true`; assertions above match whole lines, so it does not collide.

- [ ] **Step 2: Run the tests and confirm the expected failures against the current script**

Run: `zsh tests/test_update.sh`
Expected: `FAIL test_no_tty_skips_softwareupdate` (non-zero status: the stub sudo reproduces the launchd error), `FAIL test_list_failure_is_not_fatal`, `FAIL test_cached_sudo_installs`; `PASS test_tty_prompts_sudo`, `PASS test_brew_failure_still_aborts` (current script already behaves correctly there); exit status non-zero. If `test_no_tty_skips_softwareupdate` passes here, the stub isn't reproducing the bug: fix the harness before continuing.

- [ ] **Step 3: Replace `update.sh` line 11 with the three-way branch**

```zsh
if [ -t 0 ]; then
  sudo softwareupdate -i -a
elif sudo -n true 2>/dev/null; then
  sudo -n softwareupdate -i -a
else
  echo "Skipping: no terminal for the sudo password. Pending updates:"
  softwareupdate -l || true
fi
```

- [ ] **Step 4: Run tests and syntax check**

Run: `zsh tests/test_update.sh && zsh -n update.sh && zsh -n install.sh`
Expected: five `PASS` lines, exit status 0.

- [ ] **Step 5: Commit**

```bash
git add update.sh tests/test_update.sh
git commit -m "fix: skip sudo softwareupdate without a TTY so launchd runs reach brew"
```

---

### Task 2: Run the tests in CI

**Files:**
- Modify: `.github/workflows/archive.yml` (add a step between "Checkout repository" and "Create zip archive")

**Interfaces:**
- Consumes: `zsh tests/test_update.sh` from Task 1.
- Produces: nothing later tasks use.

- [ ] **Step 1: Add the step**

Name `Run tests`, `run: zsh -n update.sh && zsh -n install.sh && zsh tests/test_update.sh`. Leave the zip contents unchanged (tests are not shipped).

- [ ] **Step 2: Verify the workflow file parses**

Run: `ruby -ryaml -e 'YAML.load_file(".github/workflows/archive.yml")' && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/archive.yml
git commit -m "ci: run update.sh tests before archiving"
```

---

### Task 3: Bring docs in line

**Files:**
- Modify: `CLAUDE.md` ("Commands" and "Things to know" sections)
- Modify: `README.md` ("Features" section)

**Interfaces:**
- Consumes: the behavior from Task 1 and the CI step from Task 2.
- Produces: nothing.

- [ ] **Step 1: Update `CLAUDE.md`**

- Commands: add `zsh tests/test_update.sh   # stubbed tests for update.sh`.
- Intro: replace "There is no build step, package manager, or test suite." with "There is no build step or package manager; `tests/test_update.sh` runs `update.sh` against stub commands."
- Architecture: `archive.yml` now runs the tests before zipping.
- Things to know: delete the "The plist is missing from the repo" bullet (stale since commit `a8972ed`). Replace the `sudo softwareupdate` bullet with: without a TTY, the script uses `sudo -n` if credentials are cached, otherwise skips macOS updates and logs `softwareupdate -l`; Homebrew and later steps still run.

- [ ] **Step 2: Update `README.md`**

Under Features, add one line: scheduled runs can't prompt for a sudo password, so they skip installing macOS updates (pending ones are listed in `/usr/local/var/log/update.log`) unless sudo is already cached; run `zsh update.sh` in a terminal to install them.

- [ ] **Step 3: Verify**

Run: `grep -n "plist is missing" CLAUDE.md; grep -n "test_update.sh" CLAUDE.md`
Expected: no output from the first grep; at least one line from the second.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: document no-TTY softwareupdate behavior and tests"
```

---

### Task 4: Install and confirm on this Mac (user, manual)

Requires the user's sudo password, so an agent cannot run it.

- [ ] **Step 1:** `zsh install.sh` (copies the fixed script to `/usr/local/bin`, reloads the LaunchAgent).
- [ ] **Step 2:** `diff update.sh /usr/local/bin/update.sh && echo INSTALLED` → expected `INSTALLED`.
- [ ] **Step 3:** `launchctl start com.marsegm.dailyupdate`, wait for it to finish, then `tail -20 /usr/local/var/log/update.log` → expected the `Skipping: ...` line followed by `🍺 Updating Homebrew and packages...` and finally `✅ All updates completed.`
