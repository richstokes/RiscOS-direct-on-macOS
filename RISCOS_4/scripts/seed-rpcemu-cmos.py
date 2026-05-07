#!/usr/bin/env python3
"""Seed RPCEmu CMOS settings for a useful RISC OS 4 desktop."""

from __future__ import annotations

import argparse
from pathlib import Path


def cmos_offset(location: int) -> int:
    """Map a RISC OS CMOS location to its byte offset in RPCEmu's cmos.ram."""
    offset = location + 0x40
    if offset > 0xFF:
        offset -= 240
    return offset


def update_checksum(cmos: bytearray) -> None:
    checksum = 0
    for location in range(239):
        checksum += cmos[cmos_offset(location)]
    cmos[0x3F] = (checksum + 1) & 0xFF


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Patch an RPCEmu cmos.ram file with RISC OS display defaults."
    )
    parser.add_argument("cmos", type=Path, help="Path to RPCEmu cmos.ram")
    parser.add_argument(
        "--monitor-type",
        type=int,
        default=4,
        help="RISC OS monitor type to configure; 4 is Super-VGA",
    )
    parser.add_argument(
        "--wimp-mode",
        type=int,
        default=31,
        help="Fallback RISC OS WimpMode number; 31 is 800x600 with 16 colours",
    )
    parser.add_argument(
        "--hostfs-boot",
        action="store_true",
        help="Boot from RPCEmu HostFS so a generated !Boot file can set display modes",
    )
    args = parser.parse_args()

    cmos = bytearray(args.cmos.read_bytes())
    if len(cmos) != 256:
        raise SystemExit(f"{args.cmos}: expected 256 bytes, got {len(cmos)}")

    monitor_location = cmos_offset(133)
    cmos[monitor_location] = (cmos[monitor_location] & 0x83) | (
        (args.monitor_type & 0x1F) << 2
    )
    # Location 133 bit 1 disables LoadModeFile from !Boot when set.
    cmos[monitor_location] &= ~0x02

    # Location 195 bit 4 selects automatic mode handling when set. Clear it so
    # RISC OS uses the configured WimpMode byte at location 196.
    cmos[cmos_offset(195)] &= ~0x10
    cmos[cmos_offset(196)] = args.wimp_mode & 0xFF

    if args.hostfs_boot:
        cmos[cmos_offset(5)] = 0x99
        cmos[cmos_offset(16)] |= 0x10

    update_checksum(cmos)
    args.cmos.write_bytes(cmos)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
