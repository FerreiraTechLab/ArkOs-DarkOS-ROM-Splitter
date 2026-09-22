#!/usr/bin/env bash
set -Eeuo pipefail

CURRENT_SD2_UUID=""
SWITCH_BOUND=0
SWITCH_NEW_BINDS=0
SWITCH_CONFLICTS=0
SWITCH_MISSING=0

mounted_sd2_partition() {
  findmnt -n -o SOURCE "$ROMS2_ROOT" 2>/dev/null | sed 's/\[.*$//'
}

sd2_partition_uuid() {
  local part="$1"
  if [[ "${ROMS2_DEMO:-0}" == 1 ]]; then
    printf '%s\n' "${ROMS2_DEMO_UUID:-demo-card}"
  else
    blkid -s UUID -o value "$part" 2>/dev/null
  fi
}

safe_managed_placeholder() {
  local target="$1" kind="$2"
  case "$kind" in
    dir) [[ -d "$target" && ! -L "$target" ]] && [[ -z "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]] ;;
    file) [[ -f "$target" && ! -L "$target" && ! -s "$target" ]] ;;
    *) return 1 ;;
  esac
}

remove_managed_placeholder() {
  local rel="$1" kind="$2" target="$ROMS_ROOT/$rel"
  [[ -e "$target" || -L "$target" ]] || return 0
  if safe_managed_placeholder "$target" "$kind"; then
    if [[ "$kind" == dir ]]; then rmdir -- "$target"; else rm -f -- "$target"; fi
    log "Removed managed placeholder: $rel"
  else
    log "Preserved non-empty SD1 path while deactivating card: $rel"
    return 1
  fi
}

migrate_legacy_bind_registry() {
  local marker="$STATE_DIR/.bind-registry-v1" cache rel kind card_id target
  [[ -e "$marker" ]] && return 0
  mkdir -p "$STATE_DIR"
  cache="$(manifest_cache_file)"
  load_config
  card_id="${ROMS2_UUID:-legacy-card}"
  if [[ -f "$cache" ]]; then
    while IFS=$'\t' read -r rel kind; do
      validate_manifest_rel "$rel" || continue
      target="$ROMS_ROOT/$rel"
      if mountpoint -q "$target" 2>/dev/null || safe_managed_placeholder "$target" "$kind"; then
        active_bind_add "$card_id" "$rel" "$kind"
      fi
    done < "$cache"
  fi
  : > "$marker"
}

deactivate_recorded_binds() {
  local registry card_id rel kind target failures=0
  migrate_legacy_bind_registry
  registry="$(active_binds_file)"
  [[ -f "$registry" ]] || { clear_active_card_id; return 0; }

  while IFS=$'\t' read -r card_id rel kind; do
    [[ -n "$rel" ]] || continue
    target="$ROMS_ROOT/$rel"
    unbind_one "$target" || failures=$((failures+1))
    remove_managed_placeholder "$rel" "$kind" || failures=$((failures+1))
  done < "$registry"
  ((failures == 0)) || return 1
  : > "$registry"
  clear_active_card_id
}

mount_sd2() {
  if [[ "${ROMS2_DEMO:-0}" == 1 ]]; then
    mkdir -p "$ROMS2_ROOT"
    CURRENT_SD2_UUID="$(sd2_partition_uuid demo)"
    set_active_card_id "$CURRENT_SD2_UUID"
    sync_manifest_cache
    return 0
  fi
  local part uuid
  part="$(find_sd2_partition || true)"
  [[ -n "$part" ]] || fail "ROMS2 card not found."

  mkdir -p "$ROMS2_ROOT"
  if findmnt -rn "$ROMS2_ROOT" >/dev/null 2>&1; then
    local src
    src="$(findmnt -n -o SOURCE "$ROMS2_ROOT")"
    if [[ "$src" == "$part" ]]; then
      uuid="$(sd2_partition_uuid "$part" || true)"
      CURRENT_SD2_UUID="$uuid"
      [[ -n "$uuid" ]] && set_active_card_id "$uuid"
      sync_manifest_cache
      return 0
    fi
    fail "$ROMS2_ROOT is already mounted from $src"
  fi

  run_root mount -t exfat -o uid=1000,gid=1000,fmask=0000,dmask=0000,noatime "$part" "$ROMS2_ROOT"
  uuid="$(sd2_partition_uuid "$part" || true)"
  [[ -n "$uuid" ]] || { run_root umount "$ROMS2_ROOT"; fail "Mounted SD2 has no readable UUID."; return 1; }
  CURRENT_SD2_UUID="$uuid"
  set_active_card_id "$uuid"
  [[ -n "$uuid" ]] && save_config_value ROMS2_UUID "$uuid"
  save_config_value ROMS2_PARTITION "$part"
  sync_manifest_cache
  log "Mounted SD2 $part at $ROMS2_ROOT"
}

