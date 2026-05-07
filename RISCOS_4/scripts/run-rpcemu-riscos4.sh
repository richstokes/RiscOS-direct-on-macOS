#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ROOT="$ROOT/emulators/rpcemu-0.9.4a-mac"
APP_BIN="$APP_ROOT/RPCEmu-Interpreter.app/Contents/MacOS/rpcemu-interpreter"
DRIVE0=""
DRIVE1=""
FLOPPY_MODE="copy"
HARD_DRIVE4=""
HARD_DRIVE5=""
HARD_DRIVE_MODE="link"
HARD_DRIVE_CACHE="$ROOT/run/rpcemu-riscos4/hard-drives"
WINDOW_POSITION="20,24"
PREPARE_ONLY="0"
PREP_ARGS=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Launch RISC OS 4 in RPCEmu. If floppy or hard drive images are supplied, they
are staged under RPCEmu's startup filenames before RISC OS boots.

Options:
  --floppy FILE, --floppy=FILE    Mount FILE as drive :0
  --floppy1 FILE, --floppy1=FILE  Mount FILE as drive :1
  --link-floppy                   Symlink images instead of copying them
  --hard-drive FILE               Mount FILE as ADFS hard drive :4
  --hard-drive=FILE               Mount FILE as ADFS hard drive :4
  --hard-drive5 FILE              Mount FILE as ADFS hard drive :5
  --hard-drive5=FILE              Mount FILE as ADFS hard drive :5
  --copy-hard-drive               Copy hard drive images instead of symlinking
  --game-compat                   Use monitor/display defaults friendlier to old games
  --monitor-type N                RISC OS monitor type for CMOS
  --wimp-mode N                   Fallback numeric WimpMode for CMOS
  --desktop-mode MODE             HostFS WimpMode string
  --no-hostfs-display-boot        Do not force the generated high-res desktop mode
  --model MODEL                   RPCEmu model name, e.g. RPC610, RPC710, A7000+
  --mouse-following 0|1           Enable/disable follow-host-mouse mode
  --no-follow-mouse               Disable follow-host-mouse mode
  --refresh-rate N                RPCEmu video refresh rate
  --stretch-mode 0|1              Enable/disable RPCEmu stretch mode
  --vram-size N                   RPCEmu VRAM config value, 0 or 2
  --window-position X,Y           Move the RPCEmu window after launch
  --no-window-position            Leave the RPCEmu window wherever Qt puts it
  --prepare-only                  Download and stage everything without launching RPCEmu
  -h, --help                      Show this help

Only .adf images are supported by this startup shortcut because RPCEmu 0.9.4a
autoloads fixed filenames named boot.adf and notboot.adf.
Hard drive images should be .hdf files. By default they are symlinked because
they are usually large and expected to be writable. FileCore hard drive images
whose embedded geometry does not match RPCEmu's Risc PC IDE expectations are
first copied to a persistent RPCEmu-compatible image under run/rpcemu-riscos4.
EOF
}

die() {
  echo "error: $*" >&2
  echo "Try: $(basename "$0") --help" >&2
  exit 1
}

need_value() {
  local opt="$1"
  local value="${2:-}"

  [[ -n "$value" ]] || die "$opt requires a file path"
  [[ "$value" != -* ]] || die "$opt requires a file path"
}

