#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d /tmp/rom-splitter-rc15-upgrade.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT

source "$repo_dir/packaging/Install ROM Splitter.sh"
trap 'cleanup; rm -rf -- "$test_root"' EXIT
ROMS_DIR="$test_root/roms"
INSTALL_DIR="$ROMS_DIR/tools/.rom-splitter"
WORK_DIR="$(mktemp -d "$test_root/installer.XXXXXX")"
LOG_FILE="$test_root/install.log"
mkdir -p "$INSTALL_DIR"

unzip -q "$repo_dir/dist/ROM-Splitter-1.0.0-rc15.zip" -d "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/state/cards"
printf 'card-a\tpsx/game.chd\tfile\n' > "$INSTALL_DIR/state/active-binds.tsv"
printf 'card-a\n' > "$INSTALL_DIR/state/active-card"
printf 'psx/game.chd\tfile\n' > "$INSTALL_DIR/state/cards/card-a.manifest.tsv"
printf 'ROMS2_UUID=card-a\n' > "$INSTALL_DIR/config/roms2.conf"

prepare_files "$repo_dir/dist/ROM-Splitter-1.0.0-rc19.zip" > "$test_root/progress"
[[ "$(<"$INSTALL_DIR/VERSION")" == '1.0.0-rc19' ]]
[[ "$(<"$INSTALL_DIR/config/roms2.conf")" == 'ROMS2_UUID=card-a' ]]
[[ -f "$ROMS_DIR/tools/.rom-splitter-state/active-binds.tsv" ]]
cmp "$INSTALL_DIR/state/active-binds.tsv" "$ROMS_DIR/tools/.rom-splitter-state/active-binds.tsv"
cmp "$INSTALL_DIR/state/cards/card-a.manifest.tsv" "$ROMS_DIR/tools/.rom-splitter-state/cards/card-a.manifest.tsv"

(
  export ROMS_ROOT="$ROMS_DIR"
  export ROMS2_ROOT="$test_root/roms2"
  export ROMS2_BASE_DIR="$INSTALL_DIR"
  source "$INSTALL_DIR/lib/common.sh"
  source "$INSTALL_DIR/lib/games.sh"
  ensure_runtime_dirs
  [[ "$STATE_DIR" == "$ROMS_DIR/tools/.rom-splitter-state" ]]
  [[ ! -L "$INSTALL_DIR/state" ]]
  active_bind_contains 'psx/game.chd'
  [[ "$(active_card_id)" == 'card-a' ]]
)

printf 'upgrade-rc15-tests-ok\n'