unbind_one() {
  local target="$1"
  if [[ "${ROMS2_DEMO:-0}" == 1 && -L "$target" ]]; then
    rm -f -- "$target"
    log "Demo bind removed $target"
    return 0
  fi
  if mountpoint -q "$target" 2>/dev/null; then
    run_root umount "$target"
    log "Unmounted bind $target"
  fi
}

unmount_all_binds() {
  deactivate_recorded_binds
}

unmount_sd2() {
  sync_manifest_cache
  unmount_all_binds || { fail "Could not safely deactivate every SD2 bind."; return 1; }
  [[ "${ROMS2_DEMO:-0}" == 1 ]] && { log "Demo SD2 unmounted"; return 0; }
  if findmnt -rn "$ROMS2_ROOT" >/dev/null 2>&1; then
    run_root umount "$ROMS2_ROOT"
    log "Unmounted SD2"
  fi
}

bind_item() {
  local source="$1" target="$2" rel="${3:-${2#"$ROMS_ROOT/"}}" card_id kind
  [[ -e "$source" ]] || return 1
  mkdir -p "$(dirname "$target")"
  kind=file; [[ -d "$source" ]] && kind=dir
  card_id="$(active_card_id || true)"
  [[ -n "$card_id" ]] || card_id="${CURRENT_SD2_UUID:-unknown-card}"

  if [[ "${ROMS2_DEMO:-0}" == 1 ]]; then
    if [[ -e "$target" || -L "$target" ]]; then
      active_bind_contains "$rel" || { fail "SD1 conflict blocks SD2 activation: $rel"; return 1; }
      rm -rf -- "$target"
    fi
    ln -s -- "$source" "$target"
    active_bind_add "$card_id" "$rel" "$kind"
    log "Demo bind $source -> $target"
    return 0
  fi

  if mountpoint -q "$target" 2>/dev/null; then
    active_bind_add "$card_id" "$rel" "$kind"
    return 0
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    if active_bind_contains "$rel" && safe_managed_placeholder "$target" "$kind"; then
      :
    else
      fail "SD1 conflict blocks SD2 activation: $rel"
      return 1
    fi
  fi

  # Record ownership before creating a placeholder. A power interruption
  # cannot leave a newly created target without a registry entry.
  active_bind_add "$card_id" "$rel" "$kind"
  if [[ -d "$source" ]]; then
    [[ -d "$target" ]] || { rm -f -- "$target" 2>/dev/null || true; mkdir -p "$target"; }
  else
    [[ -e "$target" ]] || : > "$target"
  fi

  run_root mount --bind "$source" "$target" || { fail "Bind mount failed: $rel"; return 1; }
  log "Bind mounted $source -> $target"
}

