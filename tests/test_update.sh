#!/usr/bin/env zsh
# Tests for update.sh. Run from the repo root: zsh tests/test_update.sh
# Every external command (brew, sudo, softwareupdate) is a stub in a temp dir;
# nothing real is invoked.

REPO=${0:A:h:h}
FAILED=0
TEST_FAILED=0
tmp=""

# --- harness -----------------------------------------------------------------

setup() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/update-test.XXXXXX") || { echo "mktemp failed"; exit 1; }
  mkdir -p "$tmp/bin" "$tmp/home"
  : > "$tmp/calls"

  cat > "$tmp/bin/brew" <<'STUB'
#!/bin/sh
echo "brew $*" >> "$STUB_CALLS"
if [ "$1" = upgrade ] && [ "$BREW_UPGRADE_FAILS" = 1 ]; then exit 1; fi
exit 0
STUB

  cat > "$tmp/bin/softwareupdate" <<'STUB'
#!/bin/sh
echo "softwareupdate $*" >> "$STUB_CALLS"
if [ "$1" = -l ] && [ "$SWU_LIST_FAILS" = 1 ]; then exit 1; fi
if [ "$1" = -i ] && [ "$SWU_INSTALL_FAILS" = 1 ]; then exit 1; fi
exit 0
STUB

  # Mimics real sudo: cached credentials, -n refusal, a prompt on a tty,
  # and the launchd failure when there is no tty.
  cat > "$tmp/bin/sudo" <<'STUB'
#!/bin/sh
echo "sudo $*" >> "$STUB_CALLS"
if [ "$SUDO_CACHED" = 1 ]; then
  [ "$1" = -n ] && shift
  # "-l <cmd>" is a permission probe: succeed without running anything.
  if [ "$1" = -l ]; then exit 0; fi
  exec "$@"
elif [ "$SUDO_ALLOW" = softwareupdate ] && [ "$1" = -n ]; then
  # Sudoers rule scoped to softwareupdate only (NOPASSWD).
  if [ "$2" = -l ] && [ "$3" = /usr/sbin/softwareupdate ]; then exit 0; fi
  if [ "$2" = softwareupdate ]; then shift; exec "$@"; fi
  echo "sudo: a password is required" >&2
  exit 1
elif [ "$1" = -n ]; then
  exit 1
elif [ -t 0 ]; then
  exec "$@"
else
  echo "sudo: a terminal is required to read the password" >&2
  exit 1
fi
STUB
  chmod +x "$tmp/bin/"*
}

teardown() {
  [ -n "$tmp" ] && rm -rf "$tmp"
  tmp=""
}

# run_update <notty|tty> [VAR=value ...]
# Sets $status_code and $output. Extra vars reach only this run (env -i).
run_update() {
  local mode=$1; shift
  local -a cmd=(env -i PATH="$tmp/bin:/usr/bin:/bin" HOME="$tmp/home" TERM=dumb
                STUB_CALLS="$tmp/calls" "$@" zsh "$REPO/update.sh")
  if [ "$mode" = tty ]; then
    # script gives the child a pty; its stdin is /dev/null (it echoes a
    # literal ^D then, which no assertion depends on).
    output=$(script -q /dev/null "${cmd[@]}" < /dev/null 2>&1)
  else
    output=$("${cmd[@]}" < /dev/null 2>&1)
  fi
  status_code=$?
}

fail() { echo "  $1"; TEST_FAILED=1; }
assert_called()     { grep -qxF -- "$1" "$tmp/calls" || fail "expected call: $1"; }
assert_not_called() { grep -qxF -- "$1" "$tmp/calls" && fail "unexpected call: $1"; return 0; }
assert_status()     { [ "$status_code" -eq "$1" ] || fail "expected status $1, got $status_code"; }
assert_status_nonzero() { [ "$status_code" -ne 0 ] || fail "expected non-zero status, got 0"; }
assert_output_contains()     { [[ "$output" == *"$1"* ]] || fail "output missing: $1"; }
assert_output_not_contains() { [[ "$output" != *"$1"* ]] || fail "output unexpectedly contains: $1"; }

# run_test <name>: runs the function <name> between setup and teardown.
run_test() {
  local name=$1
  TEST_FAILED=0
  setup
  "$name"
  if [ "$TEST_FAILED" -eq 0 ]; then
    echo "PASS $name"
  else
    echo "FAIL $name"
    echo "$output" | sed 's/^/    | /'
    FAILED=1
  fi
  teardown
}

# --- tests -------------------------------------------------------------------

test_no_tty_skips_softwareupdate() {
  run_update notty
  assert_status 0
  assert_called "softwareupdate -l"
  assert_called "brew update"
  assert_called "brew upgrade"
  assert_called "brew cleanup"
  assert_not_called "softwareupdate -i -a"
  assert_output_contains "Skipping: no terminal for the sudo password. Pending updates:"
  assert_output_contains "✅ All updates completed."
}

test_list_failure_is_not_fatal() {
  run_update notty SWU_LIST_FAILS=1
  assert_status 0
  assert_called "softwareupdate -l"
  assert_called "brew upgrade"
}

test_cached_sudo_installs() {
  run_update notty SUDO_CACHED=1
  assert_status 0
  assert_called "sudo -n softwareupdate -i -a"
  assert_called "softwareupdate -i -a"
  assert_called "brew upgrade"
  assert_not_called "softwareupdate -l"
}

test_scoped_nopasswd_installs() {
  run_update notty SUDO_ALLOW=softwareupdate
  assert_status 0
  assert_called "softwareupdate -i -a"
  assert_called "brew upgrade"
  assert_not_called "softwareupdate -l"
}

test_cached_install_failure_is_not_fatal() {
  run_update notty SUDO_CACHED=1 SWU_INSTALL_FAILS=1
  assert_status 0
  assert_called "brew upgrade"
  assert_output_contains "softwareupdate install failed (exit 1); continuing"
}

test_tty_prompts_sudo() {
  run_update tty
  assert_status 0
  assert_called "sudo softwareupdate -i -a"
  assert_not_called "sudo -n softwareupdate -i -a"
}

test_brew_failure_still_aborts() {
  run_update notty SUDO_CACHED=1 BREW_UPGRADE_FAILS=1
  assert_status_nonzero
  assert_called "brew upgrade"
  assert_not_called "brew cleanup"
  assert_output_not_contains "✅ All updates completed."
}

# --- main --------------------------------------------------------------------

trap 'teardown' EXIT

run_test test_no_tty_skips_softwareupdate
run_test test_list_failure_is_not_fatal
run_test test_cached_sudo_installs
run_test test_scoped_nopasswd_installs
run_test test_cached_install_failure_is_not_fatal

# script needs a pty; some sandboxes deny openpty.
if script -q /dev/null true < /dev/null > /dev/null 2>&1; then
  run_test test_tty_prompts_sudo
else
  if [ -n "$CI" ]; then
    echo "FAIL test_tty_prompts_sudo (no pty available in CI; interactive path unexercised)"
    FAILED=1
  else
    echo "SKIP test_tty_prompts_sudo (no pty available)"
  fi
fi

run_test test_brew_failure_still_aborts

exit $FAILED
