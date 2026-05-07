#!/usr/bin/env python3
"""Create an RPCEmu-friendly copy of a RISC OS FileCore hard disc image."""

from __future__ import annotations

import argparse
import hashlib
import mmap
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path


BOOT_BLOCK_OFFSET = 0xC00
BOOT_HARDWARE_OFFSET = 0x1BA
BOOT_DISC_RECORD_OFFSET = 0x1C0
BOOT_CHECKSUM_OFFSET = 0x1FF
DISC_RECORD_SIZE = 60
RPCEMU_SECTORS_PER_TRACK = 63
RPCEMU_HEADS = 16


@dataclass(frozen=True)
class DiscRecord:
    log2_sector_size: int
    sectors_per_track: int
    heads: int
    idlen: int
    log2_bytes_per_map_bit: int
    nzones: int
    raw: bytes

    @property
    def sector_size(self) -> int:
        return 1 << self.log2_sector_size


@dataclass(frozen=True)
class HDFInfo:
    path: Path
    supported: bool
    compatible: bool
    record: DiscRecord | None
    map_starts: tuple[int, ...]
    reason: str = ""


def adc_checksum(data: bytes | bytearray, check_index: int) -> int:
    total = 0
    carry = 0
    for offset in range(check_index - 1, -1, -1):
        total = total + data[offset] + carry
        if total > 0xFF:
            carry = 1
            total &= 0xFF
        else:
            carry = 0
    return total & 0xFF


def map_zone_check(block: bytes | bytearray, sector_size: int) -> int:
    sum0 = sum1 = sum2 = sum3 = 0
    for rover in range(sector_size - 4, 0, -4):
        sum0 += block[rover] + (sum3 >> 8)
        sum3 &= 0xFF
        sum1 += block[rover + 1] + (sum0 >> 8)
        sum0 &= 0xFF
        sum2 += block[rover + 2] + (sum1 >> 8)
        sum1 &= 0xFF
        sum3 += block[rover + 3] + (sum2 >> 8)
        sum2 &= 0xFF

    sum0 += sum3 >> 8
    sum1 += block[1] + (sum0 >> 8)
    sum2 += block[2] + (sum1 >> 8)
    sum3 += block[3] + (sum2 >> 8)
    return (sum0 ^ sum1 ^ sum2 ^ sum3) & 0xFF


def read_disc_record(data: mmap.mmap, offset: int) -> DiscRecord | None:
    if offset + DISC_RECORD_SIZE > len(data):
        return None

    raw = bytes(data[offset : offset + DISC_RECORD_SIZE])
    log2_sector_size = raw[0]
    if log2_sector_size < 8 or log2_sector_size > 12:
        return None

    return DiscRecord(
        log2_sector_size=log2_sector_size,
        sectors_per_track=raw[1],
        heads=raw[2],
        idlen=raw[4],
        log2_bytes_per_map_bit=raw[5],
        nzones=raw[9],
        raw=raw,
    )


def valid_map(data: mmap.mmap, start: int, sector_size: int, nzones: int) -> bool:
    end = start + sector_size * nzones
    if start < 0 or end > len(data):
        return False

    cross_check = 0
    for zone in range(nzones):
        block_start = start + zone * sector_size
        block = data[block_start : block_start + sector_size]
        if block[0] != map_zone_check(block, sector_size):
            return False
        cross_check ^= block[3]

    return cross_check == 0xFF


def find_map_starts(data: mmap.mmap, record: DiscRecord) -> tuple[int, ...]:
    # The map copy of the disc record can differ from the boot-block copy in
    # private/flag bytes. Search on the stable geometry prefix and let the map
    # checksum/cross-check validation prove that the hit is real.
    pattern = record.raw[:7]
    starts: list[int] = []
    position = data.find(pattern)
    while position != -1:
        start = position - 4
        if start >= 0 and start % record.sector_size == 0:
            if valid_map(data, start, record.sector_size, record.nzones):
                starts.append(start)
        position = data.find(pattern, position + 1)
    return tuple(starts)


