#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d /tmp/rom-splitter-installer-test.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT

source "$repo_dir/packaging/Install ROM Splitter.sh"
trap 'cleanup; rm -rf -- "$test_root"' EXIT
SCRIPT_DIR="$repo_dir/dist"
ROMS_DIR="$test_root/roms"
INSTALL_DIR="$ROMS_DIR/tools/.rom-splitter"
PERSISTENT_STATE_DIR="$ROMS_DIR/tools/.rom-splitter-state"
ROM_SPLITTER_INSTALL_LOG="$test_root/install.log"
test_archive="$(find "$SCRIPT_DIR" -maxdepth 1 -type f -name 'ROM-Splitter-*.zip' | sort -V | tail -n1)"
test_version="$(unzip -p "$test_archive" VERSION | tr -d '[:space:]')"
EXPECTED_SHA256="$(sha256sum "$test_archive" | awk '{print $1}')"
[[ "$(find_package)" == "$test_archive" ]]
EXPECTED_SHA256=deadbeef
if find_package >/dev/null; then
  printf 'Wrong checksum selected a package\n' >&2
  exit 1
fi
EXPECTED_SHA256="$(sha256sum "$test_archive" | awk '{print $1}')"

enter_console() { :; }
start_controls() { :; }
ui_msg() { printf 'MESSAGE: %s\n' "$1" >> "$test_root/events"; }
ui_menu() {
  case "$1" in
    'ROM Splitter installer') printf '%s\n' "$MENU_CHOICE" ;;
    'Choose ROM Splitter ZIP') printf '%s\n' "$ZIP_CHOICE" ;;
  esac
}
ui_yesno() {
  printf 'PROMPT: %s: %s\n' "$1" "$2" >> "$test_root/events"
  [[ "$ANSWER" == yes ]]
}
run_stage() { printf 'STAGE: %s\n' "$1" >> "$test_root/events"; }

ANSWER=yes
MENU_CHOICE=update
main
[[ "$(rg -c '^STAGE:' "$test_root/events")" -eq 3 ]]
rg -q "Installed: not installed.*Selected: $test_version" "$test_root/events"
rg -q 'MESSAGE: Installation complete' "$test_root/events"

mkdir -p "$INSTALL_DIR"
printf '%s\n' "$test_version" > "$INSTALL_DIR/VERSION"
printf '' > "$test_root/events"
ANSWER=no
main
rg -q 'PROMPT: Reinstall ROM Splitter' "$test_root/events"
if rg -q '^STAGE:' "$test_root/events"; then
  printf 'Cancelled reinstall unexpectedly started installation\n' >&2
  exit 1
fi

# Choosing an older local ZIP offers rollback instead of forcing the bundled ZIP.
old_archive="$SCRIPT_DIR/ROM-Splitter-1.0.0-rc16.zip"
old_version="$(package_version_of "$old_archive")"
printf '' > "$test_root/events"
ANSWER=yes
MENU_CHOICE=choose
ZIP_CHOICE=2
main
rg -q "Selected: $old_version" "$test_root/events"
rg -q 'MESSAGE: ZIP verification' "$test_root/events"
[[ "$(rg -c '^STAGE:' "$test_root/events")" -eq 3 ]]

mkdir -p "$INSTALL_DIR/config"
printf 'KEEP_MY_CONFIG=1\n' > "$INSTALL_DIR/config/roms2.conf"
mkdir -p "$PERSISTENT_STATE_DIR"
printf persistent > "$PERSISTENT_STATE_DIR/state-probe"
LOG_FILE="$test_root/extract.log"
prepare_files "$old_archive" > "$test_root/rollback-progress"
[[ "$(<"$INSTALL_DIR/VERSION")" == "$old_version" ]]
[[ "$(<"$INSTALL_DIR/config/roms2.conf")" == 'KEEP_MY_CONFIG=1' ]]
[[ "$(<"$INSTALL_DIR/state/state-probe")" == persistent ]]
printf legacy > "$INSTALL_DIR/state/state-probe"
prepare_files "$test_archive" > "$test_root/progress"
[[ "$(<"$INSTALL_DIR/config/roms2.conf")" == 'KEEP_MY_CONFIG=1' ]]
[[ "$(<"$INSTALL_DIR/VERSION")" == "$test_version" ]]
[[ "$(<"$PERSISTENT_STATE_DIR/state-probe")" == legacy ]]
rg -q '^100$' "$test_root/progress"

