#!/usr/bin/env bash
set -Eeuo pipefail
ROMS_DIR="${ROMS_ROOT:-/roms}"
SYSTEMD_DIR="${ROMS2_SYSTEMD_DIR:-/etc/systemd/system}"
sudo systemctl disable --now roms2-manager.service 2>/dev/null || true
sudo rm -f "$SYSTEMD_DIR/roms2-manager.service" "$SYSTEMD_DIR/emulationstation.service.d/rom-splitter.conf"
sudo rm -f "/opt/system/Tools/ROM Splitter.sh"
sudo rm -f "$ROMS_DIR/tools/ROM Splitter.sh"
sudo systemctl daemon-reload
echo "Launcher/service removed. ROM files and SD2 data were NOT deleted."
