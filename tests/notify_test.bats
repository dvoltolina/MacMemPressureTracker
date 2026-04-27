#!/usr/bin/env bats
# Tests for lib/notify.sh.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TMP="$(mktemp -d)"
  export MPM_LOG_PATH="${TMP}/log.jsonl"
  export MPM_NOTIFICATION_BACKEND=stderr
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/lib/log.sh"
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/lib/notify.sh"
}

teardown() {
  rm -rf "${TMP}"
}

@test "stderr backend prints expected line and returns 0" {
  run notify::send "Memory pressure: red" "Free 3%."
  [ "$status" -eq 0 ]
  [[ "$output" == *"notify: title=Memory pressure: red body=Free 3%. sound="* ]]
}

@test "stderr backend includes sound argument" {
  run notify::send "T" "B" "Submarine"
  [[ "$output" == *"sound=Submarine"* ]]
}

@test "applescript escaping handles double-quote and backslash" {
  run bash -c "
    source '${REPO_ROOT}/lib/notify.sh'
    _notify::escape_applescript 'a\"b\\\\c'
  "
  [ "$output" = 'a\"b\\\\c' ]
}

@test "osascript backend invokes osascript with escaped script" {
  # Stub osascript on PATH; capture its argv.
  STUB="${TMP}/bin"
  mkdir -p "${STUB}"
  cat > "${STUB}/osascript" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "${TMP}/osascript.argv"
exit 0
STUB
  chmod +x "${STUB}/osascript"
  PATH="${STUB}:${PATH}" MPM_NOTIFICATION_BACKEND=osascript notify::send 'Hello' 'World "X"'
  run cat "${TMP}/osascript.argv"
  [[ "$output" == *'-e'* ]]
  [[ "$output" == *'display notification'* ]]
  [[ "$output" == *'\"X\"'* ]]
}

@test "osascript backend returns non-zero on failure" {
  STUB="${TMP}/bin"
  mkdir -p "${STUB}"
  cat > "${STUB}/osascript" <<'STUB'
#!/bin/bash
exit 7
STUB
  chmod +x "${STUB}/osascript"
  run env PATH="${STUB}:${PATH}" MPM_NOTIFICATION_BACKEND=osascript bash -c \
    "source '${REPO_ROOT}/lib/log.sh'; source '${REPO_ROOT}/lib/notify.sh'; notify::send T B"
  [ "$status" -eq 7 ]
}

@test "terminal-notifier missing -> falls back to osascript with warn" {
  STUB="${TMP}/bin"
  mkdir -p "${STUB}"
  cat > "${STUB}/osascript" <<'STUB'
#!/bin/bash
echo "osascript called" > "${TMP}/osa.flag"
exit 0
STUB
  chmod +x "${STUB}/osascript"
  PATH="${STUB}:${PATH}" MPM_NOTIFICATION_BACKEND=terminal-notifier notify::send T B
  [ -f "${TMP}/osa.flag" ]
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'notify_fallback'* ]]
}