# uninstall_has_sd2_games only reports true while an active bind registry exists.
rm -f "$PERSISTENT_STATE_DIR/active-binds.tsv"
if uninstall_has_sd2_games; then
  printf 'uninstall_has_sd2_games should be false with no active binds\n' >&2
  exit 1
fi
mkdir -p "$PERSISTENT_STATE_DIR"
printf 'card1\tpsx/game.zip\tfile\n' > "$PERSISTENT_STATE_DIR/active-binds.tsv"
uninstall_has_sd2_games || { printf 'uninstall_has_sd2_games should be true with active binds\n' >&2; exit 1; }
rm -f "$PERSISTENT_STATE_DIR/active-binds.tsv"

# Cancelling the first uninstall confirmation removes nothing and leaves the
# installed app in place.
printf '' > "$test_root/events"
MENU_CHOICE=uninstall
ANSWER=no
main
rg -q 'PROMPT: Uninstall ROM Splitter' "$test_root/events"
if rg -q '^STAGE:' "$test_root/events"; then
  printf 'Cancelling uninstall unexpectedly started removal\n' >&2
  exit 1
fi
[[ -f "$INSTALL_DIR/VERSION" ]]

# Confirming uninstall runs both stages (deactivate SD2, then remove files)
# and shows the completion message. run_stage is stubbed here, same as the
# install assertions above, so this checks orchestration, not sudo-gated
# file removal.
printf '' > "$test_root/events"
ANSWER=yes
main
[[ "$(rg -c '^STAGE:' "$test_root/events")" -eq 2 ]]
rg -q 'MESSAGE: Uninstall complete' "$test_root/events"
if rg -q 'PROMPT: SD2 games will disconnect' "$test_root/events"; then
  printf 'Unexpected SD2 warning with no active binds\n' >&2
  exit 1
fi

# When games are actively bound from SD2, uninstalling shows the extra warning.
mkdir -p "$PERSISTENT_STATE_DIR"
printf 'card1\tpsx/game.zip\tfile\n' > "$PERSISTENT_STATE_DIR/active-binds.tsv"
printf '' > "$test_root/events"
main
rg -q 'PROMPT: Uninstall ROM Splitter' "$test_root/events"
rg -q 'PROMPT: SD2 games will disconnect' "$test_root/events"
[[ "$(rg -c '^STAGE:' "$test_root/events")" -eq 2 ]]
rm -f "$PERSISTENT_STATE_DIR/active-binds.tsv"

# Uninstall remains available when the folder contains no release ZIPs.
empty_packages="$test_root/no-zips"
mkdir -p "$empty_packages"
SCRIPT_DIR="$empty_packages"
printf '' > "$test_root/events"
main
rg -q 'PROMPT: Uninstall ROM Splitter' "$test_root/events"
[[ "$(rg -c '^STAGE:' "$test_root/events")" -eq 2 ]]
SCRIPT_DIR="$repo_dir/dist"

# The removal backend deletes the private app copy while leaving an unrelated
# ROM file untouched. sudo/systemctl are stubbed to keep this test unprivileged.
unrelated_rom="$ROMS_DIR/psx/Keep Me.chd"
mkdir -p "$(dirname "$unrelated_rom")" "$INSTALL_DIR"
printf game > "$unrelated_rom"
printf app > "$INSTALL_DIR/test-file"
mkdir -p "$PERSISTENT_STATE_DIR"
printf state > "$PERSISTENT_STATE_DIR/keep-state"
sudo() { "$@"; }
systemctl() { :; }
LOG_FILE="$test_root/remove.log"
remove_installed_files > "$test_root/remove-progress"
[[ ! -e "$INSTALL_DIR" ]]
[[ "$(<"$unrelated_rom")" == game ]]
[[ "$(<"$PERSISTENT_STATE_DIR/keep-state")" == state ]]

printf 'installer-flow-tests-ok\n'
