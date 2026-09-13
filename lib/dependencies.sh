#!/usr/bin/env bash
set -Eeuo pipefail

format_tools_os_id() {
  [[ -r /etc/os-release ]] || return 1
  ( . /etc/os-release; printf '%s\n' "${ID:-}" )
}

format_tool_available() {
  command -v "$1" >/dev/null 2>&1
}

apt_get_available() {
  command -v apt-get >/dev/null 2>&1
}

run_optional_apt_install() {
  local -a apt_cmd=()
  if ((EUID == 0)); then
    apt_cmd=(env DEBIAN_FRONTEND=noninteractive apt-get)
  else
    apt_cmd=(sudo -n env DEBIAN_FRONTEND=noninteractive apt-get)
  fi
  if command -v timeout >/dev/null 2>&1; then
    apt_cmd=(timeout 90s "${apt_cmd[@]}")
  fi
  "${apt_cmd[@]}" \
    -o Acquire::Retries=0 \
    -o Acquire::http::Timeout=15 \
    -o Acquire::https::Timeout=15 \
    install -y --no-install-recommends --no-remove "$@"
}

install_optional_format_tools() {
  local os_id
  local -a packages=()

  format_tool_available parted || packages+=(parted)
  format_tool_available mkfs.exfat || packages+=(exfatprogs)
  if ((${#packages[@]} == 0)); then
    printf 'SD2 formatting tools are available.\n'
    return 0
  fi

  os_id="$(format_tools_os_id || true)"
  if [[ "$os_id" == debian ]] && apt_get_available; then
    printf 'Installing optional SD2 formatting package(s): %s\n' "${packages[*]}"
    if ! run_optional_apt_install "${packages[@]}"; then
      printf 'WARNING: Optional formatting packages could not be installed. The ROM Splitter installation will continue.\n' >&2
    fi
  else
    printf 'WARNING: Automatic formatting-tool installation is supported only on Debian with apt-get.\n' >&2
  fi

  if ! format_tool_available parted || ! format_tool_available mkfs.exfat; then
    printf 'WARNING: ROM Splitter will work, but its SD2 formatting option is unavailable until parted and mkfs.exfat are installed.\n' >&2
  fi
  return 0
}
