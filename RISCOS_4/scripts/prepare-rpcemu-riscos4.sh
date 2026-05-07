#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ROOT="$ROOT/emulators/rpcemu-0.9.4a-mac"
APP_DATA="$APP_ROOT/Data"
DATA="$ROOT/run/rpcemu-riscos4/Data"
ISO="$ROOT/downloads/archive-org/riscos-4-cdrev-3/RISCOS4CDREV3.iso"
MODEL="RPC610"
MONITOR_TYPE="4"
WIMP_MODE="31"
DESKTOP_MODE="X1280 Y1024 C256 EX1 EY1"
HOSTFS_DISPLAY_BOOT="1"
MOUSE_FOLLOWING="1"
REFRESH_RATE="60"
STRETCH_MODE="1"
VRAM_SIZE="2"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Prepare RPCEmu's RISC OS 4 Data directory.

Options:
  --game-compat                  Use monitor/display defaults friendlier to old games
  --monitor-type N               RISC OS monitor type for CMOS
  --wimp-mode N                  Fallback numeric WimpMode for CMOS
  --desktop-mode MODE            HostFS WimpMode string
  --no-hostfs-display-boot       Do not load generated ModeInfo/WimpMode from HostFS
  --model MODEL                  RPCEmu model name, e.g. RPC610, RPC710, A7000+
  --mouse-following 0|1          Enable/disable RPCEmu follow-host-mouse mode
  --refresh-rate N               RPCEmu video refresh rate
  --stretch-mode 0|1             Enable/disable RPCEmu stretch mode
  --vram-size N                  RPCEmu VRAM config value, 0 or 2
  -h, --help                     Show this help
EOF
}

need_value() {
  local opt="$1"
  local value="${2:-}"

  [[ -n "$value" ]] || { echo "error: $opt requires a value" >&2; exit 1; }
  [[ "$value" != -* ]] || { echo "error: $opt requires a value" >&2; exit 1; }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --game-compat)
      MODEL="A7000+"
      MONITOR_TYPE="3"
      WIMP_MODE="28"
      DESKTOP_MODE="28"
      HOSTFS_DISPLAY_BOOT="minimal"
      MOUSE_FOLLOWING="0"
      VRAM_SIZE="0"
      shift
      ;;
    --monitor-type)
      need_value "$1" "${2:-}"
      MONITOR_TYPE="$2"
      shift 2
      ;;
    --monitor-type=*)
      MONITOR_TYPE="${1#*=}"
      [[ -n "$MONITOR_TYPE" ]] || { echo "error: --monitor-type requires a value" >&2; exit 1; }
      shift
      ;;
    --wimp-mode)
      need_value "$1" "${2:-}"
      WIMP_MODE="$2"
      shift 2
      ;;
    --wimp-mode=*)
      WIMP_MODE="${1#*=}"
      [[ -n "$WIMP_MODE" ]] || { echo "error: --wimp-mode requires a value" >&2; exit 1; }
      shift
      ;;
    --desktop-mode)
      need_value "$1" "${2:-}"
      DESKTOP_MODE="$2"
      HOSTFS_DISPLAY_BOOT="1"
      shift 2
      ;;
    --desktop-mode=*)
      DESKTOP_MODE="${1#*=}"
      [[ -n "$DESKTOP_MODE" ]] || { echo "error: --desktop-mode requires a value" >&2; exit 1; }
      HOSTFS_DISPLAY_BOOT="1"
      shift
      ;;
    --no-hostfs-display-boot)
      DESKTOP_MODE=""
      HOSTFS_DISPLAY_BOOT="0"
      shift
      ;;
    --model)
      need_value "$1" "${2:-}"
      MODEL="$2"
      shift 2
      ;;
    --model=*)
      MODEL="${1#*=}"
      [[ -n "$MODEL" ]] || { echo "error: --model requires a value" >&2; exit 1; }
      shift
      ;;
    --mouse-following)
      need_value "$1" "${2:-}"
      MOUSE_FOLLOWING="$2"
      shift 2
      ;;
    --mouse-following=*)
      MOUSE_FOLLOWING="${1#*=}"
      [[ -n "$MOUSE_FOLLOWING" ]] || { echo "error: --mouse-following requires a value" >&2; exit 1; }
      shift
      ;;
    --refresh-rate)
      need_value "$1" "${2:-}"
      REFRESH_RATE="$2"
      shift 2
      ;;
    --refresh-rate=*)
      REFRESH_RATE="${1#*=}"
      [[ -n "$REFRESH_RATE" ]] || { echo "error: --refresh-rate requires a value" >&2; exit 1; }
      shift
      ;;
    --stretch-mode)
      need_value "$1" "${2:-}"
      STRETCH_MODE="$2"
      shift 2
      ;;
    --stretch-mode=*)
      STRETCH_MODE="${1#*=}"
      [[ -n "$STRETCH_MODE" ]] || { echo "error: --stretch-mode requires a value" >&2; exit 1; }
      shift
      ;;
    --vram-size)
      need_value "$1" "${2:-}"
      VRAM_SIZE="$2"
      shift 2
      ;;
    --vram-size=*)
      VRAM_SIZE="${1#*=}"
      [[ -n "$VRAM_SIZE" ]] || { echo "error: --vram-size requires a value" >&2; exit 1; }
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$APP_DATA" || ! -d "$APP_ROOT/RPCEmu-Interpreter.app" ]]; then
  "$ROOT/scripts/fetch-rpcemu-mac.sh"