orphan_placeholder_candidates() {
  local manifest="$ROMS2_ROOT/.roms2-manifest.tsv" rel kind src dst
  [[ -f "$manifest" ]] || return 0
  while IFS=$'\t' read -r rel kind; do
    [[ -n "$rel" && "$rel" != \#* ]] || continue
    validate_manifest_rel "$rel" || continue
    [[ "$kind" == file || "$kind" == dir ]] || continue
    src="$ROMS2_ROOT/$rel"; dst="$ROMS_ROOT/$rel"
    [[ -e "$src" ]] || continue
    mountpoint -q "$dst" 2>/dev/null && continue
    active_bind_contains "$rel" && continue
    safe_managed_placeholder "$dst" "$kind" && printf '%s\0' "$rel"
  done < "$manifest"
}

recover_orphan_placeholders() {
  local backup_dir="$1" rel target
  local -a candidates=()
  mapfile -d '' -t candidates < <(orphan_placeholder_candidates)
  ((${#candidates[@]})) || return 0
  mkdir -p "$backup_dir"
  for rel in "${candidates[@]}"; do
    target="$ROMS_ROOT/$rel"
    # Recheck immediately before moving, and never touch a live bind or data.
    [[ -e "$ROMS2_ROOT/$rel" ]] || continue
    active_bind_contains "$rel" && continue
    mountpoint -q "$target" 2>/dev/null && continue
    if [[ -f "$target" && ! -L "$target" ]]; then
      safe_managed_placeholder "$target" file || continue
    elif [[ -d "$target" && ! -L "$target" ]]; then
      safe_managed_placeholder "$target" dir || continue
    else
      continue
    fi
    mkdir -p "$(dirname "$backup_dir/$rel")"
    [[ ! -e "$backup_dir/$rel" ]] || { fail "Recovery backup already contains: $rel"; return 1; }
    mv -- "$target" "$backup_dir/$rel"
    log "Backed up orphan placeholder: $rel to $backup_dir"
  done
}

rebuild_binds() {
  local progress_fd="${1:-}" total=0 processed=0
  mount_sd2 || return 1
  sync_manifest_cache
  local manifest="$ROMS2_ROOT/.roms2-manifest.tsv"
  local rel kind src dst already_bound
  SWITCH_BOUND=0
  SWITCH_NEW_BINDS=0
  SWITCH_CONFLICTS=0
  SWITCH_MISSING=0
  [[ -f "$manifest" ]] || { inventory_progress "$progress_fd" 70 "No SD2 manifest to rebuild."; return 0; }
  total="$(awk 'NF && $1 !~ /^#/ { count++ } END { print count+0 }' "$manifest")"

  while IFS=$'\t' read -r rel kind; do
    [[ -n "$rel" ]] || continue
    [[ "$rel" == \#* ]] && continue
    processed=$((processed+1))
    inventory_progress "$progress_fd" $((5 + processed * 65 / (total > 0 ? total : 1))) \
      "Rebuilding game links: $processed/$total"
    src="$ROMS2_ROOT/$rel"; dst="$ROMS_ROOT/$rel"
    if [[ ! -e "$src" ]]; then
      SWITCH_MISSING=$((SWITCH_MISSING+1))
      log "Missing manifest source: $src"
      continue
    fi
    already_bound=0
    if mountpoint -q "$dst" 2>/dev/null || { [[ "${ROMS2_DEMO:-0}" == 1 ]] && [[ -L "$dst" ]]; }; then
      already_bound=1
    fi
    if bind_item "$src" "$dst" "$rel"; then
      SWITCH_BOUND=$((SWITCH_BOUND+1))
      if ((already_bound == 0)); then SWITCH_NEW_BINDS=$((SWITCH_NEW_BINDS+1)); fi
    else
      SWITCH_CONFLICTS=$((SWITCH_CONFLICTS+1))
      log "Failed bind: $rel"
    fi
  done < "$manifest"
}

activate_inserted_sd2() {
  local previous_card new_card
  previous_card="$(active_card_id || true)"
  deactivate_recorded_binds || return 1
  mount_sd2 || return 1
  new_card="$(active_card_id || true)"
  rebuild_binds || return 1
  log "Activated SD2 profile: ${new_card:-unknown} (previous=${previous_card:-none}, bound=$SWITCH_BOUND, conflicts=$SWITCH_CONFLICTS, missing=$SWITCH_MISSING)"
}
