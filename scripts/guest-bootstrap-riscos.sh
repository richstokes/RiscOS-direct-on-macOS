#!/usr/bin/env bash
set -euo pipefail

DIRECT_URL="${DIRECT_URL:-https://www.riscosdev.com/wordpress/wp-content/uploads/2025/12/DirectPi5.tbz}"
ARCHIVE="${ARCHIVE:-$HOME/DirectPi5.tbz}"
DIRECT_DIR="$HOME/RISC_OS_Direct/RISC_OS_Linux_Binary"
EXTRACT_STAMP="${EXTRACT_STAMP:-$HOME/RISC_OS_Direct/.macos-vm-extract-complete}"
LOG_FILE="${LOG_FILE:-$HOME/riscos-direct-bootstrap.log}"
VNC_DISPLAY="${VNC_DISPLAY:-:1}"
VNC_GEOMETRY="${VNC_GEOMETRY:-1920x1080}"
VNC_PASSWORD="${VNC_PASSWORD:-riscos}"
DISC_SHARE_TAG="${DISC_SHARE_TAG:-riscosdiscs}"
DISC_SHARE_MOUNT="${DISC_SHARE_MOUNT:-/mnt/riscos-discs}"

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

direct_tree_complete() {
  [[ -s "$DIRECT_DIR/Built/sdl" ]] &&
    [[ -s "$DIRECT_DIR/Unix/LinuxSupport/common.mk" ]] &&
    [[ -s "$DIRECT_DIR/Unix/LinuxSupport/run_RISC_OS" ]] &&
    [[ -s "$DIRECT_DIR/Unix/RISCOS.IMG" ]] &&
    [[ -d "$DIRECT_DIR/hostfs/HardDisc4" ]]
}

extract_direct() {
  if [[ -f "$EXTRACT_STAMP" ]] && direct_tree_complete; then
    log "Using existing $DIRECT_DIR"
    return 0
  fi

  if direct_tree_complete; then
    log "Using existing $DIRECT_DIR and marking extraction complete"
    : > "$EXTRACT_STAMP"
    return 0
  fi

  if [[ -e "$HOME/RISC_OS_Direct" ]]; then
    log "Removing incomplete RISC_OS_Direct extraction"
    rm -rf "$HOME/RISC_OS_Direct"
  fi

  log "Extracting DirectPi5.tbz inside Linux so RISC OS xattrs and filenames survive"
  tar --xattrs -xjf "$ARCHIVE" -C "$HOME"

  if ! direct_tree_complete; then
    printf 'Direct archive extraction did not produce the expected RISC OS Direct tree.\n' >&2
    exit 1
  fi

  : > "$EXTRACT_STAMP"
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

sanitize_disc_name() {
  local name="$1"
  name="${name%.*}"
  name="${name//[^A-Za-z0-9_+-]/_}"
  name="${name:0:10}"
  if [[ -z "$name" ]]; then
    name="ImportedDisc"
  fi
  printf '%s\n' "$name"
}

mount_disc_share() {
  sudo modprobe 9pnet_virtio >/dev/null 2>&1 || true
  sudo mkdir -p "$DISC_SHARE_MOUNT"

  if ! mountpoint -q "$DISC_SHARE_MOUNT"; then
    sudo mount -t 9p -o trans=virtio,version=9p2000.L,ro,access=any "$DISC_SHARE_TAG" "$DISC_SHARE_MOUNT"
  fi
}

import_configured_discs() {
  local source name target tmp source_size source_mtime target_size target_mtime

  if ! mount_disc_share; then
    log "Could not mount QEMU disc share '$DISC_SHARE_TAG'"
    return 0
  fi

  cd "$DIRECT_DIR"
  mkdir -p HardDisc4/ImportedDiscs

  while IFS= read -r -d '' source; do
    name="$(sanitize_disc_name "$(basename "$source")")"
    target="HardDisc4/ImportedDiscs/$name,ffc"
    source_size="$(sudo stat -c '%s' "$source")"
    source_mtime="$(sudo stat -c '%Y' "$source")"
    target_size="$(stat -c '%s' "$target" 2>/dev/null || true)"
    target_mtime="$(stat -c '%Y' "$target" 2>/dev/null || true)"

    if [[ "$source_size" == "$target_size" && "$source_mtime" == "$target_mtime" ]]; then
      log "Using existing imported disc image $target"
      continue
    fi

    log "Importing disc image $(basename "$source") as $target"
    tmp="$target.tmp.$$"
    rm -f "$tmp"
    sudo cp -p "$source" "$tmp"
    sudo chown "$(id -u):$(id -g)" "$tmp"
    chmod 644 "$tmp"
    mv "$tmp" "$target"
  done < <(sudo find "$DISC_SHARE_MOUNT" -maxdepth 1 -type f -iname '*.hdf' -print0)
}

prepare() {
  exec > >(tee -a "$LOG_FILE") 2>&1
  install_deps
  download_direct
  extract_direct
  link_direct_layout
  import_configured_discs
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
export RISC_OS__GUI="${RISC_OS__GUI:-Built/sdl --swapmouse}"
export RISC_OS__INSECURE=YES
export SDL_VIDEO_WINDOW_POS=0,0
boot='/<IXFS$HardDisc4>.!Boot'
if [ "${RISCOS_AUTO_MOUNT_DISCS:-0}" = "1" ]; then
  for image in HardDisc4/ImportedDiscs/*,ffc; do
    [ -e "$image" ] || continue
    name="$(basename "$image" ',ffc')"
    boot="Echo Mounting imported disc $name
/<IXFS\$HardDisc4>.ImportedDiscs.$name
$boot"
  done
fi
export RISC_OS_Alias_IXFSBoot="$boot"
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
