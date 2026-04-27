#!/usr/bin/env bats
# Tests for lib/log.sh — JSONL logger.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TMP="$(mktemp -d)"
  export MPM_LOG_PATH="${TMP}/log.jsonl"
  export TEST_NOW="2026-04-27T08:45:00-07:00"
  unset MPM_LOG_TEE_STDERR
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/lib/log.sh"
}

teardown() {
  rm -rf "${TMP}"
}

@test "log::info writes one line of valid JSON" {
  log::info sample_taken zone=normal free_pct=42.1
  run cat "${MPM_LOG_PATH}"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "${MPM_LOG_PATH}" | tr -d ' ')" = "1" ]
  [[ "$output" == *'"ts":"2026-04-27T08:45:00-07:00"'* ]]
  [[ "$output" == *'"level":"info"'* ]]
  [[ "$output" == *'"event":"sample_taken"'* ]]
  [[ "$output" == *'"zone":"normal"'* ]]
  [[ "$output" == *'"free_pct":42.1'* ]]
}

@test "log::warn and log::error use correct levels" {
  log::warn parse_failed reason=bad_format
  log::error notify_failed code=1
  run cat "${MPM_LOG_PATH}"
  [ "$(wc -l < "${MPM_LOG_PATH}" | tr -d ' ')" = "2" ]
  [[ "$output" == *'"level":"warn"'* ]]
  [[ "$output" == *'"level":"error"'* ]]
}

@test "log::info escapes quotes and backslashes in values" {
  log::info weird_event payload='hello "world" \\ and more'
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'\"world\"'* ]]
  [[ "$output" == *'\\\\'* ]]
}

@test "log::info emits numeric values unquoted" {
  log::info nums int_val=42 float_val=3.14 neg_val=-1
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'"int_val":42'* ]]
  [[ "$output" == *'"float_val":3.14'* ]]
  [[ "$output" == *'"neg_val":-1'* ]]
  [[ "$output" != *'"int_val":"42"'* ]]
}

@test "log::info honors TEST_NOW" {
  TEST_NOW="2030-01-02T03:04:05+00:00" log::info marker
  run cat "${MPM_LOG_PATH}"
  [[ "$output" == *'"ts":"2030-01-02T03:04:05+00:00"'* ]]
}

@test "log::info creates the parent directory lazily" {
  rm -rf "${TMP}/nested"
  MPM_LOG_PATH="${TMP}/nested/deep/log.jsonl" log::info created_dir
  [ -f "${TMP}/nested/deep/log.jsonl" ]
}

@test "MPM_LOG_TEE_STDERR=1 also writes to stderr" {
  MPM_LOG_TEE_STDERR=1 log::info teed 2> "${TMP}/err"
  [ -s "${TMP}/err" ]
  run cat "${TMP}/err"
  [[ "$output" == *'"event":"teed"'* ]]
}

@test "log::path returns the resolved path" {
  run log::path
  [ "$output" = "${MPM_LOG_PATH}" ]
}

@test "writes append (do not overwrite)" {
  log::info first
  log::info second
  [ "$(wc -l < "${MPM_LOG_PATH}" | tr -d ' ')" = "2" ]
}
