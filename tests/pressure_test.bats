#!/usr/bin/env bats
# Tests for lib/pressure.sh — sysctl + vm_stat parser.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FIX="${REPO_ROOT}/tests/fixtures"
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/lib/pressure.sh"
}

# --- Individual parsers --------------------------------------------------

@test "parse_pressure_level: normal=1" {
  run bash -c "source '${REPO_ROOT}/lib/pressure.sh' && pressure::parse_pressure_level < '${FIX}/sysctl_pressure_level_normal.txt'"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "parse_pressure_level: warn=2" {
  run bash -c "source '${REPO_ROOT}/lib/pressure.sh' && pressure::parse_pressure_level < '${FIX}/sysctl_pressure_level_warn.txt'"
  [ "$output" = "2" ]
}

@test "parse_pressure_level: critical=4" {
  run bash -c "source '${REPO_ROOT}/lib/pressure.sh' && pressure::parse_pressure_level < '${FIX}/sysctl_pressure_level_critical.txt'"
  [ "$output" = "4" ]
}

@test "parse_pressure_level: malformed input fails" {
  run bash -c "source '${REPO_ROOT}/lib/pressure.sh' && printf 'garbage' | pressure::parse_pressure_level"
  [ "$status" -ne 0 ]
}

@test "parse_free_level: integer percentage" {
  run bash -c "source '${REPO_ROOT}/lib/pressure.sh' && pressure::parse_free_level < '${FIX}/sysctl_memorystatus_level.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "parse_swap: active swap returns positive integer MiB" {
  run bash -c "source '${REPO_ROOT}/lib/pressure.sh' && pressure::parse_swap < '${FIX}/sysctl_swapusage_active.txt'"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
}

@test "parse_swap: inactive swap returns 0" {
  run bash -c "source '${REPO_ROOT}/lib/pressure.sh' && pressure::parse_swap < '${FIX}/sysctl_swapusage_inactive.txt'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
}

@test "parse_compressed: vm_stat returns positive page count" {
  run bash -c "source '${REPO_ROOT}/lib/pressure.sh' && pressure::parse_compressed < '${FIX}/vm_stat_macos26.txt'"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
}

# --- Zone classification -------------------------------------------------

@test "is_red: critical zone is red" {
  run bash -c "source '${REPO_ROOT}/lib/pressure.sh' && pressure::is_red '{\"zone\":\"red\",\"free_pct\":3,\"compressed_pages\":900000,\"swap_used_mib\":1500}'"
  [ "$status" -eq 0 ]
}

@test "is_red: warn zone is not red" {
  run bash -c "source '${REPO_ROOT}/lib/pressure.sh' && pressure::is_red '{\"zone\":\"warn\",\"free_pct\":15,\"compressed_pages\":500000,\"swap_used_mib\":200}'"
  [ "$status" -ne 0 ]
}

@test "is_red: normal zone is not red" {
  run bash -c "source '${REPO_ROOT}/lib/pressure.sh' && pressure::is_red '{\"zone\":\"normal\",\"free_pct\":53,\"compressed_pages\":100000,\"swap_used_mib\":0}'"
  [ "$status" -ne 0 ]
}

# --- Swap threshold ------------------------------------------------------

@test "swap_in_use: above threshold returns 0" {
  run bash -c "MPM_SWAP_THRESHOLD_MIB=64 && source '${REPO_ROOT}/lib/pressure.sh' && pressure::swap_in_use '{\"zone\":\"normal\",\"free_pct\":50,\"compressed_pages\":100,\"swap_used_mib\":2806}'"
  [ "$status" -eq 0 ]
}

@test "swap_in_use: at threshold returns 0" {
  run bash -c "MPM_SWAP_THRESHOLD_MIB=64 && source '${REPO_ROOT}/lib/pressure.sh' && pressure::swap_in_use '{\"zone\":\"normal\",\"free_pct\":50,\"compressed_pages\":100,\"swap_used_mib\":64}'"
  [ "$status" -eq 0 ]
}

@test "swap_in_use: below threshold returns non-zero" {
  run bash -c "MPM_SWAP_THRESHOLD_MIB=64 && source '${REPO_ROOT}/lib/pressure.sh' && pressure::swap_in_use '{\"zone\":\"normal\",\"free_pct\":50,\"compressed_pages\":100,\"swap_used_mib\":0}'"
  [ "$status" -ne 0 ]
}

# --- Composite sample with stubbed externals -----------------------------

@test "sample: stubbed externals produce a valid red+swap JSON line" {
  run bash -c "
    source '${REPO_ROOT}/lib/pressure.sh'
    _pressure::_invoke_external() {
      case \"\$1\" in
        pressure_level) cat '${FIX}/sysctl_pressure_level_critical.txt' ;;
        free_level) cat '${FIX}/sysctl_memorystatus_level.txt' ;;
        vm_stat) cat '${FIX}/vm_stat_macos26.txt' ;;
        swapusage) cat '${FIX}/sysctl_swapusage_active.txt' ;;
      esac
    }
    pressure::sample
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *'"zone":"red"'* ]]
  [[ "$output" =~ \"swap_used_mib\":[1-9][0-9]+ ]]
}

@test "sample: normal zone with no swap" {
  run bash -c "
    source '${REPO_ROOT}/lib/pressure.sh'
    _pressure::_invoke_external() {
      case \"\$1\" in
        pressure_level) cat '${FIX}/sysctl_pressure_level_normal.txt' ;;
        free_level) cat '${FIX}/sysctl_memorystatus_level.txt' ;;
        vm_stat) cat '${FIX}/vm_stat_macos26.txt' ;;
        swapusage) cat '${FIX}/sysctl_swapusage_inactive.txt' ;;
      esac
    }
    pressure::sample
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *'"zone":"normal"'* ]]
  [[ "$output" == *'"swap_used_mib":0'* ]]
}

@test "sample: malformed primary pressure level fails even if secondary fields parse" {
  run bash -c "
    source '${REPO_ROOT}/lib/pressure.sh'
    _pressure::_invoke_external() {
      case \"\$1\" in
        pressure_level) printf 'kern.memorystatus_vm_pressure_level: nope\n' ;;
        free_level) cat '${FIX}/sysctl_memorystatus_level.txt' ;;
        vm_stat) cat '${FIX}/vm_stat_macos26.txt' ;;
        swapusage) cat '${FIX}/sysctl_swapusage_inactive.txt' ;;
      esac
    }
    pressure::sample
  "
  [ "$status" -ne 0 ]
}

@test "sample: malformed swap output fails instead of reporting zero" {
  run bash -c "
    source '${REPO_ROOT}/lib/pressure.sh'
    _pressure::_invoke_external() {
      case \"\$1\" in
        pressure_level) cat '${FIX}/sysctl_pressure_level_normal.txt' ;;
        free_level) cat '${FIX}/sysctl_memorystatus_level.txt' ;;
        vm_stat) cat '${FIX}/vm_stat_macos26.txt' ;;
        swapusage) printf 'vm.swapusage: unexpected units used = 1.5G\n' ;;
      esac
    }
    pressure::sample
  "
  [ "$status" -ne 0 ]
}