fi

if [[ ! -f "$ISO" ]]; then
  "$ROOT/scripts/fetch-riscos4-cd.sh"
fi

if [[ ! -f "$ROOT/roms/a7000p.zip" ]]; then
  "$ROOT/scripts/fetch-riscos4-roms.sh"
fi

mkdir -p "$DATA"
rsync -a --exclude 'roms/*' "$APP_DATA/" "$DATA/"
mkdir -p "$DATA/roms" "$DATA/hostfs" "$DATA/poduleroms" "$DATA/netroms"
rm -f "$DATA/roms/"*
cp "$APP_DATA/roms/roms.txt" "$DATA/roms/roms.txt"
"$ROOT/scripts/seed-rpcemu-cmos.py" \
  "$DATA/cmos.ram" \
  --monitor-type "$MONITOR_TYPE" \
  --wimp-mode "$WIMP_MODE" \
  --hostfs-boot

if [[ "$HOSTFS_DISPLAY_BOOT" == "1" ]]; then
  "$ROOT/scripts/write-rpcemu-display-boot.py" \
    "$DATA/hostfs" \
    --desktop-mode "$DESKTOP_MODE"
elif [[ "$HOSTFS_DISPLAY_BOOT" == "minimal" ]]; then
  rm -f "$DATA/hostfs/RPCEmuModes,fff"
  printf 'WimpMode %s\r' "$DESKTOP_MODE" > "$DATA/hostfs/!Boot,feb"
else
  rm -f "$DATA/hostfs/!Boot,feb" "$DATA/hostfs/RPCEmuModes,fff"
fi

"$ROOT/scripts/merge-rpcemu-rom.py" \
  "$ROOT/roms/a7000p.zip" \
  --bios 402 \
  --output "$DATA/roms/riscos402.rom"

cat > "$DATA/rpc.cfg" <<EOF
[General]
bridgename=rpcemu
cdrom_enabled=1
cdrom_iso=$ISO
cdrom_type=0
cpu_idle=0
ipaddress=172.31.0.1
macaddress=
mem_size=64
model=$MODEL
mouse_following=$MOUSE_FOLLOWING
mouse_twobutton=0
network_type=off
refresh_rate=$REFRESH_RATE
show_fullscreen_message=1
sound_enabled=1
stretch_mode=$STRETCH_MODE
username=
vram_size=$VRAM_SIZE
EOF

echo "$DATA"