def analyze(path: Path) -> HDFInfo:
    if path.stat().st_size < BOOT_BLOCK_OFFSET + 512:
        return HDFInfo(path, False, False, None, (), "image is too small")

    with path.open("rb") as handle:
        with mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ) as data:
            boot = data[BOOT_BLOCK_OFFSET : BOOT_BLOCK_OFFSET + 512]
            if adc_checksum(boot, BOOT_CHECKSUM_OFFSET) != boot[BOOT_CHECKSUM_OFFSET]:
                return HDFInfo(path, False, False, None, (), "boot block checksum is invalid")

            record = read_disc_record(
                data, BOOT_BLOCK_OFFSET + BOOT_DISC_RECORD_OFFSET
            )
            if record is None:
                return HDFInfo(path, False, False, None, (), "no FileCore disc record found")
            if record.sector_size != 512:
                return HDFInfo(
                    path,
                    False,
                    False,
                    record,
                    (),
                    f"unsupported sector size: {record.sector_size}",
                )
            if not record.nzones:
                return HDFInfo(path, False, False, record, (), "map has zero zones")

            map_starts = find_map_starts(data, record)
            if not map_starts:
                return HDFInfo(path, False, False, record, (), "FileCore map was not found")

            compatible = (
                record.sectors_per_track == RPCEMU_SECTORS_PER_TRACK
                and record.heads == RPCEMU_HEADS
                and boot[BOOT_HARDWARE_OFFSET] == 0
            )
            for start in map_starts:
                map_record = read_disc_record(data, start + 4)
                compatible = compatible and map_record is not None
                compatible = compatible and (
                    map_record.sectors_per_track == RPCEMU_SECTORS_PER_TRACK
                    and map_record.heads == RPCEMU_HEADS
                )

            return HDFInfo(path, True, compatible, record, map_starts)


def cache_path(source: Path, cache_dir: Path) -> Path:
    resolved = str(source.expanduser().resolve())
    digest = hashlib.sha1(resolved.encode("utf-8")).hexdigest()[:12]
    suffix = source.suffix if source.suffix else ".hdf"
    return cache_dir / f"{source.stem}-{digest}.rpcemu63x16{suffix}"


def patch_copy(source: Path, output: Path, info: HDFInfo) -> None:
    assert info.record is not None

    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, output)

    with output.open("r+b") as handle:
        with mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_WRITE) as data:
            boot_start = BOOT_BLOCK_OFFSET
            boot_end = boot_start + info.record.sector_size
            boot = bytearray(data[boot_start:boot_end])
            record_start = BOOT_DISC_RECORD_OFFSET
            boot[record_start + 1] = RPCEMU_SECTORS_PER_TRACK
            boot[record_start + 2] = RPCEMU_HEADS
            boot[BOOT_HARDWARE_OFFSET] = 0
            boot[BOOT_CHECKSUM_OFFSET] = adc_checksum(boot, BOOT_CHECKSUM_OFFSET)
            data[boot_start:boot_end] = boot

            for map_start in info.map_starts:
                block_end = map_start + info.record.sector_size
                block = bytearray(data[map_start:block_end])
                block[4 + 1] = RPCEMU_SECTORS_PER_TRACK
                block[4 + 2] = RPCEMU_HEADS
                block[0] = map_zone_check(block, info.record.sector_size)
                data[map_start:block_end] = block

            data.flush()


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Create a persistent 63-sector/16-head RPCEmu-compatible copy of "
            "a RISC OS FileCore HDF when its embedded geometry needs it."
        )
    )
    parser.add_argument("source", type=Path, help="source .hdf image")
    parser.add_argument("--output", type=Path, help="explicit output image path")
    parser.add_argument("--cache-dir", type=Path, help="directory for converted images")
    args = parser.parse_args()

    source = args.source.expanduser().resolve()
    if not source.is_file():
        raise SystemExit(f"{source}: not a file")

    info = analyze(source)
    if not info.supported:
        print(source)
        print(f"{source}: {info.reason}; using original image.", file=sys.stderr)
        return 0

    if info.compatible:
        print(source)
        return 0

    if args.output:
        output = args.output.expanduser()
    elif args.cache_dir:
        output = cache_path(source, args.cache_dir.expanduser())
    else:
        raise SystemExit("normalization needs --output or --cache-dir")

    if output.exists():
        output_info = analyze(output)
        if output_info.supported and output_info.compatible:
            print(output)
            print(f"Using existing RPCEmu-compatible hard drive copy: {output}", file=sys.stderr)
            return 0
        if args.output:
            raise SystemExit(
                f"{output}: exists but is not a compatible generated image; remove it first"
            )
        print(f"Replacing stale RPCEmu hard drive copy: {output}", file=sys.stderr)
        output.unlink()

    patch_copy(source, output, info)
    print(output)
    print(
        "Created RPCEmu-compatible hard drive copy "
        f"with {RPCEMU_SECTORS_PER_TRACK} sectors/track and {RPCEMU_HEADS} heads: {output}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
