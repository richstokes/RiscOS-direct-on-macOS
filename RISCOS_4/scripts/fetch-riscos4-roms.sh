#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/roms"
ZIP="$OUT/a7000p.zip"
URL="https://mdk.cab/download/split/a7000p.zip"

mkdir -p "$OUT"

cat <<'EOF'
This downloads the split RISC OS 4.02/4.39 ROM zip used by the RPCEmu
launcher. Only use it if your RISC OS license covers these ROM images.

The file is stored under roms/ and is ignored by this workspace.
EOF
echo

if [[ -f "$ZIP" ]]; then
  echo "Already have $ZIP"
else
  echo "Downloading $URL"
  curl -L --fail --retry 3 --retry-delay 2 --show-error --output "$ZIP" "$URL"
fi

echo
echo "ROM zip:"
shasum -a 1 "$ZIP"

echo
echo "RISC OS 4.02 chip hashes:"
unzip -p "$ZIP" riscos402_1.bin | shasum -a 1 | sed 's/-$/riscos402_1.bin/'
unzip -p "$ZIP" riscos402_2.bin | shasum -a 1 | sed 's/-$/riscos402_2.bin/'
