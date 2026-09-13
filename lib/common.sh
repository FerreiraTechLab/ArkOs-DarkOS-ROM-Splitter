#!/usr/bin/env bash
set -Eeuo pipefail

ROMS_ROOT="${ROMS_ROOT:-/roms}"
ROMS2_ROOT="${ROMS2_ROOT:-/roms2}"
CONFIG_DIR="${ROMS2_BASE_DIR}/config"
LOG_DIR="${ROMS2_BASE_DIR}/logs"
STATE_DIR="${ROMS2_BASE_DIR}/state"
CONFIG_FILE="$CONFIG_DIR/roms2.conf"
LOG_FILE="$LOG_DIR/roms2-manager.log"

log() {
  mkdir -p "$LOG_DIR"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

fail() {
  log "ERROR: $*"
  # Technical errors should not overwrite an active dialog screen. UI callers
  # report a user-facing message; non-UI callers still receive stderr.
  if [[ -z "${UI_BIN:-}" ]]; then
    printf '%s\n' "$*" >&2
  fi
  return 1
}

ensure_runtime_dirs() {
  mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$STATE_DIR" "$ROMS2_ROOT"
}

require_root_or_sudo() {
  command -v sudo >/dev/null 2>&1 || true
}

run_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

BATTERY_BLOCK_REASON=""
BATTERY_WARNING=""
BATTERY_READING_DETAIL=""
BATTERY_SENSOR_SAFETY_MARGIN=2

battery_allows_heavy_operation() {
  BATTERY_BLOCK_REASON=""
  BATTERY_WARNING=""
  BATTERY_READING_DETAIL=""
  [[ "${ROMS2_DEMO:-0}" != 1 ]] || return 0

  local supply type capacity found=0 unknown=0 root="${ROMS2_POWER_SUPPLY_ROOT:-/sys/class/power_supply}"
  local -a readings=()
  for supply in "$root"/*; do
    [[ -d "$supply" ]] || continue
    [[ -r "$supply/type" ]] || continue
    type=""
    IFS= read -r type < "$supply/type" || true
    [[ "$type" == Battery ]] || continue
    found=1
    if [[ ! -r "$supply/capacity" ]]; then
      unknown=1
      readings+=("${supply##*/}: unavailable")
      continue
    fi
    capacity=""
    IFS= read -r capacity < "$supply/capacity" || true
    if [[ ! "$capacity" =~ ^[0-9]+$ ]] || ((10#$capacity > 100)); then
      unknown=1
      readings+=("${supply##*/}: invalid")
      continue
    fi
    readings+=("${supply##*/}: $((10#$capacity))%")
    # On tested R36H, EmulationStation displayed 19% while the kernel sensor
    # still reported 21%. Keep a small margin around the displayed 20% limit.
    if ((10#$capacity <= 20 + BATTERY_SENSOR_SAFETY_MARGIN)); then
      BATTERY_READING_DETAIL="${readings[*]}"
      BATTERY_BLOCK_REASON="Battery sensor reads $((10#$capacity))% (20% limit with a 2-point safety margin). Charge a little more before moving, deleting or formatting."
      return 1
    fi
  done

  if ((found == 0 || unknown)); then
    BATTERY_WARNING="Battery level could not be verified. You can continue, but charge the console before moving, deleting or formatting."
  fi
  BATTERY_READING_DETAIL="${readings[*]:-unavailable}"
  return 0
}

human_size() {
  numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || printf '%s B' "$1"
}

file_size_bytes() {
  local p="$1"
  if [[ -d "$p" ]]; then
    du -sb -- "$p" | awk '{print $1}'
  else
    stat -c '%s' -- "$p"
  fi
}

safe_realpath() {
  realpath -m -- "$1"
}

is_under() {
  local child parent
  child="$(safe_realpath "$1")"
  parent="$(safe_realpath "$2")"
  [[ "$child" == "$parent" || "$child" == "$parent"/* ]]
}

load_config() {
  [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
}

save_config_value() {
  local key="$1" value="$2"
  touch "$CONFIG_FILE"
  if grep -q "^${key}=" "$CONFIG_FILE"; then
    sed -i "s|^${key}=.*|${key}=$(printf '%q' "$value")|" "$CONFIG_FILE"
  else
    printf '%s=%q\n' "$key" "$value" >> "$CONFIG_FILE"
  fi
}
