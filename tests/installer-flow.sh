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
old_archive="$(list_local_packages | sed -n '2p')"
old_version="$(package_version_of "$old_archive")"
printf '' > "$test_root/events"
ANSWER=yes
MENU_CHOICE=choose
ZIP_CHOICE=1
main
rg -q "Selected: $old_version" "$test_root/events"
rg -q 'MESSAGE: ZIP verification' "$test_root/events"
[[ "$(rg -c '^STAGE:' "$test_root/events")" -eq 3 ]]

mkdir -p "$INSTALL_DIR/config"
printf 'KEEP_MY_CONFIG=1\n' > "$INSTALL_DIR/config/roms2.conf"
LOG_FILE="$test_root/extract.log"
prepare_files "$old_archive" > "$test_root/rollback-progress"
[[ "$(<"$INSTALL_DIR/VERSION")" == "$old_version" ]]
[[ "$(<"$INSTALL_DIR/config/roms2.conf")" == 'KEEP_MY_CONFIG=1' ]]
prepare_files "$test_archive" > "$test_root/progress"
[[ "$(<"$INSTALL_DIR/config/roms2.conf")" == 'KEEP_MY_CONFIG=1' ]]
[[ "$(<"$INSTALL_DIR/VERSION")" == "$test_version" ]]
rg -q '^100$' "$test_root/progress"

printf 'installer-flow-tests-ok\n'
