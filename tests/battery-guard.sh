#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d /tmp/rom-splitter-battery.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT

export ROMS2_BASE_DIR="$test_root/app"
export ROMS_ROOT="$test_root/roms"
export ROMS2_ROOT="$test_root/roms2"
export ROMS2_POWER_SUPPLY_ROOT="$test_root/power_supply"

source "$repo_dir/lib/common.sh"
source "$repo_dir/lib/transfer.sh"
ensure_runtime_dirs

assert_blocked() {
  if battery_allows_heavy_operation; then
    printf 'Expected battery guard to block: %s\n' "$1" >&2
    exit 1
  fi
}

assert_allowed() {
  if ! battery_allows_heavy_operation; then
    printf 'Expected battery guard to allow: %s (%s)\n' "$1" "$BATTERY_BLOCK_REASON" >&2
    exit 1
  fi
}

assert_allowed 'no battery reading'
[[ -n "$BATTERY_WARNING" ]]
mkdir -p "$ROMS2_POWER_SUPPLY_ROOT/ac" "$ROMS2_POWER_SUPPLY_ROOT/BAT0"
printf 'Mains\n' > "$ROMS2_POWER_SUPPLY_ROOT/ac/type"
printf 'Battery\n' > "$ROMS2_POWER_SUPPLY_ROOT/BAT0/type"
printf '20\n' > "$ROMS2_POWER_SUPPLY_ROOT/BAT0/capacity"
assert_blocked '20 percent'
printf '19\n' > "$ROMS2_POWER_SUPPLY_ROOT/BAT0/capacity"
assert_blocked '19 percent'
printf '21\n' > "$ROMS2_POWER_SUPPLY_ROOT/BAT0/capacity"
assert_allowed '21 percent'
[[ -z "$BATTERY_WARNING" ]]
printf 'invalid\n' > "$ROMS2_POWER_SUPPLY_ROOT/BAT0/capacity"
assert_allowed 'invalid reading'
[[ -n "$BATTERY_WARNING" ]]
printf '21\n' > "$ROMS2_POWER_SUPPLY_ROOT/BAT0/capacity"
mkdir -p "$ROMS2_POWER_SUPPLY_ROOT/BAT1"
printf 'Battery\n' > "$ROMS2_POWER_SUPPLY_ROOT/BAT1/type"
printf '20\n' > "$ROMS2_POWER_SUPPLY_ROOT/BAT1/capacity"
assert_blocked 'one of multiple batteries is low'
printf 'invalid\n' > "$ROMS2_POWER_SUPPLY_ROOT/BAT0/capacity"
assert_blocked 'low battery still blocks when another reading is invalid'

export ROMS2_DEMO=1
assert_allowed 'demo mode'
unset ROMS2_DEMO

# A direct game action must stop before resolving or touching its files.
printf '20\n' > "$ROMS2_POWER_SUPPLY_ROOT/BAT0/capacity"
resolve_game_group() { printf 'Unexpected game resolution\n' >&2; return 2; }
UI_BIN="dialog"
if delete_game_group 'psx/Test.chd'; then
  printf 'Expected direct deletion to be blocked\n' >&2
  exit 1
fi

printf 'battery-guard-tests-ok\n'
