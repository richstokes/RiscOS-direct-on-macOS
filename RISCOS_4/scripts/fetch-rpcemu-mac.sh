#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/downloads/rpcemu-src"
DEST="$ROOT/emulators/rpcemu-0.9.4a-mac"
ZIP="$OUT/RPCEmu-0.9.4a-Release.zip"
URL="https://github.com/Septercius/rpcemu-dev/releases/download/0.9.4a/RPCEmu-0.9.4a-Release.zip"

mkdir -p "$OUT" "$DEST"

if [[ ! -f "$ZIP" ]]; then
  echo "Downloading $URL"
  curl -L --fail --retry 3 --retry-delay 2 --show-error --output "$ZIP" "$URL"
fi

if [[ ! -d "$DEST/RPCEmu-Interpreter.app" ]]; then
  unzip -q "$ZIP" -d "$DEST"
fi

xattr -dr com.apple.quarantine "$DEST/RPCEmu-Interpreter.app" "$DEST/RPCEmu-Recompiler.app" 2>/dev/null || true

echo "$DEST/RPCEmu-Interpreter.app"
