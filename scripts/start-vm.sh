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
DISC_SHARE_TAG="riscosdiscs"
DISC_SHARE_DIR="$VM_DIR/disc-share"

usage() {
  cat <<USAGE
Usage: $0 [--disc /path/to/acorn-disc.hdf]

Options:
  --disc PATH   Share one Acorn/RISC OS hard disc image with the guest.
  -h, --help    Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disc)
      if [[ $# -lt 2 ]]; then
        printf '%s\n' '--disc requires a path.' >&2
        exit 2
      fi
      DISC_PATH="$2"
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

if [[ ! -f "$DISK" || ! -f "$SEED_ISO" ]]; then
  printf 'Missing VM files. Create them first:\n  %s/scripts/create-vm.sh\n' "$ROOT" >&2
  exit 1
fi

DISC_ARGS=()
if [[ -n "$DISC_PATH" ]]; then
  if [[ ! -f "$DISC_PATH" ]]; then
    printf 'Disc image not found: %s\n' "$DISC_PATH" >&2
    exit 1
  fi

  DISC_BASENAME="$(basename "$DISC_PATH")"
  rm -rf "$DISC_SHARE_DIR"
  mkdir -p "$DISC_SHARE_DIR"
  if ! ln "$DISC_PATH" "$DISC_SHARE_DIR/$DISC_BASENAME" 2>/dev/null; then
    printf 'Hard-linking the disc image failed; copying it into %s instead.\n' "$DISC_SHARE_DIR" >&2
    cp -p "$DISC_PATH" "$DISC_SHARE_DIR/$DISC_BASENAME"
  fi
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

if [[ -t 0 ]]; then
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
printf '%s\n\n' "$QUIT_HINT"

exec "$QEMU" \
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
