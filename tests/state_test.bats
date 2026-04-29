#!/usr/bin/env bats
# Tests for lib/state.sh — debounce state file manager (schema 2).
#
# Schema 2 shape:
#   {"schema":2,
#    "last_alert":{"red_pressure":<iso|null>,
#                  "warn_pressure":<iso|null>,
#                  "swap_in_use":<iso|null>},
#    "swap_alerted_mib":<int>}
#
# Schema 1 (legacy: swap_active boolean, no warn_pressure key) is read
# transparently and rewritten as schema 2 on the next write.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TMP="$(mktemp -d)"
  export MPM_STATE_PATH="${TMP}/state.json"
  export MPM_LOG_PATH="${TMP}/log.jsonl"
  export MPM_RED_COOLDOWN_SECONDS=600
  export MPM_WARN_COOLDOWN_SECONDS=1800
  export MPM_SWAP_COOLDOWN_SECONDS=900
  export MPM_SWAP_THRESHOLD_MIB=64
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/lib/log.sh"
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/lib/state.sh"
}

teardown() {
  rm -rf "${TMP}"
}

# Returns epoch seconds for a fixed ISO timestamp used across tests.
_iso_epoch() {
  date -j -f "%Y-%m-%dT%H:%M:%S%z" "$1" +%s
}

# ---------------------------------------------------------------------------
# Path / reset / unknown-kind plumbing
# ---------------------------------------------------------------------------

@test "state::path returns the override" {
  run state::path
  [ "$output" = "${MPM_STATE_PATH}" ]
}

@test "state::reset removes the state file" {
  TEST_NOW_ISO="2026-04-27T08:45:00-07:00" state::record_alert red_pressure
  [ -f "${MPM_STATE_PATH}" ]
  state::reset
  [ ! -f "${MPM_STATE_PATH}" ]
}

@test "should_alert: missing state file returns 0 (allow)" {
  run state::should_alert red_pressure
  [ "$status" -eq 0 ]
}

