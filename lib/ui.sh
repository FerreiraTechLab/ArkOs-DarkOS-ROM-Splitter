#!/usr/bin/env bash
set -Eeuo pipefail

UI_BIN=""
if command -v dialog >/dev/null 2>&1; then UI_BIN="dialog"; elif command -v whiptail >/dev/null 2>&1; then UI_BIN="whiptail"; fi

UI_HEIGHT=10
UI_WIDTH=60
APP_VERSION="unknown"
if [[ -r "${ROMS2_BASE_DIR:-}/VERSION" ]]; then
  APP_VERSION="$(tr -d '[:space:]' < "$ROMS2_BASE_DIR/VERSION")"
fi
ES_RESTART_PENDING=0
APP_EXIT_REQUESTED=0

ui_size_for_text() {
  local text="$1" extra_rows="${2:-5}" min_height="${3:-8}" max_height="${4:-20}"
  local content_width=52 lines=0 line length
  # dialog renders literal \n sequences as line breaks; size for those rows.
  text="${text//\\n/$'\n'}"
  while IFS= read -r line || [[ -n "$line" ]]; do
    length=${#line}
    lines=$((lines + (length > 0 ? (length + content_width - 1) / content_width : 1)))
  done <<< "$text"
  UI_HEIGHT=$((lines + extra_rows))
  ((UI_HEIGHT < min_height)) && UI_HEIGHT=$min_height
  ((UI_HEIGHT > max_height)) && UI_HEIGHT=$max_height
  UI_WIDTH=60
  # Arithmetic tests return 1 when false; never leak that status to callers
  # because the application runs with set -e.
  return 0
}

ui_msg() {
  local title="$1" text="$2"
  if [[ -n "$UI_BIN" ]]; then
    local display_text
    display_text="$text\nA: OK"
    ui_size_for_text "$display_text" 3 7 14
    "$UI_BIN" --title "$title" --msgbox "$display_text" "$UI_HEIGHT" "$UI_WIDTH" || true
  else
    printf '\n[%s]\n%s\n' "$title" "$text"
  fi
}

ui_infobox() {
  local title="$1" text="$2"
  if [[ -n "$UI_BIN" ]]; then
    ui_size_for_text "$text" 3 6 12
    "$UI_BIN" --title "$title" --infobox "$text" "$UI_HEIGHT" "$UI_WIDTH" || true
  else
    printf '\n[%s]\n%s\n' "$title" "$text"
  fi
}

ui_yesno() {
  local title="$1" text="$2"
  if [[ -n "$UI_BIN" ]]; then
    local display_text
    display_text="$text\nA: Yes | B: No"
    ui_size_for_text "$display_text" 4 8 15
    "$UI_BIN" --title "$title" --yesno "$display_text" "$UI_HEIGHT" "$UI_WIDTH"
  else
    read -r -p "$text [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]]
  fi
}

ui_menu() {
  local title="$1" prompt="$2"; shift 2
  if [[ -n "$UI_BIN" ]]; then
    local item_count=$(( $# / 2 )) menu_height height width menu_prompt
    menu_height=$item_count
    ((menu_height > 8)) && menu_height=8
    # Menus do not use X/checklist controls, so keep their help on one compact
    # line and reserve the detailed help text for checklist screens.
    menu_prompt="$prompt\nD-Pad: Navigate | A: Confirm | B: Back"
    height=$((menu_height + 6))
    ((height < 9)) && height=9
    ((height > 22)) && height=22
    width=60
    "$UI_BIN" --clear --title "$title" --menu "$menu_prompt" "$height" "$width" "$menu_height" "$@" 3>&1 1>&2 2>&3
  else
    local args=("$@") i=0
    printf '\n%s\n%s\n' "$title" "$prompt" >&2
    while (( i < ${#args[@]} )); do printf '%s) %s\n' "${args[i]}" "${args[i+1]}" >&2; i=$((i+2)); done
    read -r -p '> ' choice || return 1
    printf '%s\n' "$choice"
  fi
}

ui_checklist() {
  local title="$1" prompt="$2"; shift 2
  if [[ -n "$UI_BIN" ]]; then
    local item_count=$(( $# / 3 )) list_height height
    list_height=$item_count
    ((list_height < 3)) && list_height=3
    ((list_height > 8)) && list_height=8
    height=$((list_height + 7))
    "$UI_BIN" --separate-output --title "$title" --checklist "$prompt\nD-Pad: Navigate | X: Select | A: Confirm | B: Back" "$height" 62 "$list_height" "$@" 3>&1 1>&2 2>&3
  else
    local args=("$@") i=0 answer token
    printf '\n%s\n%s\n' "$title" "$prompt" >&2
    while (( i < ${#args[@]} )); do
      printf '%s) %s\n' "${args[i]}" "${args[i+1]}" >&2
      i=$((i+3))
    done
    read -r -p 'Numbers separated by spaces: ' answer || return 1
    for token in $answer; do printf '%s\n' "$token"; done
  fi
}

ui_gauge() {
  local title="$1" prompt="$2"
  if [[ -n "$UI_BIN" ]]; then
    "$UI_BIN" --title "$title" --gauge "$prompt" 8 60 0
  else
    # Keep noninteractive/keyboard-only execution quiet while consuming input.
    while IFS= read -r _; do :; done
  fi
}

ui_backend_quiet() {
  "$@" >>"$LOG_FILE" 2>&1
}

schedule_emulationstation_restart() {
  local systemctl_bin unit
  systemctl_bin="$(command -v systemctl)" || return 1
  command -v systemd-run >/dev/null 2>&1 || return 1
  systemctl cat emulationstation.service >/dev/null 2>&1 || return 1
  unit="rom-splitter-es-restart-$(date +%s)-$BASHPID"
  run_root systemd-run --quiet --on-active=3s --unit="$unit" \
    "$systemctl_bin" restart emulationstation.service
  log "Scheduled EmulationStation restart: $unit"
}

offer_emulationstation_restart() {
  ((ES_RESTART_PENDING)) || return 0
  ui_yesno "Refresh game list" "Games changed. Restart EmulationStation now to refresh its game list?" || return 0
  if ui_backend_quiet schedule_emulationstation_restart; then
    ES_RESTART_PENDING=0
    APP_EXIT_REQUESTED=1
    ui_infobox "Restarting" "EmulationStation will restart shortly."
  else
    ui_msg "Restart unavailable" "Could not schedule the EmulationStation restart. Your changes are safe; try again when exiting."
  fi
  return 0
}

build_system_menu_cache() {
  local system="$1" output_file="$2" item loc size rel index=0 total
  local -a logical_items=()

  inventory_progress 3 2 "Scanning $system storage..."
  prepare_system_inventory_cache "$system"
  inventory_progress 3 10 "Reading game entries..."
  mapfile -t logical_items < <(list_logical_games_for_system "$system" 3)
  total=${#logical_items[@]}

  : > "$output_file"
  for item in "${logical_items[@]}"; do
    index=$((index+1))
    rel="$system/$item"
    loc="$(cached_group_location "$rel")"
    if [[ "$system" == ports ]]; then
      size="size calculated after selection"
    else
      size="$(human_size "$(cached_group_size "$rel" 2>/dev/null || echo 0)")"
    fi
    printf '%s\0%s\0%s\0' "$item" "$loc" "$size" >> "$output_file"
    inventory_progress 3 $((55 + index * 44 / (total > 0 ? total : 1))) \
      "Preparing game list: $index/$total"
  done
  inventory_progress 3 100 "Game list ready: $total game(s)"
}

show_storage_info() {
  local s1 s2
  s1="$(df -h "$ROMS_ROOT" | tail -n1 | awk '{print "SD1: " $3 " used / " $2 ", " $4 " free"}')"
  if findmnt -rn "$ROMS2_ROOT" >/dev/null 2>&1; then
    s2="$(df -h "$ROMS2_ROOT" | tail -n1 | awk '{print "SD2: " $3 " used / " $2 ", " $4 " free"}')"
  else
    s2="SD2: not mounted"
  fi
  ui_msg "Storage" "$s1\n$s2\n\n$(sd2_info 2>>"$LOG_FILE")"
}

choose_system() {
  local storage_filter="${1:-}" supplied_systems="${2:-}" opts=() s prompt="Choose a system"
  [[ -n "$storage_filter" ]] && prompt="Choose a system on $storage_filter"
  if [[ -n "$storage_filter" ]]; then
    if [[ -n "$supplied_systems" ]]; then
      while read -r s; do [[ -n "$s" ]] && opts+=("$s" "$s"); done <<< "$supplied_systems"
    else
      while read -r s; do [[ -n "$s" ]] && opts+=("$s" "$s"); done < <(systems_for_storage "$storage_filter" 2>>"$LOG_FILE")
    fi
  else
    while read -r s; do [[ -n "$s" ]] && opts+=("$s" "$s"); done < <(systems_from_es)
  fi
  ((${#opts[@]})) || return 1
  ui_menu "ROM Splitter" "$prompt" "${opts[@]}"
}

choose_storage() {
  ui_menu "Browse by storage" "Choose which card to view" \
    "SD1" "Primary ROM storage" \
    "SD2" "Secondary ROM storage"
}

location_matches_storage() {
  local location="$1" storage="$2"
  case "$storage:$location" in
    SD1:SD1|SD2:SD2|SD2:SD2-unmounted) return 0 ;;
    *) return 1 ;;
  esac
}

manage_system() {
  local system="$1" storage_filter="${2:-}" item loc size rel id selected_output scan_file scan_rc gauge_rc needs_refresh=1
  local -a scan_pipeline_status opts=() games=()
  while true; do
    if ((needs_refresh)); then
      opts=()
      games=()
      id=0
      scan_file="$(mktemp "$STATE_DIR/system-scan.XXXXXX")"
      set +e
      build_system_menu_cache "$system" "$scan_file" 3>&1 >>"$LOG_FILE" 2>&1 | ui_gauge "Scanning games" "Scanning $system..."
      scan_pipeline_status=("${PIPESTATUS[@]}")
      scan_rc=${scan_pipeline_status[0]:-1}
      gauge_rc=${scan_pipeline_status[1]:-1}
      set -e
      if ((scan_rc != 0 || gauge_rc != 0)); then
        rm -f -- "$scan_file"
        ui_msg "Scan error" "Could not scan games for $system. Check the log for details."
        return 0
      fi

      while IFS= read -r -d '' item && IFS= read -r -d '' loc && IFS= read -r -d '' size; do
        if [[ -n "$storage_filter" ]] && ! location_matches_storage "$loc" "$storage_filter"; then
          continue
        fi
        id=$((id+1))
        games[id]="$item"
        opts+=("$id" "$item | $loc | $size" "off")
      done < "$scan_file"
      rm -f -- "$scan_file"
      needs_refresh=0
    fi

    ((${#opts[@]})) || {
      ui_msg "ROM Splitter" "No items found in $system${storage_filter:+ on $storage_filter}."
      return
    }
    local -a selected=()
    if ! selected_output="$(ui_checklist "$system" "Select one or more games" "${opts[@]}")"; then
      # B/Escape returns to the system list.
      return 0
    fi
    mapfile -t selected <<< "$selected_output"
    if [[ -z "$selected_output" || ${#selected[@]} -eq 0 ]]; then
      ui_msg "Selection required" "Select at least one game with X before pressing A."
      continue
    fi

    local selected_id first_loc="" total=0 member_count=0 group_size group_members_count
    for selected_id in "${selected[@]}"; do
      item="${games[selected_id]:-}"
      [[ -n "$item" ]] || continue
      rel="$system/$item"
      loc="$(game_group_location "$rel")"
      [[ -z "$first_loc" ]] && first_loc="$loc"
      if [[ "$loc" != "$first_loc" ]]; then
        ui_msg "Selection" "Select games from only one storage location at a time."
        continue 2
      fi
      group_size="$(game_group_size "$rel")"
      group_members_count="$(resolve_game_group "$rel" | wc -l)"
      total=$((total + group_size))
      member_count=$((member_count + group_members_count))
    done

    local destination move_action chosen_action
    case "$first_loc" in
      SD1) destination="SD2"; move_action="move_group_to_sd2" ;;
      SD2|SD2-unmounted) destination="SD1"; move_action="move_group_to_sd1" ;;
      *) ui_msg "Error" "Unsupported selection state: $first_loc"; continue ;;
    esac

    chosen_action="$(ui_menu "Game action" \
      "${#selected[@]} game(s) selected | $member_count file(s)/item(s) | $(human_size "$total")" \
      "move" "Move to $destination" \
      "delete" "Permanently delete")" || continue

    case "$chosen_action" in
      move|delete)
        if ! battery_allows_heavy_operation; then
          ui_msg "Battery protection" "$BATTERY_BLOCK_REASON"
          continue
        fi
        if [[ -n "$BATTERY_WARNING" ]]; then ui_msg "Battery warning" "$BATTERY_WARNING"; fi
        ;;
      *) continue ;;
    esac

    local action result_title
    case "$chosen_action" in
      move)
        action="$move_action"
        result_title="Move result"
        ui_yesno "Confirm move" "Move ${#selected[@]} game(s) to $destination?\n\nTotal: $(human_size "$total")" || continue
        ;;
      delete)
        action="delete_game_group"
        result_title="Delete result"
        ui_yesno "PERMANENT DELETE" \
          "Permanently delete ${#selected[@]} game(s)?\n\n$member_count file(s)/item(s)\nTotal: $(human_size "$total")\n\nThis cannot be undone." || continue
        ;;
      *) continue ;;
    esac

    local completed=0 failed=0 battery_stopped=0 battery_warned=0 before_mutations=$GAME_LIBRARY_MUTATION_COUNT
    [[ -z "$BATTERY_WARNING" ]] || battery_warned=1
    for selected_id in "${selected[@]}"; do
      item="${games[selected_id]:-}"
      [[ -n "$item" ]] || continue
      if ! battery_allows_heavy_operation; then
        battery_stopped=1
        ui_msg "Battery protection" "$BATTERY_BLOCK_REASON\n\nRemaining games were not processed."
        break
      fi
      if [[ -n "$BATTERY_WARNING" ]] && ((battery_warned == 0)); then
        ui_msg "Battery warning" "$BATTERY_WARNING"
        battery_warned=1
      fi
      if "$action" "$system/$item"; then completed=$((completed+1)); else failed=$((failed+1)); fi
    done
    local result_note=""
    if ((battery_stopped)); then result_note="\nRemaining games skipped: low battery."; fi
    ui_msg "$result_title" "Completed: $completed\nFailed: $failed$result_note\n\nSee the log for details."
    if ((GAME_LIBRARY_MUTATION_COUNT > before_mutations)); then
      ES_RESTART_PENDING=1
      offer_emulationstation_restart
      ((APP_EXIT_REQUESTED == 0)) || return 0
    fi
    # A real storage mutation invalidates locations and item membership. Simple
    # navigation, empty selection and cancelled dialogs keep the current cache.
    needs_refresh=1
  done
}

manage_games() {
  ui_backend_quiet mount_sd2 || { ui_msg "SD2" "No configured ROMS2 card was found."; return 0; }
  local sys
  while sys="$(choose_system)"; do
    manage_system "$sys"
    ((APP_EXIT_REQUESTED == 0)) || return 0
  done
}

manage_games_by_storage() {
  local storage sys available_systems systems_file scan_rc gauge_rc
  local -a pipeline_status
  while storage="$(choose_storage)"; do
    if [[ "$storage" == SD2 ]] && ! ui_backend_quiet mount_sd2; then
      ui_msg "SD2" "No configured ROMS2 card was found."
      continue
    fi

    while true; do
      systems_file="$(mktemp "$STATE_DIR/storage-systems.XXXXXX")"
      set +e
      # Duplicate the pipeline into fd 3 first, then redirect normal output to
      # the cache file. Reversing this order mixes gauge protocol into systems.
      systems_for_storage "$storage" 3 3>&1 > "$systems_file" 2>>"$LOG_FILE" | \
        ui_gauge "Scanning $storage" "Looking for systems with games..."
      pipeline_status=("${PIPESTATUS[@]}")
      scan_rc=${pipeline_status[0]:-1}
      gauge_rc=${pipeline_status[1]:-1}
      set -e
      available_systems="$(<"$systems_file")"
      rm -f -- "$systems_file"

      if ((scan_rc != 0 || gauge_rc != 0)); then
        ui_msg "Browse by storage" "Could not scan systems on $storage. Check the log."
        break
      fi
      if [[ -z "$available_systems" ]]; then
        ui_msg "Browse by storage" "No managed games were found on $storage."
        break
      fi
      sys="$(choose_system "$storage" "$available_systems")" || break
      manage_system "$sys" "$storage"
      ((APP_EXIT_REQUESTED == 0)) || return 0
    done
  done
}

format_sd2_ui() {
  if [[ "${ROMS2_DEMO:-0}" == 1 ]]; then
    ui_msg "Demo mode" "Formatting is disabled in demo mode."
    return
  fi
  local opts=() dev size model chosen format_rc gauge_rc mounted_part mounted_dev mounted_uuid missing had_binds=0
  local -a pipeline_status
  while IFS='|' read -r dev size model; do opts+=("$dev" "$size $model"); done < <(list_candidate_sd2_devices 2>>"$LOG_FILE")
  ((${#opts[@]})) || { ui_msg "Prepare SD2" "No safe candidate device was detected."; return; }
  chosen="$(ui_menu "Prepare SD2" "Select the SECONDARY card. The selected device will be ERASED." "${opts[@]}")" || return 0
  validate_not_system_device "$chosen" || { ui_msg "Prepare SD2" "System/SD1 device cannot be formatted."; return; }
  missing="$(missing_format_tools)"
  if [[ -n "$missing" ]]; then
    ui_msg "Prepare SD2" "Formatting unavailable: missing $missing.\n\nNo game links were disconnected and the card was not modified."
    return 0
  fi
  mounted_part="$(mounted_sd2_partition || true)"
  mounted_dev=""
  if [[ -n "$mounted_part" ]]; then
    mounted_dev="$(lsblk -no PKNAME "$mounted_part" 2>/dev/null | head -n1)"
    [[ -n "$mounted_dev" ]] && mounted_dev="/dev/$mounted_dev"
  fi
  if [[ "$mounted_dev" == "$chosen" ]]; then
    [[ -s "$(active_binds_file)" ]] && had_binds=1
    mounted_uuid="$(sd2_partition_uuid "$mounted_part" || true)"
    [[ -n "$mounted_uuid" ]] || { ui_msg "Prepare SD2" "Could not identify the active SD2 card. Formatting blocked."; return; }
    ui_yesno "SD2 in use" "The selected card ($chosen, UUID $mounted_uuid) is the ACTIVE SD2 and contains games.\n\nContinuing will disconnect its game links, unmount it and PERMANENTLY ERASE ALL DATA on it.\n\nContinue?" || return 0
  elif lsblk -nrpo MOUNTPOINT "$chosen" | grep -q '^/'; then
    ui_msg "Prepare SD2" "The selected device has mounted partitions not managed as the active SD2. Formatting blocked."
    return
  fi
  ui_yesno "DANGER" "ALL DATA on $chosen will be erased.\n\nThe system disk and /roms disk are protected, but verify the device before continuing.\n\nFormat as exFAT and label ROMS2?" || return 0
  if ! battery_allows_heavy_operation; then
    ui_msg "Battery protection" "$BATTERY_BLOCK_REASON"
    return 0
  fi
  if [[ -n "$BATTERY_WARNING" ]]; then ui_msg "Battery warning" "$BATTERY_WARNING"; fi
  set +e
  {
    if [[ "$mounted_dev" == "$chosen" ]]; then
      inventory_progress 3 2 "Disconnecting active SD2 game links..."
      [[ "$(mounted_sd2_partition || true)" == "$mounted_part" ]] &&
        [[ "$(sd2_partition_uuid "$mounted_part" || true)" == "$mounted_uuid" ]] &&
        unmount_sd2 || { fail "Active SD2 changed or could not be safely unmounted. Formatting cancelled."; exit 1; }
    fi
    prepare_sd2_device "$chosen" 3 &&
      inventory_progress 3 92 "Mounting the prepared card..." &&
      mount_sd2 &&
      inventory_progress 3 100 "Card ready."
  } 3>&1 >>"$LOG_FILE" 2>&1 | ui_gauge "Prepare SD2" "Preparing the selected card..."
  pipeline_status=("${PIPESTATUS[@]}")
  format_rc=${pipeline_status[0]:-1}
  gauge_rc=${pipeline_status[1]:-1}
  set -e
  if ((had_binds)) && [[ ! -s "$(active_binds_file)" ]]; then
    ES_RESTART_PENDING=1
  fi
  if ((format_rc == 0 && gauge_rc == 0)); then
    ui_msg "Prepare SD2" "Card prepared successfully as ROMS2."
  else
    ui_msg "Error" "Formatting was cancelled or failed. The card may have been in use; check the log before retrying."
  fi
}

show_diagnostics() {
  ui_backend_quiet mount_sd2 || true
  local text=""
  battery_allows_heavy_operation || true
  text+="Battery: ${BATTERY_READING_DETAIL:-unavailable}\n"
  [[ -z "$BATTERY_BLOCK_REASON" ]] || text+="Battery protection: active (sensor at 22% or less)\n"
  [[ -z "$BATTERY_WARNING" ]] || text+="Battery protection: reading unavailable; warning only\n"
  text+="ROMS mount: $(findmnt -n -o SOURCE,FSTYPE "$ROMS_ROOT" 2>/dev/null || echo missing)\n"
  text+="ROMS2 mount: $(findmnt -n -o SOURCE,FSTYPE "$ROMS2_ROOT" 2>/dev/null || echo not-mounted)\n"
  text+="Configured SD2: $(sd2_info 2>>"$LOG_FILE")\n"
  text+="Active card profile: $(active_card_id 2>/dev/null || echo none)\n"
  text+="Known card profiles: $(known_card_profiles_count)\n"
  text+="Manifest entries: $(manifest_list 2>/dev/null | wc -l)\n"
  text+="Controls: ${CONTROLS_BACKEND:-keyboard}\n"
  ui_msg "Diagnostics" "$text"
}

scan_sd2_for_new_games() {
  local status_file import_rc gauge_rc total=0 added=0 conflicts=0 failed=0
  local -a pipeline_status
  if ! ui_backend_quiet mount_sd2; then
    ui_msg "Scan SD2" "No ROMS2 card is available. Insert or activate a card, then scan again."
    return 0
  fi
  status_file="$(mktemp "$STATE_DIR/sd2-scan-status.XXXXXX")"

  set +e
  import_new_sd2_items 3 "$status_file" 3>&1 >>"$LOG_FILE" 2>&1 | ui_gauge "Scanning SD2" "Looking for new games..."
  pipeline_status=("${PIPESTATUS[@]}")
  import_rc=${pipeline_status[0]:-1}
  gauge_rc=${pipeline_status[1]:-1}
  set -e

  if [[ -s "$status_file" ]]; then
    IFS=$'\t' read -r added conflicts failed total < "$status_file"
  fi
  rm -f -- "$status_file"
  if ((import_rc == 0 && gauge_rc == 0)); then
    ui_msg "Scan SD2" "New items linked: $added\nConflicts skipped: $conflicts\nFailures: $failed\n\nNew games are now available under /roms."
  else
    ui_msg "Scan SD2" "New items linked: $added\nConflicts skipped: $conflicts\nFailures: $failed\n\nCheck the log for failed items."
  fi
  if ((added > 0)); then
    ES_RESTART_PENDING=1
    offer_emulationstation_restart
  fi
  return 0
}

repair_storage_ui() {
  local repair_rc gauge_rc new_binds=0 status_file backup_dir=""
  local -a orphan_candidates=()
  local -a pipeline_status
  if ! ui_backend_quiet mount_sd2; then
    ui_msg "Repair" "No ROMS2 card is available. Insert or activate a card, then retry."
    return 0
  fi
  mapfile -d '' -t orphan_candidates < <(orphan_placeholder_candidates)
  if ((${#orphan_candidates[@]})); then
    if ui_yesno "Recover SD2 links" \
      "Found ${#orphan_candidates[@]} empty SD1 paths listed on SD2 but missing from the bind registry. They may be orphan placeholders.\n\nWith your approval, these empty paths will be backed up under /roms/tools, then SD2 links rebuilt. Non-empty SD1 files and folders will never be moved.\n\nRecover empty paths now?"; then
      backup_dir="$(mktemp -d "$ROMS_ROOT/tools/.rom-splitter-recovery.XXXXXX")"
      if ! ui_backend_quiet recover_orphan_placeholders "$backup_dir"; then
        ui_msg "Repair" "Could not back up all empty paths. Check the log before trying again. Backup: $backup_dir"
        return 0
      fi
    fi
  fi
  status_file="$(mktemp "$STATE_DIR/repair-status.XXXXXX")"
  set +e
  repair_storage 3 "$status_file" 3>&1 >>"$LOG_FILE" 2>&1 | ui_gauge "Repair SD2" "Rebuilding game links..."
  pipeline_status=("${PIPESTATUS[@]}")
  repair_rc=${pipeline_status[0]:-1}
  gauge_rc=${pipeline_status[1]:-1}
  set -e
  if [[ -s "$status_file" ]]; then read -r new_binds < "$status_file"; fi
  rm -f -- "$status_file"
  if ((new_binds > 0)); then ES_RESTART_PENDING=1; fi
  if ((repair_rc == 0 && gauge_rc == 0)); then
    ui_msg "Repair" "Bind mounts checked and rebuilt. Check the log for any conflicts.${backup_dir:+\n\nEmpty-path backup: $backup_dir}"
  else
    ui_msg "Repair" "Repair failed. Check the log for details."
  fi
  return 0
}

switch_sd2_ui() {
  local old_card new_card had_binds=0
  old_card="$(active_card_id || true)"
  [[ -s "$(active_binds_file)" ]] && had_binds=1

  if findmnt -rn "$ROMS2_ROOT" >/dev/null 2>&1 || [[ -n "$old_card" ]]; then
    if ! ui_backend_quiet unmount_sd2; then
      ui_msg "Switch SD2" "The current card could not be safely deactivated. Check the log and do not remove it."
      return 0
    fi
    if ((had_binds)); then ES_RESTART_PENDING=1; fi
  fi

  ui_yesno "Switch SD2" \
    "The previous SD2 is safely deactivated.\n\nRemove it, insert the desired ROMS2 card, then choose Yes to activate its profile.\n\nChoose No to leave SD2 disconnected." || return 0

  ui_infobox "Switch SD2" "Detecting the inserted card and rebuilding its game links..."
  if ui_backend_quiet activate_inserted_sd2; then
    new_card="$(active_card_id || true)"
    if ((SWITCH_NEW_BINDS > 0)); then ES_RESTART_PENDING=1; fi
    ui_msg "Switch SD2" \
      "Active card: ${new_card:-unknown}\nLinks created: $SWITCH_BOUND\nConflicts skipped: $SWITCH_CONFLICTS\nMissing items: $SWITCH_MISSING"
  else
    ui_msg "Switch SD2" "The inserted ROMS2 card could not be activated. No SD1 game was overwritten. Check the log."
    return 0
  fi
}

unmount_sd2_ui() {
  local had_binds=0
  [[ -s "$(active_binds_file)" ]] && had_binds=1
  if ui_backend_quiet unmount_sd2; then
    if ((had_binds)); then ES_RESTART_PENDING=1; fi
    ui_msg "SD2" "Unmounted safely."
  else
    ui_msg "SD2" "Unmount failed. Check the log."
  fi
  return 0
}

main_menu() {
  while true; do
    local choice
    if ! choice="$(ui_menu "ROM Splitter v$APP_VERSION" "ArkOS Dual Storage Manager" \
      "1" "Manage games" \
      "2" "Manage games by storage" \
      "3" "Storage information" \
      "4" "Prepare/format SD2" \
      "5" "Repair/rebuild bind mounts" \
      "6" "Activate/switch SD2 card" \
      "7" "Safely unmount SD2" \
      "8" "Diagnostics" \
      "9" "Scan SD2 for new games" \
      "0" "Exit")"; then
      # B/Escape at the root keeps the application open. Exit is explicit.
      continue
    fi

    case "$choice" in
      1) manage_games ;;
      2) manage_games_by_storage ;;
      3) show_storage_info ;;
      4) format_sd2_ui ;;
      5) repair_storage_ui ;;
      6) switch_sd2_ui ;;
      7) unmount_sd2_ui ;;
      8) show_diagnostics ;;
      9) scan_sd2_for_new_games ;;
      0)
        if ((ES_RESTART_PENDING)); then
          if ui_yesno "Refresh game list" "Games changed during this session. Restart EmulationStation before leaving?"; then
            if ui_backend_quiet schedule_emulationstation_restart; then
              ES_RESTART_PENDING=0
              ui_infobox "Restarting" "EmulationStation will restart shortly."
            else
              ui_msg "Restart unavailable" "Could not schedule the restart. Your changes are safe; try again or exit without restarting."
              continue
            fi
          fi
        fi
        break
        ;;
    esac
    ((APP_EXIT_REQUESTED == 0)) || break
  done
}
