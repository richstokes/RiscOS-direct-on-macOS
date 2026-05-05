#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="$ROOT/vm"
DISK="$VM_DIR/riscos-ubuntu-arm64.qcow2"
SEED_ISO="$VM_DIR/seed.iso"

SSH_PORT="${SSH_PORT:-2222}"
VNC_PORT="${VNC_PORT:-5901}"
MEMORY="${MEMORY:-3072}"
SMP="${SMP:-4}"
DISC_PATH=""
FLOPPY_PATH=""
OPEN_VNC=1
DISC_SHARE_TAG="riscosdiscs"
DISC_SHARE_DIR="$VM_DIR/disc-share"

usage() {
  cat <<USAGE
Usage: $0 [--no-open-vnc] [--disc /path/to/acorn-disc.hdf] [--floppy /path/to/acorn-floppy.adf]

Options:
  --no-open-vnc  Stay attached to QEMU instead of opening macOS VNC.
  --disc PATH     Share one Acorn/RISC OS hard disc image with the guest.
  --floppy PATH   Share one Acorn/RISC OS floppy image with the guest.
  -h, --help      Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --open-vnc)
      OPEN_VNC=1
      shift
      ;;
    --no-open-vnc)
      OPEN_VNC=0
      shift
      ;;
    --disc)
      if [[ $# -lt 2 ]]; then
        printf '%s\n' '--disc requires a path.' >&2
        exit 2
      fi
      DISC_PATH="$2"
      shift 2
      ;;
    --floppy)
      if [[ $# -lt 2 ]]; then
        printf '%s\n' '--floppy requires a path.' >&2
        exit 2
      fi
      FLOPPY_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

find_qemu() {
  if command -v qemu-system-aarch64 >/dev/null 2>&1; then
    command -v qemu-system-aarch64
    return 0
  fi
  return 1
}

find_firmware_file() {
  local name="$1"
  local prefix

  if [[ -n "${QEMU_EFI_DIR:-}" && -f "$QEMU_EFI_DIR/$name" ]]; then
    printf '%s\n' "$QEMU_EFI_DIR/$name"
    return 0
  fi

  for prefix in \
    "$(brew --prefix qemu 2>/dev/null || true)" \
    /opt/homebrew \
    /usr/local \
    /Applications/UTM.app/Contents/Resources/qemu
  do
    [[ -n "$prefix" ]] || continue
    for candidate in "$prefix/share/qemu/$name" "$prefix/$name"; do
      if [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  done
  return 1
}

ensure_port_free() {
  local port="$1"
  local label="$2"

  if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
    printf '%s port 127.0.0.1:%s is already in use. Is the VM already running?\n' "$label" "$port" >&2
    exit 1
  fi
}

if [[ ! -f "$DISK" || ! -f "$SEED_ISO" ]]; then
  printf 'Missing VM files. Create them first:\n  %s/scripts/create-vm.sh\n' "$ROOT" >&2
  exit 1
fi

ensure_port_free "$SSH_PORT" "SSH"
ensure_port_free "$VNC_PORT" "VNC"

DISC_ARGS=()
stage_import_image() {
  local source="$1"
  local label="$2"
  local basename

  if [[ ! -f "$source" ]]; then
    printf '%s image not found: %s\n' "$label" "$source" >&2
    exit 1
  fi

  basename="$(basename "$source")"
  if ! ln "$source" "$DISC_SHARE_DIR/$basename" 2>/dev/null; then
    printf 'Hard-linking the %s image failed; copying it into %s instead.\n' "$label" "$DISC_SHARE_DIR" >&2
    cp -p "$source" "$DISC_SHARE_DIR/$basename"
  fi
}

if [[ -n "$DISC_PATH" || -n "$FLOPPY_PATH" ]]; then
  rm -rf "$DISC_SHARE_DIR"
  mkdir -p "$DISC_SHARE_DIR"
  [[ -z "$DISC_PATH" ]] || stage_import_image "$DISC_PATH" "Disc"
  [[ -z "$FLOPPY_PATH" ]] || stage_import_image "$FLOPPY_PATH" "Floppy"

  DISC_ARGS=(
    -fsdev "local,id=$DISC_SHARE_TAG,path=$DISC_SHARE_DIR,security_model=mapped-xattr,readonly=on"
    -device "virtio-9p-pci,fsdev=$DISC_SHARE_TAG,mount_tag=$DISC_SHARE_TAG"
  )
fi

QEMU="$(find_qemu || true)"
if [[ -z "$QEMU" ]]; then
  printf 'qemu-system-aarch64 was not found. Install QEMU first:\n  brew install qemu\n' >&2
  exit 1
fi

if [[ "$OPEN_VNC" -eq 1 ]] && ! command -v open >/dev/null 2>&1; then
  printf 'The --open-vnc option requires macOS open(1).\n' >&2
  exit 1
fi

EFI_CODE="$(find_firmware_file edk2-aarch64-code.fd || true)"
if [[ -z "$EFI_CODE" ]]; then
  printf 'Could not find EDK2 AArch64 firmware. With Homebrew QEMU this usually lives under $(brew --prefix qemu)/share/qemu.\n' >&2
  exit 1
fi

if [[ "$(uname -m)" == "arm64" ]]; then
  ACCEL="${ACCEL:-hvf}"
  CPU="${CPU:-host}"
else
  ACCEL="${ACCEL:-tcg}"
  CPU="${CPU:-max}"
  printf 'Warning: non-Apple-Silicon host detected; ARM64 emulation will be slow.\n' >&2
fi

if [[ "$OPEN_VNC" -eq 1 ]]; then
  SERIAL_LOG="${SERIAL_LOG:-$VM_DIR/serial.log}"
  : > "$SERIAL_LOG"
  SERIAL_ARGS=(-serial "file:$SERIAL_LOG" -monitor none)
  QUIT_HINT="Managed VNC mode is using serial log $SERIAL_LOG."
elif [[ -t 0 ]]; then
  SERIAL_ARGS=(-serial mon:stdio)
  QUIT_HINT='Quit QEMU from this terminal with Ctrl-A then X.'
else
  SERIAL_LOG="${SERIAL_LOG:-$VM_DIR/serial.log}"
  : > "$SERIAL_LOG"
  SERIAL_ARGS=(-serial "file:$SERIAL_LOG" -monitor none)
  QUIT_HINT="Serial console is logging to $SERIAL_LOG."
fi

printf 'Starting local QEMU VM. SSH: ssh -p %s ubuntu@localhost (password: ubuntu)\n' "$SSH_PORT"
printf 'When bootstrap finishes, open vnc://localhost:%s (password: riscos)\n' "$VNC_PORT"
if [[ -n "$DISC_PATH" ]]; then
  printf 'Sharing Acorn/RISC OS disc image: %s\n' "$DISC_PATH"
fi
if [[ -n "$FLOPPY_PATH" ]]; then
  printf 'Sharing Acorn/RISC OS floppy image: %s\n' "$FLOPPY_PATH"
fi
printf '%s\n\n' "$QUIT_HINT"

QEMU_ARGS=(
  -machine virt,highmem=off \
  -accel "$ACCEL" \
  -cpu "$CPU" \
  -smp "$SMP" \
  -m "$MEMORY" \
  -bios "$EFI_CODE" \
  -device virtio-blk-pci,drive=system,bootindex=0 \
  -drive "if=none,id=system,format=qcow2,file=$DISK,cache=writethrough" \
  -device virtio-blk-pci,drive=seed,bootindex=1 \
  -drive "if=none,id=seed,format=raw,media=cdrom,file=$SEED_ISO,readonly=on" \
  -device virtio-net-pci,netdev=net0 \
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22,hostfwd=tcp:127.0.0.1:$VNC_PORT-:5901" \
  "${DISC_ARGS[@]}" \
  "${SERIAL_ARGS[@]}" \
  -display none \
  -name riscos-direct
)

wait_for_vnc() {
  local banner
  local i

  for i in $(seq 1 240); do
    banner="$({ sleep 1; } | nc -w 2 127.0.0.1 "$VNC_PORT" 2>/dev/null | head -c 4 || true)"
    if [[ "$banner" == "RFB " ]]; then
      return 0
    fi
    sleep 2
  done

  return 1
}

if [[ "$OPEN_VNC" -ne 1 ]]; then
  exec "$QEMU" "${QEMU_ARGS[@]}"
fi

"$QEMU" "${QEMU_ARGS[@]}" &
QEMU_PID=$!
CLEANED_UP=0

cleanup_managed_vm() {
  if [[ "$CLEANED_UP" -eq 1 ]]; then
    return 0
  fi
  CLEANED_UP=1

  if kill -0 "$QEMU_PID" >/dev/null 2>&1; then
    printf 'Stopping VM...\n'
    "$ROOT/scripts/stop-vm.sh" >/dev/null 2>&1 || true

    for _ in $(seq 1 20); do
      if ! kill -0 "$QEMU_PID" >/dev/null 2>&1; then
        wait "$QEMU_PID" 2>/dev/null || true
        return 0
      fi
      sleep 1
    done

    printf 'VM did not stop gracefully; terminating QEMU process %s.\n' "$QEMU_PID" >&2
    kill "$QEMU_PID" >/dev/null 2>&1 || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}

trap cleanup_managed_vm EXIT INT TERM

printf 'Waiting for VNC server on localhost:%s...\n' "$VNC_PORT"
if ! wait_for_vnc; then
  printf 'Timed out waiting for VNC. Check %s for boot progress.\n' "$SERIAL_LOG" >&2
  exit 1
fi

printf 'Opening vnc://localhost:%s. Close the VNC viewer to stop the VM.\n' "$VNC_PORT"
open -W "vnc://localhost:$VNC_PORT"