need_arg() {
  local opt="$1"
  local value="${2:-}"

  [[ -n "$value" ]] || die "$opt requires a value"
  [[ "$value" != -* ]] || die "$opt requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --floppy|--floppy0)
      need_value "$1" "${2:-}"
      DRIVE0="$2"
      shift 2
      ;;
    --floppy=*)
      DRIVE0="${1#*=}"
      [[ -n "$DRIVE0" ]] || die "--floppy requires a file path"
      shift
      ;;
    --floppy0=*)
      DRIVE0="${1#*=}"
      [[ -n "$DRIVE0" ]] || die "--floppy0 requires a file path"
      shift
      ;;
    --floppy1)
      need_value "$1" "${2:-}"
      DRIVE1="$2"
      shift 2
      ;;
    --floppy1=*)
      DRIVE1="${1#*=}"
      [[ -n "$DRIVE1" ]] || die "--floppy1 requires a file path"
      shift
      ;;
    --link-floppy)
      FLOPPY_MODE="link"
      shift
      ;;
    --hard-drive|--hard-drive4|--hdf)
      need_value "$1" "${2:-}"
      HARD_DRIVE4="$2"
      shift 2
      ;;
    --hard-drive=*|--hard-drive4=*|--hdf=*)
      HARD_DRIVE4="${1#*=}"
      [[ -n "$HARD_DRIVE4" ]] || die "${1%%=*} requires a file path"
      shift
      ;;
    --hard-drive5|--hdf5)
      need_value "$1" "${2:-}"
      HARD_DRIVE5="$2"
      shift 2
      ;;
    --hard-drive5=*|--hdf5=*)
      HARD_DRIVE5="${1#*=}"
      [[ -n "$HARD_DRIVE5" ]] || die "${1%%=*} requires a file path"
      shift
      ;;
    --copy-hard-drive)
      HARD_DRIVE_MODE="copy"
      shift
      ;;
    --game-compat)
      PREP_ARGS+=("$1")
      shift
      ;;
    --monitor-type|--wimp-mode|--desktop-mode|--model|--mouse-following|--refresh-rate|--stretch-mode|--vram-size)
      need_arg "$1" "${2:-}"
      PREP_ARGS+=("$1" "$2")
      shift 2
      ;;
    --monitor-type=*|--wimp-mode=*|--desktop-mode=*|--model=*|--mouse-following=*|--refresh-rate=*|--stretch-mode=*|--vram-size=*)
      [[ -n "${1#*=}" ]] || die "${1%%=*} requires a value"
      PREP_ARGS+=("$1")
      shift
      ;;
    --no-hostfs-display-boot)
      PREP_ARGS+=("$1")
      shift
      ;;
    --no-follow-mouse)
      PREP_ARGS+=("--mouse-following" "0")
      shift
      ;;
    --window-position)
      need_value "$1" "${2:-}"
      WINDOW_POSITION="$2"
      shift 2
      ;;
    --window-position=*)
      WINDOW_POSITION="${1#*=}"
      [[ -n "$WINDOW_POSITION" ]] || die "--window-position requires X,Y"
      shift
      ;;
    --no-window-position)
      WINDOW_POSITION=""
      shift
      ;;
    --prepare-only)
      PREPARE_ONLY="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      die "image paths must be supplied with --floppy or --hard-drive: $1"
      ;;
  esac
done

stage_floppy() {
  local drive_label="$1"
  local src="$2"
  local target="$3"

  [[ -f "$src" ]] || die "floppy image does not exist: $src"
  case "$src" in
    *.[Aa][Dd][Ff]) ;;
    *) die "startup floppy images must be .adf files: $src" ;;
  esac

  rm -f "$target"
  if [[ "$FLOPPY_MODE" == "link" ]]; then
    ln -s "$src" "$target"
    echo "Mounted $src as RPCEmu floppy drive $drive_label via symlink."
  else
    cp -f "$src" "$target"
    echo "Mounted $src as RPCEmu floppy drive $drive_label via a working copy."
  fi
}

position_rpcemu_window() {
  local app_pid="$1"
  local position="$2"
  local x="${position%,*}"
  local y="${position#*,}"

  [[ "$position" =~ ^[0-9]+,[0-9]+$ ]] || return 0
  command -v osascript >/dev/null 2>&1 || return 0

  for _ in {1..80}; do
    kill -0 "$app_pid" 2>/dev/null || return 0
    if osascript >/dev/null 2>&1 <<OSA
tell application "System Events"
  set matchingProcesses to every process whose unix id is $app_pid
  if (count of matchingProcesses) > 0 then
    tell item 1 of matchingProcesses
      if (count of windows) > 0 then
        set position of window 1 to {$x, $y}
        return "ok"
      end if
    end tell
  end if
end tell
error number -128
OSA
    then
      return 0
    fi
    sleep 0.25
  done
}

