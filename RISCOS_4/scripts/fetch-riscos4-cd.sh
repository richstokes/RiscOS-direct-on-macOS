#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/downloads/archive-org/riscos-4-cdrev-3"
ISO="$OUT/RISCOS4CDREV3.iso"
URL="https://archive.org/download/riscos-4-cdrev-3/RISCOS4CDREV3.iso"

mkdir -p "$OUT"

if [[ ! -f "$ISO" ]]; then
  echo "Downloading $URL"
  curl -L --fail --retry 3 --retry-delay 2 --show-error --output "$ISO" "$URL"
fi

echo "$ISO"
shasum -a 256 "$ISO"
