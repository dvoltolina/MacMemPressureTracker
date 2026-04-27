#!/usr/bin/env bats
# Smoke test — runs against the bootstrap scaffold. Verifies the repo
# layout is intact and required docs are present. As real implementation
# lands, additional bats files cover behavior.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "required top-level docs exist" {
  for f in CLAUDE.md AGENTS.md ARCHITECTURE.md CONSISTENCY.md REPO_STATUS.md CHANGELOG.md README.md; do
    [ -f "${REPO_ROOT}/${f}" ] || {
      echo "missing required doc: ${f}"
      return 1
    }
  done
}

@test "required directories exist" {
  for d in scripts lib launchd tests config prompts .github/workflows; do
    [ -d "${REPO_ROOT}/${d}" ] || {
      echo "missing required directory: ${d}"
      return 1
    }
  done
}

@test "Makefile exists and exposes a help target" {
  [ -f "${REPO_ROOT}/Makefile" ]
  run grep -q '^help:' "${REPO_ROOT}/Makefile"
  [ "$status" -eq 0 ]
}

@test ".gitignore covers state and logs" {
  run grep -E '^(state/|logs/|\*\.log)$' "${REPO_ROOT}/.gitignore"
  [ "$status" -eq 0 ]
}

@test "every committed shell library file sources cleanly" {
  shopt -s nullglob
  local files=("${REPO_ROOT}"/lib/*.sh)
  if [ "${#files[@]}" -eq 0 ]; then
    skip "no library files yet — placeholder"
  fi
  for f in "${files[@]}"; do
    bash -n "$f" || {
      echo "syntax error in $f"
      return 1
    }
  done
}
