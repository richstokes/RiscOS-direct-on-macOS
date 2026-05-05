#!/usr/bin/env python3
"""Extract an Acorn ADFS image with a local ADFSlib checkout."""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adfslib", required=True, help="Directory containing ADFSlib.py")
    parser.add_argument("image")
    parser.add_argument("destination")
    args = parser.parse_args()

    adfslib = Path(args.adfslib).expanduser().resolve()
    image = Path(args.image).expanduser().resolve()
    destination = Path(args.destination).expanduser().resolve()

    sys.path.insert(0, str(adfslib))
    try:
        from ADFSlib import ADFSdisc, ADFS_exception
    except ImportError as exc:
        print(f"Could not import ADFSlib from {adfslib}: {exc}", file=sys.stderr)
        return 1

    try:
        with image.open("rb") as handle:
            disc = ADFSdisc(adf=handle, verify=1)
            if destination.exists():
                shutil.rmtree(destination)
            destination.mkdir(parents=True)
            disc.extract_files(
                str(destination),
                filetypes=1,
                separator=",",
                convert_dict={"/": "."},
            )
    except ADFS_exception as exc:
        print(f"Unrecognised ADFS image {image}: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
