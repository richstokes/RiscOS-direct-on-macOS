#!/usr/bin/env bash
set -euo pipefail

DIRECT_URL="${DIRECT_URL:-https://www.riscosdev.com/wordpress/wp-content/uploads/2025/12/DirectPi5.tbz}"
ARCHIVE="${ARCHIVE:-$HOME/DirectPi5.tbz}"
DIRECT_DIR="$HOME/RISC_OS_Direct/RISC_OS_Linux_Binary"
LOG_FILE="${LOG_FILE:-$HOME/riscos-direct-bootstrap.log}"
VNC_DISPLAY="${VNC_DISPLAY:-:1}"
VNC_GEOMETRY="${VNC_GEOMETRY:-1920x1080}"
VNC_PASSWORD="${VNC_PASSWORD:-riscos}"

DEBIAN_FRONTEND=noninteractive
export DEBIAN_FRONTEND

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

install_deps() {
  if ! command -v apt-get >/dev/null 2>&1; then
    return 0
  fi

  log "Installing Linux dependencies"
  sudo apt-get update
  sudo apt-get install -y \
    attr bash bubblewrap bzip2 ca-certificates curl dbus-x11 \
    freeglut3-dev g++ gcc libattr1-dev libglib2.0-dev libgl1 \
    libglu1-mesa libpixman-1-dev libseccomp-dev libsdl2-2.0-0 \
    libsdl2-dev make mesa-utils ninja-build openbox pkg-config \
    python3 tar tigervnc-common tigervnc-standalone-server x11-xserver-utils \
    xdotool xterm xz-utils zlib1g-dev

  # Direct's build scripts support either setuid bubblewrap or user namespaces.
  # Ubuntu 24.04 cloud images restrict unprivileged user namespaces by default.
  sudo chmod u+s "$(command -v bwrap)"
}

download_direct() {
  if [[ -f "$ARCHIVE" ]]; then
    log "Using existing $ARCHIVE"
    return 0
  fi

  log "Downloading RISC OS Direct archive"
  curl --fail --location --continue-at - --output "$ARCHIVE" "$DIRECT_URL"
}

extract_direct() {
  if [[ -d "$DIRECT_DIR" ]]; then
    log "Using existing $DIRECT_DIR"
    return 0
  fi

  log "Extracting DirectPi5.tbz inside Linux so RISC OS xattrs and filenames survive"
  tar --xattrs -xjf "$ARCHIVE" -C "$HOME"
}

link_direct_layout() {
  cd "$DIRECT_DIR"

  if [[ ! -e HardDisc4 && -d hostfs/HardDisc4 ]]; then
    log "Linking generic Linux launcher layout to Direct Pi 5 hostfs layout"
    ln -s hostfs/HardDisc4 HardDisc4
  fi

  if [[ ! -d HardDisc4 ]]; then
    printf 'HardDisc4 was not found. The Direct archive layout was not what this script expected.\n' >&2
    exit 1
  fi

  mkdir -p "$HOME/Downloads"
  : > "$HOME/Downloads/HardDisc4.5.28.util"
}

patch_direct_for_local_vm() {
  cd "$DIRECT_DIR"

  if ! grep -q -- "--unshare-all" Unix/LinuxSupport/common.mk Unix/LinuxSupport/run_RISC_OS; then
    return 0
  fi

  log "Patching Direct's bubblewrap profile for QEMU-in-QEMU local VM use"
  sed -i.bak \
    's/--unshare-all/--unshare-user-try --unshare-pid --unshare-ipc --unshare-uts/g' \
    Unix/LinuxSupport/common.mk \
    Unix/LinuxSupport/run_RISC_OS
}

build_patched_qemu() {
  cd "$DIRECT_DIR"
  log "Building/linking Direct's patched qemu-arm user emulator"

  if make -f Unix/LinuxSupport/common.mk Built/qemu-arm Built/qemu-link Built/wrapper Built/wait_stdin; then
    return 0
  fi

  log "Incremental qemu build failed; forcing a clean patched qemu-arm rebuild"
  rm -rf Built/qemu Built/qemu_files Built/qemu_stamp-v5.2.0 Built/qemu_Makefile_stamp Built/qemu-arm Built/qemu-link
  make -f Unix/LinuxSupport/common.mk Built/qemu-arm Built/qemu-link Built/wrapper Built/wait_stdin
}

prepare() {
  exec > >(tee -a "$LOG_FILE") 2>&1
  install_deps
  download_direct
  extract_direct
  link_direct_layout
  patch_direct_for_local_vm
  build_patched_qemu
  log "RISC OS Direct is prepared"
}

write_xstartup() {
  mkdir -p "$HOME/.vnc"
  printf '%s\n' "$VNC_PASSWORD" | vncpasswd -f > "$HOME/.vnc/passwd"
  chmod 600 "$HOME/.vnc/passwd"

  cat > "$HOME/.vnc/xstartup" <<'XSTARTUP'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
cd "$HOME/RISC_OS_Direct/RISC_OS_Linux_Binary" || exit 1
export RISC_OS__GUI=Built/sdl
export RISC_OS__INSECURE=YES
export SDL_VIDEO_WINDOW_POS=0,0
(
  i=0
  while [ "$i" -lt 200 ]; do
    win="$(xdotool search --name '^RISC OS$' 2>/dev/null | head -n 1 || true)"
    if [ -n "$win" ]; then
      xdotool windowmove "$win" 0 0
    fi
    i=$((i + 1))
    sleep 0.1
  done
) &
exec ./run_RISC_OS
XSTARTUP
  chmod +x "$HOME/.vnc/xstartup"
}

start_vnc() {
  exec > >(tee -a "$LOG_FILE") 2>&1
  prepare
  write_xstartup
  vncserver -kill "$VNC_DISPLAY" >/dev/null 2>&1 || true
  log "Starting VNC display $VNC_DISPLAY at ${VNC_GEOMETRY}"
  vncserver "$VNC_DISPLAY" -geometry "$VNC_GEOMETRY" -depth 24 -localhost no
  log "Connect from macOS to vnc://localhost:5901 with password '$VNC_PASSWORD'"
}

stop_vnc() {
  vncserver -kill "$VNC_DISPLAY" || true
}

status() {
  vncserver -list || true
  if [[ -f "$LOG_FILE" ]]; then
    tail -80 "$LOG_FILE"
  fi
}

case "${1:-prepare}" in
  prepare)
    prepare
    ;;
  start-vnc)
    start_vnc
    ;;
  restart-vnc)
    stop_vnc
    start_vnc
    ;;
  stop-vnc)
    stop_vnc
    ;;
  status)
    status
    ;;
  *)
    cat >&2 <<'USAGE'
Usage: riscos-direct [prepare|start-vnc|restart-vnc|stop-vnc|status]
USAGE
    exit 2
    ;;
esac
