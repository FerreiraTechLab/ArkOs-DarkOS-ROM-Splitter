#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROMS_DIR="${ROMS_ROOT:-/roms}"
TOOLS_DIR="$ROMS_DIR/tools"
TARGET="$TOOLS_DIR/ROM Splitter.sh"
SYSTEM_TARGET="${ROMS2_SYSTEM_TOOLS_DIR:-/opt/system/Tools}/ROM Splitter.sh"
SYSTEMD_DIR="${ROMS2_SYSTEMD_DIR:-/etc/systemd/system}"
SERVICE="$SYSTEMD_DIR/roms2-manager.service"
ES_DROPIN_DIR="$SYSTEMD_DIR/emulationstation.service.d"
ES_DROPIN="$ES_DROPIN_DIR/rom-splitter.conf"
LAUNCHER_TMP=""
SERVICE_TMP=""
ES_DROPIN_TMP=""
cleanup_install_tmp() {
  [[ -z "$LAUNCHER_TMP" ]] || rm -f -- "$LAUNCHER_TMP"
  [[ -z "$SERVICE_TMP" ]] || rm -f -- "$SERVICE_TMP"
  [[ -z "$ES_DROPIN_TMP" ]] || rm -f -- "$ES_DROPIN_TMP"
}
trap cleanup_install_tmp EXIT

chmod +x "$BASE_DIR/roms2-manager.sh" "$BASE_DIR/boot/roms2-mount.sh" "$BASE_DIR/install.sh"
find "$BASE_DIR/lib" -type f -name '*.sh' -exec chmod +x {} +

LAUNCHER_TMP="$(mktemp "${TMPDIR:-/tmp}/rom-splitter-launcher.XXXXXX")"
cat > "$LAUNCHER_TMP" <<EOF2
#!/usr/bin/env bash
set -uo pipefail
cd "$BASE_DIR"

# SSH and an interactive shell already provide a usable terminal.
if [[ -t 0 && -t 1 ]]; then
  export TERM="\${TERM:-linux}"
  exec "$BASE_DIR/roms2-manager.sh"
fi

# EmulationStation may launch custom Tools without a controlling TTY. Run the
# terminal UI on VT2, then switch back to the VT normally used by ES.
if command -v openvt >/dev/null 2>&1 && command -v chvt >/dev/null 2>&1; then
  sudo openvt -c 2 -s -f -w -- env TERM=linux "$BASE_DIR/roms2-manager.sh"
  rc=\$?
  sudo chvt 1 || true
  exit "\$rc"
fi

# Compatibility fallback for images without openvt/chvt.
export TERM=linux
exec "$BASE_DIR/roms2-manager.sh" </dev/tty1 >/dev/tty1 2>&1
EOF2
chmod +x "$LAUNCHER_TMP"
sudo mkdir -p "$TOOLS_DIR" "$(dirname "$SYSTEM_TARGET")"
sudo cp "$LAUNCHER_TMP" "$TARGET"
sudo cp "$LAUNCHER_TMP" "$SYSTEM_TARGET"

SERVICE_TMP="$(mktemp "${TMPDIR:-/tmp}/roms2-manager-service.XXXXXX")"
cat > "$SERVICE_TMP" <<EOF2
[Unit]
Description=ROM Splitter SD2 bind mount restoration
After=local-fs.target
Before=emulationstation.service
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=$BASE_DIR/boot/roms2-mount.sh
RemainAfterExit=no
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF2
sudo mkdir -p "$SYSTEMD_DIR"
sudo cp "$SERVICE_TMP" "$SERVICE"
ES_DROPIN_TMP="$(mktemp "${TMPDIR:-/tmp}/rom-splitter-es-order.XXXXXX")"
cat > "$ES_DROPIN_TMP" <<EOF2
[Unit]
# Wait for SD2 links when both services start at boot. This does not require
# an SD2 card and does not rerun the one-shot service on ES restarts.
After=roms2-manager.service
EOF2
sudo mkdir -p "$ES_DROPIN_DIR"
sudo cp "$ES_DROPIN_TMP" "$ES_DROPIN"
sudo systemctl daemon-reload
sudo systemctl enable roms2-manager.service

if [[ "${ROM_SPLITTER_SKIP_OPTIONAL_DEPS:-0}" != 1 ]]; then
  source "$BASE_DIR/lib/dependencies.sh"
  install_optional_format_tools
fi

echo "Installed. ROM launcher: $TARGET"
echo "System launcher: $SYSTEM_TARGET"
echo "Boot service: roms2-manager.service"
