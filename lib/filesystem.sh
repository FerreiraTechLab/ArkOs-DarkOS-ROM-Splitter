#!/usr/bin/env bash
set -Eeuo pipefail

missing_format_tools() {
  local tool
  local -a missing=()
  for tool in parted mkfs.exfat; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  printf '%s' "${missing[*]}"
}

prepare_sd2_device() {
  local dev="$1" progress_fd="${2:-}" missing
  [[ -b "$dev" ]] || { fail "Invalid block device: $dev"; return 1; }
  validate_not_system_device "$dev" || { fail "Refusing to format system/storage device: $dev"; return 1; }

  # The UI may deactivate the selected SD2 first, but formatting itself must
  # never silently unmount a disk or proceed while any partition is mounted.
  if lsblk -nrpo MOUNTPOINT "$dev" | grep -q '^/'; then
    fail "Refusing to format a device with mounted partitions: $dev"
    return 1
  fi

  missing="$(missing_format_tools)"
  [[ -z "$missing" ]] || { fail "Formatting requires missing tool(s): $missing"; return 1; }

  inventory_progress "$progress_fd" 5 "Creating the partition table..."
  run_root parted -s "$dev" mklabel gpt || return 1
  inventory_progress "$progress_fd" 25 "Creating the ROMS2 partition..."
  # Parted does not accept exfat as an fs-type. For GPT, use a partition
  # name plus fat32 to select the Microsoft basic-data GUID; mkfs.exfat
  # creates the actual exFAT filesystem in the following step.
  run_root parted -s "$dev" mkpart ROMS2 fat32 1MiB 100% || return 1
  run_root partprobe "$dev" || true
  inventory_progress "$progress_fd" 45 "Waiting for the new partition..."
  sleep 1

  local part
  if [[ "$dev" == /dev/mmcblk* || "$dev" == /dev/nvme* ]]; then
    part="${dev}p1"
  else
    part="${dev}1"
  fi
  [[ -b "$part" ]] || { sleep 2; [[ -b "$part" ]] || { fail "Partition was not created: $part"; return 1; }; }

  inventory_progress "$progress_fd" 55 "Formatting as exFAT. Do not remove the card..."
  run_root mkfs.exfat -n ROMS2 "$part" || return 1
  inventory_progress "$progress_fd" 85 "Reading the new card identifier..."
  local uuid
  uuid="$(blkid -s UUID -o value "$part" 2>/dev/null || true)"
  [[ -n "$uuid" ]] || { fail "Could not read UUID of formatted partition: $part"; return 1; }
  save_config_value ROMS2_UUID "$uuid" || return 1
  save_config_value ROMS2_PARTITION "$part" || return 1
  log "Prepared SD2 device $dev ($part, UUID=$uuid)"
}
