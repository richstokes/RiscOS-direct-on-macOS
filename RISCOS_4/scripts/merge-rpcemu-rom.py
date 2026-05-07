#!/usr/bin/env python3
"""Merge split Acorn ROM chips into a single RPCEmu ROM image."""

from __future__ import annotations

import argparse
import hashlib
import zipfile
from pathlib import Path


BIOS_FILES = {
    "402": ("riscos402_1.bin", "riscos402_2.bin"),
    "439": ("riscos439_1.bin", "riscos439_2.bin"),
}


def merge_word2(chip0: bytes, chip1: bytes) -> bytes:
    if len(chip0) != len(chip1):
        raise ValueError(f"chip sizes differ: {len(chip0)} != {len(chip1)}")
    if len(chip0) % 2:
        raise ValueError("word-interleaved chips must have even lengths")

    merged = bytearray(len(chip0) + len(chip1))
    out = 0
    for offset in range(0, len(chip0), 2):
        merged[out : out + 2] = chip0[offset : offset + 2]
        merged[out + 2 : out + 4] = chip1[offset : offset + 2]
        out += 4
    return bytes(merged)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Merge split RISC OS ROM chips from an a7000p.zip set."
    )
    parser.add_argument("zipfile", type=Path, help="a7000p.zip ROM set")
    parser.add_argument(
        "--bios",
        choices=sorted(BIOS_FILES),
        default="402",
        help="RISC OS ROM version inside the zip",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    names = BIOS_FILES[args.bios]
    with zipfile.ZipFile(args.zipfile) as archive:
        chip0 = archive.read(names[0])
        chip1 = archive.read(names[1])

    merged = merge_word2(chip0, chip1)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(merged)

    sha1 = hashlib.sha1(merged).hexdigest()
    print(f"{args.output}: {len(merged)} bytes, sha1 {sha1}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
