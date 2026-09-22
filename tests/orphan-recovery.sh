#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d /tmp/rom-splitter-orphan-test.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT

export ROMS_ROOT="$test_root/roms"
export ROMS2_ROOT="$test_root/roms2"
export ROMS2_BASE_DIR="$ROMS_ROOT/tools/.rom-splitter"
export ROMS2_DEMO=1
mkdir -p "$ROMS2_BASE_DIR/state" "$ROMS_ROOT/psx" "$ROMS_ROOT/ports" "$ROMS2_ROOT/psx" "$ROMS2_ROOT/ports"
printf 'demo-card\tpsx/old.chd\tfile\n' > "$ROMS2_BASE_DIR/state/active-binds.tsv"

source "$repo_dir/lib/common.sh"
source "$repo_dir/lib/games.sh"
source "$repo_dir/lib/mount.sh"
inventory_progress() { :; }
ensure_runtime_dirs
[[ "$STATE_DIR" == "$ROMS_ROOT/tools/.rom-splitter-state" ]]
[[ -s "$(active_binds_file)" ]]
[[ -d "$LEGACY_STATE_DIR" && ! -L "$LEGACY_STATE_DIR" ]]

printf 'game' > "$ROMS2_ROOT/psx/game.chd"
mkdir -p "$ROMS_ROOT/ports/empty" "$ROMS2_ROOT/ports/empty"
printf 'port' > "$ROMS2_ROOT/ports/empty/game.dat"
printf 'save' > "$ROMS2_ROOT/psx/save.srm"
printf 'sd1-save' > "$ROMS_ROOT/psx/save.srm"
: > "$ROMS_ROOT/psx/game.chd"
printf 'psx/game.chd\tfile\nports/empty\tdir\npsx/save.srm\tfile\n' > "$ROMS2_ROOT/.roms2-manifest.tsv"

mapfile -d '' -t candidates < <(orphan_placeholder_candidates)
[[ ${#candidates[@]} -eq 2 ]]
backup_dir="$test_root/backup"
recover_orphan_placeholders "$backup_dir"
[[ -f "$backup_dir/psx/game.chd" && -d "$backup_dir/ports/empty" ]]
[[ ! -e "$ROMS_ROOT/psx/game.chd" && ! -e "$ROMS_ROOT/ports/empty" ]]
[[ "$(<"$ROMS_ROOT/psx/save.srm")" == sd1-save ]]

rebuild_binds
[[ "$(<"$ROMS_ROOT/psx/game.chd")" == game ]]
[[ -L "$ROMS_ROOT/ports/empty" ]]
[[ "$(<"$ROMS_ROOT/psx/save.srm")" == sd1-save ]]
[[ "$SWITCH_CONFLICTS" -eq 1 ]]

# A failed real bind must retain an ownership record for its new placeholder.
printf 'other' > "$ROMS2_ROOT/psx/interrupted.chd"
ROMS2_DEMO=0
run_root() { return 1; }
if bind_item "$ROMS2_ROOT/psx/interrupted.chd" "$ROMS_ROOT/psx/interrupted.chd" 'psx/interrupted.chd'; then
  printf 'Unexpected successful bind\n' >&2
  exit 1
fi
[[ -f "$ROMS_ROOT/psx/interrupted.chd" && ! -s "$ROMS_ROOT/psx/interrupted.chd" ]]
active_bind_contains 'psx/interrupted.chd'

printf 'orphan-recovery-tests-ok\n'