@test "should_alert with unknown kind returns rc=2" {
  run state::should_alert garbage_kind
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# record_alert: schema 2 output and field preservation
# ---------------------------------------------------------------------------

@test "record_alert red_pressure writes schema-2 JSON with empty companions" {
  TEST_NOW_ISO="2026-04-27T08:45:00-07:00" state::record_alert red_pressure
  [ -f "${MPM_STATE_PATH}" ]
  run cat "${MPM_STATE_PATH}"
  [[ "$output" == *'"schema":2'* ]]
  [[ "$output" == *'"red_pressure":"2026-04-27T08:45:00-07:00"'* ]]
  [[ "$output" == *'"warn_pressure":null'* ]]
  [[ "$output" == *'"swap_in_use":null'* ]]
  [[ "$output" == *'"swap_alerted_mib":0'* ]]
  [[ "$output" != *'swap_active'* ]]
}

@test "record_alert warn_pressure populates warn_pressure key" {
  TEST_NOW_ISO="2026-04-27T08:45:00-07:00" state::record_alert warn_pressure
  run cat "${MPM_STATE_PATH}"
  [[ "$output" == *'"warn_pressure":"2026-04-27T08:45:00-07:00"'* ]]
  [[ "$output" == *'"red_pressure":null'* ]]
}

@test "record_alert swap_in_use with explicit MiB stores swap_alerted_mib" {
  TEST_NOW_ISO="2026-04-27T08:45:00-07:00" state::record_alert swap_in_use 4096
  run cat "${MPM_STATE_PATH}"
  [[ "$output" == *'"swap_in_use":"2026-04-27T08:45:00-07:00"'* ]]
  [[ "$output" == *'"swap_alerted_mib":4096'* ]]
}

@test "record_alert swap_in_use without MiB preserves prior swap_alerted_mib" {
  TEST_NOW_ISO="2026-04-27T08:45:00-07:00" state::record_alert swap_in_use 2048
  TEST_NOW_ISO="2026-04-27T09:45:00-07:00" state::record_alert swap_in_use
  run cat "${MPM_STATE_PATH}"
  [[ "$output" == *'"swap_in_use":"2026-04-27T09:45:00-07:00"'* ]]
  [[ "$output" == *'"swap_alerted_mib":2048'* ]]
}

@test "record_alert preserves all other kinds' timestamps" {
  TEST_NOW_ISO="2026-04-27T08:00:00-07:00" state::record_alert red_pressure
  TEST_NOW_ISO="2026-04-27T08:30:00-07:00" state::record_alert warn_pressure
  TEST_NOW_ISO="2026-04-27T09:00:00-07:00" state::record_alert swap_in_use 1024
  run cat "${MPM_STATE_PATH}"
  [[ "$output" == *'"red_pressure":"2026-04-27T08:00:00-07:00"'* ]]
  [[ "$output" == *'"warn_pressure":"2026-04-27T08:30:00-07:00"'* ]]
  [[ "$output" == *'"swap_in_use":"2026-04-27T09:00:00-07:00"'* ]]
  [[ "$output" == *'"swap_alerted_mib":1024'* ]]
}

@test "record_alert red_pressure preserves swap_alerted_mib" {
  TEST_NOW_ISO="2026-04-27T08:00:00-07:00" state::record_alert swap_in_use 3072
  TEST_NOW_ISO="2026-04-27T09:00:00-07:00" state::record_alert red_pressure
  run cat "${MPM_STATE_PATH}"
  [[ "$output" == *'"swap_alerted_mib":3072'* ]]
}

# ---------------------------------------------------------------------------
# should_alert cooldowns per kind
# ---------------------------------------------------------------------------

@test "should_alert red: just-recorded alert suppressed within cooldown" {
  TEST_NOW_ISO="2026-04-27T08:45:00-07:00" \
    TEST_NOW=$(_iso_epoch "2026-04-27T08:45:00-0700") \
    state::record_alert red_pressure

  later=$(($(_iso_epoch "2026-04-27T08:45:00-0700") + 300))
  run env TEST_NOW="${later}" bash -c "source '${REPO_ROOT}/lib/log.sh'; source '${REPO_ROOT}/lib/state.sh'; state::should_alert red_pressure"
  [ "$status" -eq 1 ]
}

@test "should_alert red: cooldown elapsed returns 0" {
  TEST_NOW_ISO="2026-04-27T08:45:00-07:00" \
    TEST_NOW=$(_iso_epoch "2026-04-27T08:45:00-0700") \
    state::record_alert red_pressure

  later=$(($(_iso_epoch "2026-04-27T08:45:00-0700") + 660))
  run env TEST_NOW="${later}" bash -c "source '${REPO_ROOT}/lib/log.sh'; source '${REPO_ROOT}/lib/state.sh'; state::should_alert red_pressure"
  [ "$status" -eq 0 ]
}

@test "should_alert warn: uses warn cooldown distinct from red" {
  TEST_NOW_ISO="2026-04-27T08:00:00-07:00" \
    TEST_NOW=$(_iso_epoch "2026-04-27T08:00:00-0700") \
    state::record_alert warn_pressure

  # 1500s later (< 1800s warn cooldown) — suppressed.
  later=$(($(_iso_epoch "2026-04-27T08:00:00-0700") + 1500))
  run env TEST_NOW="${later}" bash -c "source '${REPO_ROOT}/lib/log.sh'; source '${REPO_ROOT}/lib/state.sh'; state::should_alert warn_pressure"
  [ "$status" -eq 1 ]

  # 1900s later — past the warn cooldown.
  later=$(($(_iso_epoch "2026-04-27T08:00:00-0700") + 1900))
  run env TEST_NOW="${later}" bash -c "source '${REPO_ROOT}/lib/log.sh'; source '${REPO_ROOT}/lib/state.sh'; state::should_alert warn_pressure"
  [ "$status" -eq 0 ]

  # red was never recorded; should always be allowed regardless of warn timing.
  run env TEST_NOW="${later}" bash -c "source '${REPO_ROOT}/lib/log.sh'; source '${REPO_ROOT}/lib/state.sh'; state::should_alert red_pressure"
  [ "$status" -eq 0 ]
}

@test "should_alert swap_in_use: uses swap cooldown" {
  TEST_NOW_ISO="2026-04-27T08:00:00-07:00" \
    TEST_NOW=$(_iso_epoch "2026-04-27T08:00:00-0700") \
    state::record_alert swap_in_use 1024

  # 800s later (< 900s swap cooldown).
  later=$(($(_iso_epoch "2026-04-27T08:00:00-0700") + 800))
  run env TEST_NOW="${later}" bash -c "source '${REPO_ROOT}/lib/log.sh'; source '${REPO_ROOT}/lib/state.sh'; state::should_alert swap_in_use"
  [ "$status" -eq 1 ]

  later=$(($(_iso_epoch "2026-04-27T08:00:00-0700") + 1000))
  run env TEST_NOW="${later}" bash -c "source '${REPO_ROOT}/lib/log.sh'; source '${REPO_ROOT}/lib/state.sh'; state::should_alert swap_in_use"
  [ "$status" -eq 0 ]
}

@test "should_alert parses pretty schema-2 JSON with whitespace" {
  cat > "${MPM_STATE_PATH}" << 'JSON'
{
  "schema": 2,
  "last_alert": {
    "red_pressure": "2026-04-27T08:45:00-07:00",
    "warn_pressure": null,
    "swap_in_use": null
  },
  "swap_alerted_mib": 0
}
JSON

  now=$(($(_iso_epoch "2026-04-27T08:45:00-0700") + 300))
  run env TEST_NOW="${now}" bash -c "source '${REPO_ROOT}/lib/log.sh'; source '${REPO_ROOT}/lib/state.sh'; state::should_alert red_pressure"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# swap_alerted_mib accessor + width-clamp regressions
# ---------------------------------------------------------------------------

@test "swap_alerted_mib reads pretty-printed integer (B1 audit regression)" {
  cat > "${MPM_STATE_PATH}" << 'JSON'
{
  "schema": 2,
  "last_alert": {
    "red_pressure": null,
    "warn_pressure": null,
    "swap_in_use": null
  },
  "swap_alerted_mib": 4096
}
JSON
  run state::swap_alerted_mib
  [ "$output" = "4096" ]
}

@test "swap_alerted_mib clamps absurd values on read (S-2 audit regression)" {
  printf '%s' '{"schema":2,"last_alert":{"red_pressure":null,"warn_pressure":null,"swap_in_use":null},"swap_alerted_mib":999999999999999}' > "${MPM_STATE_PATH}"
  run state::swap_alerted_mib
  [ "$output" = "0" ]
}

@test "swap_alerted_mib defaults to 0 on missing state" {
  run state::swap_alerted_mib
  [ "$output" = "0" ]
}

@test "set_swap_alerted_mib preserves timestamps and writes schema 2" {
  TEST_NOW_ISO="2026-04-27T08:00:00-07:00" state::record_alert red_pressure
  TEST_NOW_ISO="2026-04-27T08:30:00-07:00" state::record_alert warn_pressure

  state::set_swap_alerted_mib 2048
  run cat "${MPM_STATE_PATH}"
  [[ "$output" == *'"schema":2'* ]]
  [[ "$output" == *'"red_pressure":"2026-04-27T08:00:00-07:00"'* ]]
  [[ "$output" == *'"warn_pressure":"2026-04-27T08:30:00-07:00"'* ]]
  [[ "$output" == *'"swap_alerted_mib":2048'* ]]
}

@test "set_swap_alerted_mib rejects non-integer with rc=2" {
  run state::set_swap_alerted_mib "abc"
  [ "$status" -eq 2 ]
  run state::set_swap_alerted_mib ""
  [ "$status" -eq 2 ]
  run state::set_swap_alerted_mib "12 34"
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Schema 1 → schema 2 migration on read and on next write
# ---------------------------------------------------------------------------

@test "schema-1 swap_active=true reads as MPM_SWAP_THRESHOLD_MIB" {
  cat > "${MPM_STATE_PATH}" << 'JSON'
{"schema":1,"last_alert":{"red_pressure":null,"swap_in_use":"2026-04-25T10:00:00-07:00"},"swap_active":true}
JSON
  run state::swap_alerted_mib
  [ "$output" = "64" ]
}

@test "schema-1 swap_active=false reads as 0" {
  cat > "${MPM_STATE_PATH}" << 'JSON'
{"schema":1,"last_alert":{"red_pressure":null,"swap_in_use":null},"swap_active":false}
JSON
  run state::swap_alerted_mib
  [ "$output" = "0" ]
}

@test "schema-1 with swap_in_use ts but no swap_active infers threshold" {
  # Pre-schema-1 file shape — neither swap_active nor swap_alerted_mib.
  cat > "${MPM_STATE_PATH}" << 'JSON'
{"schema":1,"last_alert":{"red_pressure":null,"swap_in_use":"2026-04-25T10:00:00-07:00"}}
JSON
  run state::swap_alerted_mib
  [ "$output" = "64" ]
}

@test "schema-1 file is rewritten as schema 2 on next record_alert" {
  cat > "${MPM_STATE_PATH}" << 'JSON'
{"schema":1,"last_alert":{"red_pressure":"2026-04-25T10:00:00-07:00","swap_in_use":"2026-04-25T10:05:00-07:00"},"swap_active":true}
JSON

  TEST_NOW_ISO="2026-04-27T09:00:00-07:00" state::record_alert red_pressure

  run cat "${MPM_STATE_PATH}"
  [[ "$output" == *'"schema":2'* ]]
  [[ "$output" == *'"red_pressure":"2026-04-27T09:00:00-07:00"'* ]]
  [[ "$output" == *'"swap_in_use":"2026-04-25T10:05:00-07:00"'* ]]
  [[ "$output" == *'"warn_pressure":null'* ]]
  [[ "$output" == *'"swap_alerted_mib":64'* ]]
  [[ "$output" != *'swap_active'* ]]
}

# ---------------------------------------------------------------------------
# Corruption handling
# ---------------------------------------------------------------------------

@test "corrupt state file: should_alert returns 0 (allow)" {
  printf 'this is not json at all' > "${MPM_STATE_PATH}"
  run state::should_alert red_pressure
  [ "$status" -eq 0 ]
}

@test "state file with schema but missing alert keys logs corruption warning" {
  printf '{"schema":2,' > "${MPM_STATE_PATH}"
  run state::should_alert red_pressure
  [ "$status" -eq 0 ]
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'"event":"state_corrupted"'* ]]
}

# ---------------------------------------------------------------------------
# Atomic write
# ---------------------------------------------------------------------------

@test "atomic write: no .tmp file left behind on success" {
  TEST_NOW_ISO="2026-04-27T08:45:00-07:00" state::record_alert red_pressure
  run bash -c "ls '${MPM_STATE_PATH}'.tmp.* 2>/dev/null | wc -l"
  [ "$(echo "$output" | tr -d ' ')" = "0" ]
  run bash -c "ls '$(dirname "${MPM_STATE_PATH}")'/.last_alert.* 2>/dev/null | wc -l"
  [ "$(echo "$output" | tr -d ' ')" = "0" ]
}