stage_hard_drive() {
  local drive_label="$1"
  local src="$2"
  local target="$3"
  local original_src=""
  local mounted_src="$src"

  [[ -f "$src" ]] || die "hard drive image does not exist: $src"
  case "$src" in
    *.[Hh][Dd][Ff]) ;;
    *) die "hard drive images must be .hdf files: $src" ;;
  esac

  original_src="$(cd "$(dirname "$src")" && pwd -P)/$(basename "$src")"
  mounted_src="$("$ROOT/scripts/normalize-rpcemu-hdf.py" "$original_src" --cache-dir "$HARD_DRIVE_CACHE")"

  rm -f "$target"
  if [[ "$HARD_DRIVE_MODE" == "copy" ]]; then
    cp -f "$mounted_src" "$target"
    echo "Mounted $mounted_src as RPCEmu hard drive $drive_label via a working copy."
  else
    ln -s "$mounted_src" "$target"
    if [[ "$mounted_src" == "$original_src" ]]; then
      echo "Mounted $original_src as RPCEmu hard drive $drive_label via symlink. Writes go to the original image."
    else
      echo "Mounted $mounted_src as RPCEmu hard drive $drive_label via symlink. Writes go to the compatible copy."
    fi
  fi
}

PREP_LOG="$(mktemp "${TMPDIR:-/tmp}/riscos4-prep.XXXXXX")"
"$ROOT/scripts/prepare-rpcemu-riscos4.sh" "${PREP_ARGS[@]}" | tee "$PREP_LOG"
DATA="$(tail -n 1 "$PREP_LOG")"
rm -f "$PREP_LOG"

if [[ ! -x "$APP_BIN" ]]; then
  echo "Missing RPCEmu interpreter: $APP_BIN" >&2
  exit 1
fi

rm -f "$DATA/boot.adf" "$DATA/notboot.adf" "$DATA/hd4.hdf" "$DATA/hd5.hdf"

if [[ -n "$DRIVE0" ]]; then
  stage_floppy ":0" "$DRIVE0" "$DATA/boot.adf"
fi

if [[ -n "$DRIVE1" ]]; then
  stage_floppy ":1" "$DRIVE1" "$DATA/notboot.adf"
fi

if [[ -n "$HARD_DRIVE4" ]]; then
  stage_hard_drive ":4" "$HARD_DRIVE4" "$DATA/hd4.hdf"
fi

if [[ -n "$HARD_DRIVE5" ]]; then
  stage_hard_drive ":5" "$HARD_DRIVE5" "$DATA/hd5.hdf"
fi

if [[ "$PREPARE_ONLY" == "1" ]]; then
  echo "Prepared RPCEmu RISC OS 4 data directory: $DATA"
  exit 0
fi

defaults write org.marutan.rpcemu-interpreter DataDirectory -string "$DATA/"
xattr -dr com.apple.quarantine "$APP_ROOT/RPCEmu-Interpreter.app" 2>/dev/null || true

cd "$DATA"
"$APP_BIN" &
APP_PID=$!

cleanup_rpcemu() {
  trap - INT TERM
  if kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  exit 130
}

trap cleanup_rpcemu INT TERM

if [[ -n "$WINDOW_POSITION" ]]; then
  position_rpcemu_window "$APP_PID" "$WINDOW_POSITION" &
  POSITION_PID=$!
fi

set +e
wait "$APP_PID"
APP_STATUS=$?
set -e

if [[ -n "${POSITION_PID:-}" ]]; then
  wait "$POSITION_PID" 2>/dev/null || true
fi

exit "$APP_STATUS"
