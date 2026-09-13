#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROMS_DIR="${ROMS_ROOT:-/roms}"
INSTALL_DIR="$ROMS_DIR/tools/.rom-splitter"
UNINSTALL_SENTINEL='__UNINSTALL__'
EXPECTED_SHA256=""
BUNDLED_VERSION=""
UI_BIN=""
CONTROLS_PID=""
WORK_DIR=""
LOG_FILE=""

cleanup() {
  if [[ -n "$CONTROLS_PID" ]]; then
    pkill -TERM -P "$CONTROLS_PID" 2>/dev/null || true
    kill "$CONTROLS_PID" 2>/dev/null || true
    wait "$CONTROLS_PID" 2>/dev/null || true
  fi
  [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

ui_msg() {
  local title="$1" message="$2"
  if [[ -n "$UI_BIN" ]]; then
    "$UI_BIN" --title "$title" --msgbox "$message" 10 60 || true
  else
    printf '\n[%s]\n%s\n' "$title" "$message"
    if [[ -t 0 ]]; then read -r -p 'Press Enter to continue... ' _; fi
  fi
}

ui_yesno() {
  local title="$1" message="$2" answer
  if [[ -n "$UI_BIN" ]]; then
    "$UI_BIN" --title "$title" --yesno "$message" 11 62
  else
    read -r -p "$message [y/N] " answer || return 1
    [[ "$answer" =~ ^[Yy]$ ]]
  fi
}

ui_menu() {
  local title="$1" message="$2"
  shift 2
  if [[ -n "$UI_BIN" ]]; then
    local rows=$(( $# / 2 )) height
    ((rows > 8)) && rows=8
    height=$((rows + 7))
    ((height < 10)) && height=10
    "$UI_BIN" --title "$title" --menu "$message" "$height" 64 "$rows" "$@" 3>&1 1>&2 2>&3
  else
    local -a options=("$@")
    local i choice
    printf '\n%s\n%s\n' "$title" "$message" >&2
    for ((i=0; i<${#options[@]}; i+=2)); do
      printf '%s) %s\n' "${options[i]}" "${options[i+1]}" >&2
    done
    read -r -p '> ' choice || return 1
    printf '%s\n' "$choice"
  fi
}

ui_gauge() {
  local title="$1" message="$2"
  if [[ -n "$UI_BIN" ]]; then
    "$UI_BIN" --title "$title" --gauge "$message" 8 60 0
  else
    while IFS= read -r _; do :; done
  fi
}

progress() {
  # A gauge may close when it reaches 100%. A closed UI pipe must not turn a
  # completed installation into a false backend failure.
  printf 'XXX\n%s\n%s\nXXX\n' "$1" "$2" 2>/dev/null || true
}

enter_console() {
  [[ -t 0 && -t 1 ]] && return 0
  if [[ "${ROM_SPLITTER_INSTALL_VT:-0}" != 1 ]] &&
     command -v openvt >/dev/null 2>&1 && command -v chvt >/dev/null 2>&1; then
    local rc=0
    sudo openvt -c 2 -s -f -w -- env TERM=linux ROMS_ROOT="$ROMS_DIR" ROM_SPLITTER_INSTALL_VT=1 \
      bash "$0" || rc=$?
    sudo chvt 1 || true
    exit "$rc"
  fi
  export TERM=linux
  exec bash "$0" </dev/tty1 >/dev/tty1 2>&1
}

start_controls() {
  [[ -t 0 && -t 1 ]] || return 0
  pgrep -f 'gptokeyb|oga_controls' >/dev/null 2>&1 && return 0

  local mapper="" candidate profile device
  for candidate in /opt/inttools/gptokeyb /opt/system/Tools/PortMaster/gptokeyb; do
    [[ -x "$candidate" ]] && { mapper="$candidate"; break; }
  done
  if [[ -n "$mapper" ]]; then
    printf '%s\n' \
      'back = esc' 'start = esc' 'a = enter' 'b = esc' 'x = space' \
      'up = up' 'down = down' 'left = left' 'right = right' \
      'left_analog_up = up' 'left_analog_down = down' \
      'left_analog_left = left' 'left_analog_right = right' \
      > "$WORK_DIR/installer.gptk"
    sudo chmod 666 /dev/uinput >>"$LOG_FILE" 2>&1 || true
    [[ ! -r /opt/inttools/gamecontrollerdb.txt ]] || \
      export SDL_GAMECONTROLLERCONFIG_FILE=/opt/inttools/gamecontrollerdb.txt
    "$mapper" -c "$WORK_DIR/installer.gptk" >>"$LOG_FILE" 2>&1 &
    CONTROLS_PID=$!
    sleep 0.2
    if kill -0 "$CONTROLS_PID" 2>/dev/null; then return 0; fi
    wait "$CONTROLS_PID" 2>/dev/null || true
    CONTROLS_PID=""
  fi

  mapper=""
  for candidate in /opt/quitter/oga_controls /opt/inttools/oga_controls \
                   /opt/system/Tools/PortMaster/oga_controls; do
    [[ -x "$candidate" ]] && { mapper="$candidate"; break; }
  done
  [[ -n "$mapper" ]] || return 0
  device="${ROMS2_OGA_PROFILE:-}"
  if [[ -z "$device" ]]; then
    for candidate in /home/ark/.config/.DEVICE /opt/system/.DEVICE /etc/device; do
      if [[ -r "$candidate" ]]; then
        device="$(tr -d '\r\n' < "$candidate")"
        [[ -n "$device" ]] && break
      fi
    done
  fi
  device="${device,,}"
  case "$device" in
    anbernic|chi|ogs|rk2020|oga) profile="$device" ;;
    *rg351*|*rg353*|*rg503*|*r35s*|*r36s*|*r36h*|*anbernic*) profile=anbernic ;;
    *gameforce*|*chi*) profile=chi ;;
    *odroid*super*|*ogs*) profile=ogs ;;
    *rk2020*) profile=rk2020 ;;
    *rgb10*|*odroid*advance*|*oga*) profile=oga ;;
    *) return 0 ;;
  esac
  printf '%s\n' \
    'back = esc' 'start = esc' 'a = enter' 'b = esc' 'x = space' \
    'up = up' 'down = down' 'left = left' 'right = right' \
    'left_analog_up = up' 'left_analog_down = down' \
    'left_analog_left = left' 'left_analog_right = right' \
    'deadzone_y = 2100' 'deadzone_x = 1900' \
    > "$WORK_DIR/oga_controls_settings.txt"
  (cd "$WORK_DIR" && "$mapper" roms2-manager.sh "$profile") >>"$LOG_FILE" 2>&1 &
  CONTROLS_PID=$!
}

