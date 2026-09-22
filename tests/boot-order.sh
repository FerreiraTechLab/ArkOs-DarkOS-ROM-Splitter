#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d /tmp/rom-splitter-boot-order.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT

app_dir="$test_root/app"
mkdir -p "$app_dir"
unzip -q "$repo_dir/dist/ROM-Splitter-1.0.0-rc19.zip" -d "$app_dir"
export ROMS_ROOT="$test_root/roms"
export ROMS2_SYSTEMD_DIR="$test_root/systemd"
export ROMS2_SYSTEM_TOOLS_DIR="$test_root/system-tools"
export ROM_SPLITTER_SKIP_OPTIONAL_DEPS=1
sudo() { "$@"; }
systemctl() { :; }
export -f sudo systemctl

bash "$app_dir/install.sh" > "$test_root/install-output"
service="$ROMS2_SYSTEMD_DIR/roms2-manager.service"
dropin="$ROMS2_SYSTEMD_DIR/emulationstation.service.d/rom-splitter.conf"
[[ -f "$service" && -f "$dropin" ]]
grep -q '^Before=emulationstation.service$' "$service"
grep -q '^After=roms2-manager.service$' "$dropin"
if grep -Eq '^(Requires|Wants)=roms2-manager.service$' "$dropin"; then
  printf 'EmulationStation must not require or restart the SD2 service\n' >&2
  exit 1
fi

bash "$app_dir/uninstall.sh" > "$test_root/uninstall-output"
[[ ! -e "$service" && ! -e "$dropin" ]]
printf 'boot-order-tests-ok\n'