find_package() {
  local candidate digest
  local -a packages=()
  for candidate in "$SCRIPT_DIR"/ROM-Splitter-*.zip "$SCRIPT_DIR"/ROM\ Splitter*.zip; do
    [[ -f "$candidate" ]] && packages+=("$candidate")
  done
  ((${#packages[@]})) || return 1

  if [[ -n "$EXPECTED_SHA256" ]]; then
    command -v sha256sum >/dev/null 2>&1 || return 2
    for candidate in "${packages[@]}"; do
      digest="$(sha256sum -- "$candidate" | awk '{print $1}')"
      [[ "$digest" == "$EXPECTED_SHA256" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 3
  fi

  printf '%s\n' "${packages[@]}" | sort -V | tail -n1
}

package_version_of() {
  local archive="$1" version
  version="$(unzip -p "$archive" VERSION 2>>"$LOG_FILE" | tr -d '[:space:]')" || return 1
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)?$ ]] || return 1
  [[ "${archive##*/}" == "ROM-Splitter-$version.zip" ]] || return 1
  printf '%s\n' "$version"
}

list_local_packages() {
  local archive
  for archive in "$SCRIPT_DIR"/ROM-Splitter-*.zip; do
    [[ -f "$archive" ]] && printf '%s\n' "$archive"
  done | sort -Vr
}

choose_local_zip() {
  local archive version choice index=0
  local -a archives=() options=()
  while IFS= read -r archive; do
    version="$(package_version_of "$archive" || true)"
    [[ -n "$version" ]] || continue
    archives+=("$archive")
    options+=("$index" "v$version")
    index=$((index+1))
  done < <(list_local_packages)
  ((${#archives[@]})) || { ui_msg 'No valid ZIPs' 'No valid ROM Splitter ZIP was found next to this installer.'; return 1; }
  choice="$(ui_menu 'Choose ROM Splitter ZIP' \
    'Select a version to install. A: Confirm | B: Back' "${options[@]}")" || return 1
  [[ "$choice" =~ ^[0-9]+$ ]] && ((choice < ${#archives[@]})) || return 1
  printf '%s\n' "${archives[choice]}"
}

choose_archive() {
  local bundled="$1" installed="$2" choice selected
  local -a options=()
  [[ -z "$bundled" ]] || options+=(update "Install bundled v$BUNDLED_VERSION")
  options+=(choose 'Choose another ZIP (rollback)')
  [[ "$installed" == 'not installed' ]] || options+=(uninstall 'Uninstall ROM Splitter')
  options+=(exit 'Exit installer')
  while true; do
    choice="$(ui_menu 'ROM Splitter installer' \
      "Installed: $installed\\nChoose an installation option.\\nA: Confirm | B: Exit" \
      "${options[@]}")" || return 1
    case "$choice" in
      update) [[ -z "$bundled" ]] || { printf '%s\n' "$bundled"; return 0; } ;;
      choose)
        selected="$(choose_local_zip)" || continue
        printf '%s\n' "$selected"
        return 0
        ;;
      uninstall) printf '%s\n' "$UNINSTALL_SENTINEL"; return 0 ;;
      exit) return 1 ;;
    esac
  done
}

prepare_files() {
  local archive="$1"
  progress 5 'Preparing application files...'
  mkdir -p "$INSTALL_DIR" 2>>"$LOG_FILE" || sudo mkdir -p "$INSTALL_DIR" >>"$LOG_FILE" 2>&1 || return 1
  if [[ ! -w "$INSTALL_DIR" ]]; then
    sudo chown "$(id -u):$(id -g)" "$INSTALL_DIR" >>"$LOG_FILE" 2>&1 || return 1
  fi
  if [[ -f "$INSTALL_DIR/config/roms2.conf" ]]; then
    cp -- "$INSTALL_DIR/config/roms2.conf" "$WORK_DIR/roms2.conf" >>"$LOG_FILE" 2>&1 || return 1
  fi
  progress 30 'Extracting ROM Splitter...'
  if ! unzip -q -o "$archive" -d "$INSTALL_DIR" >>"$LOG_FILE" 2>&1; then
    if [[ -f "$WORK_DIR/roms2.conf" ]]; then
      cp -- "$WORK_DIR/roms2.conf" "$INSTALL_DIR/config/roms2.conf" >>"$LOG_FILE" 2>&1 || true
    fi
    return 1
  fi
  if [[ -f "$WORK_DIR/roms2.conf" ]]; then
    cp -- "$WORK_DIR/roms2.conf" "$INSTALL_DIR/config/roms2.conf" >>"$LOG_FILE" 2>&1 || return 1
  fi
  [[ -f "$INSTALL_DIR/install.sh" && -f "$INSTALL_DIR/roms2-manager.sh" ]] || return 1
  chmod +x "$INSTALL_DIR/install.sh" "$INSTALL_DIR/uninstall.sh" \
    "$INSTALL_DIR/roms2-manager.sh" "$INSTALL_DIR/boot/roms2-mount.sh" >>"$LOG_FILE" 2>&1 || return 1
  find "$INSTALL_DIR/lib" -type f -name '*.sh' -exec chmod +x {} + >>"$LOG_FILE" 2>&1 || return 1
  progress 100 'Application files are ready.'
}

install_optional_dependencies() {
  progress 10 'Checking optional formatting tools...'
  (source "$INSTALL_DIR/lib/dependencies.sh"; install_optional_format_tools) >>"$LOG_FILE" 2>&1 || return 1
  progress 100 'Dependency check completed.'
}

finish_installation() {
  progress 20 'Creating Tools launchers...'
  ROM_SPLITTER_SKIP_OPTIONAL_DEPS=1 "$INSTALL_DIR/install.sh" >>"$LOG_FILE" 2>&1 || return 1
  progress 100 'ROM Splitter installed.'
}

# True when the installed app currently has games bind-mounted from SD2, so
# the caller can warn before that link is dropped.
uninstall_has_sd2_games() {
  [[ -f "$INSTALL_DIR/lib/common.sh" && -f "$INSTALL_DIR/lib/games.sh" ]] || return 1
  (
    export ROMS2_BASE_DIR="$INSTALL_DIR"
    source "$INSTALL_DIR/lib/common.sh"
    source "$INSTALL_DIR/lib/games.sh"
    [[ -s "$(active_binds_file)" ]]
  )
}

# Reuse the app's own safe-eject routine so SD2 games are cleanly detached
# (never deleted) before the app that restores them on boot is removed.
deactivate_before_uninstall() {
  progress 10 'Checking for active SD2 game links...'
  if [[ -f "$INSTALL_DIR/lib/common.sh" ]]; then
    (
      export ROMS2_BASE_DIR="$INSTALL_DIR"
      export ROMS_ROOT="$ROMS_DIR"
      source "$INSTALL_DIR/lib/common.sh"
      source "$INSTALL_DIR/lib/devices.sh"
      source "$INSTALL_DIR/lib/games.sh"
      source "$INSTALL_DIR/lib/mount.sh"
      ensure_runtime_dirs
      if findmnt -rn "$ROMS2_ROOT" >/dev/null 2>&1 || [[ -n "$(active_card_id || true)" ]]; then
        unmount_sd2
      fi
    ) >>"$LOG_FILE" 2>&1 || return 1
  fi
  progress 100 'SD2 game links are safe.'
}

# Removes only what the installer itself created: launchers, boot service and
# the private app copy. ROM/game files on SD1 and SD2 are never touched here.
remove_installed_files() {
  progress 15 'Disabling boot service...'
  sudo systemctl disable --now roms2-manager.service >>"$LOG_FILE" 2>&1 || true
  sudo rm -f /etc/systemd/system/roms2-manager.service >>"$LOG_FILE" 2>&1 || true
  sudo systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
  progress 45 'Removing Tools launchers...'
  sudo rm -f "/opt/system/Tools/ROM Splitter.sh" "$ROMS_DIR/tools/ROM Splitter.sh" >>"$LOG_FILE" 2>&1 || true
  progress 70 'Removing installed application files...'
  sudo rm -rf -- "$INSTALL_DIR" >>"$LOG_FILE" 2>&1 || return 1
  progress 100 'ROM Splitter removed.'
}

run_uninstall() {
  local installed="$1"
  ui_yesno 'Uninstall ROM Splitter' \
    "Installed: $installed\n\nRemoves the Tools launchers, the boot service and the app files at:\n$INSTALL_DIR\n\nAll ROM/game files on SD1 and SD2 stay untouched.\n\nContinue?\n\nA: Yes | B: Cancel" || return 0

  if uninstall_has_sd2_games; then
    ui_yesno 'SD2 games will disconnect' \
      "Games currently stored on SD2 will stop appearing in EmulationStation until ROM Splitter is reinstalled. No file on SD2 is deleted.\n\nUninstall now?\n\nA: Yes | B: Cancel" || return 0
  fi

  if ! run_stage 'Uninstalling ROM Splitter' 'Deactivating SD2 game links...' deactivate_before_uninstall; then
    ui_msg 'Uninstall failed' "SD2 could not be safely deactivated. Nothing was removed. Check the installation log: $LOG_FILE"
    return 1
  fi
  if ! run_stage 'Uninstalling ROM Splitter' 'Removing launchers, service and app files...' remove_installed_files; then
    ui_msg 'Uninstall failed' "Could not finish removing ROM Splitter. Check the installation log: $LOG_FILE"
    return 1
  fi
  ui_msg 'Uninstall complete' \
    "ROM Splitter was removed.\n\nAll ROM/game files on SD1 and SD2 were kept.\n\nRefresh or restart EmulationStation to update the Tools menu.\n\nA: OK"
}

run_stage() {
  local title="$1" message="$2" stage_rc gauge_rc
  shift 2
  local -a pipeline_status
  set +e
  "$@" | ui_gauge "$title" "$message"
  pipeline_status=("${PIPESTATUS[@]}")
  set -e
  stage_rc=${pipeline_status[0]:-1}
  gauge_rc=${pipeline_status[1]:-1}
  if ((gauge_rc != 0)); then
    printf 'Installer dialog exited with status %s during %s. Backend status: %s\n' \
      "$gauge_rc" "$title" "$stage_rc" >> "$LOG_FILE"
  fi
  ((stage_rc == 0))
}

main() {
  enter_console
  export TERM="${TERM:-linux}"
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rom-splitter-installer.XXXXXX")"
  LOG_FILE="${ROM_SPLITTER_INSTALL_LOG:-$SCRIPT_DIR/rom-splitter-install.log}"
  if ! touch "$LOG_FILE" 2>/dev/null; then LOG_FILE="$WORK_DIR/install.log"; fi
  if command -v dialog >/dev/null 2>&1; then UI_BIN=dialog
  elif command -v whiptail >/dev/null 2>&1; then UI_BIN=whiptail
  fi
  start_controls

  local archive bundled="" package_version installed_version="not installed" package_rc=0 digest
  if ! command -v unzip >/dev/null 2>&1; then
    ui_msg 'Installation error' 'The unzip command is required to install ROM Splitter.'
    return 1
  fi
  if [[ -z "$(list_local_packages)" ]]; then
    ui_msg 'Package not found' 'Copy at least one ROM Splitter ZIP next to this installer and try again.'
    return 1
  fi
  bundled="$(find_package)" || package_rc=$?
  if ((package_rc == 2)); then
    ui_msg 'Installation error' 'The sha256sum command is required to verify the bundled package.'
    return 1
  fi
  if [[ -n "$bundled" ]]; then
    BUNDLED_VERSION="$(package_version_of "$bundled" || true)"
  fi
  if [[ -r "$INSTALL_DIR/VERSION" ]]; then
    installed_version="$(tr -d '[:space:]' < "$INSTALL_DIR/VERSION")"
  fi
  archive="$(choose_archive "$bundled" "$installed_version")" || return 0
  if [[ "$archive" == "$UNINSTALL_SENTINEL" ]]; then
    run_uninstall "$installed_version"
    return $?
  fi
  package_version="$(package_version_of "$archive" || true)"
  if [[ -z "$package_version" ]] || ! unzip -tq "$archive" >>"$LOG_FILE" 2>&1; then
    ui_msg 'Invalid package' 'The selected ZIP is incomplete or its version does not match its filename.'
    return 1
  fi
  if [[ -n "$EXPECTED_SHA256" && "$package_version" == "$BUNDLED_VERSION" && "$archive" != "$bundled" ]]; then
    ui_msg 'Package mismatch' 'The bundled version does not match this installer checksum. Copy the matching ZIP again.'
    return 1
  fi
  if [[ "$archive" != "$bundled" ]]; then
    ui_msg 'ZIP verification' \
      'This ZIP passed its integrity check, but this installer has no matching checksum for it. Only continue if you trust its source.'
  elif [[ -n "$EXPECTED_SHA256" ]]; then
    digest="$(sha256sum -- "$archive" | awk '{print $1}')"
    [[ "$digest" == "$EXPECTED_SHA256" ]] || { ui_msg 'Package mismatch' 'ZIP checksum changed. Installation cancelled.'; return 1; }
  fi

  if [[ "$installed_version" == "$package_version" ]]; then
    ui_yesno 'Reinstall ROM Splitter' \
      "Version $package_version is already installed. Reinstall this ZIP?\n\nA: Yes | B: Cancel" || return 0
  else
    ui_yesno 'Install ROM Splitter' \
      "Installed: $installed_version\nSelected: $package_version\n\nInstall this version now?\n\nA: Yes | B: Cancel" || return 0
  fi

  if ! run_stage 'Installing ROM Splitter' 'Preparing application files...' prepare_files "$archive"; then
    ui_msg 'Installation failed' "Could not extract the application. Check the ZIP and installation log: $LOG_FILE"
    return 1
  fi
  if ! run_stage 'Checking dependencies' 'Checking optional formatting tools...' install_optional_dependencies; then
    ui_msg 'Dependency notice' 'The optional dependency check failed. Installation will continue, but SD2 formatting may be unavailable.'
  elif ! command -v parted >/dev/null 2>&1 || ! command -v mkfs.exfat >/dev/null 2>&1; then
    ui_msg 'Dependency notice' \
      'Could not install parted and/or exfatprogs (the console may be offline). ROM Splitter will still install; SD2 formatting needs these tools. Press A to continue.'
  fi
  if ! run_stage 'Installing ROM Splitter' 'Creating launchers and boot service...' finish_installation; then
    ui_msg 'Installation failed' "Could not finish installing ROM Splitter. Check the installation log: $LOG_FILE"
    return 1
  fi
  ui_msg 'Installation complete' \
    "ROM Splitter $package_version was installed successfully.\n\nRefresh or restart EmulationStation, then open Tools > ROM Splitter.\n\nA: OK"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
