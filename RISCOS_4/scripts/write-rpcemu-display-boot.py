#!/usr/bin/env python3
"""Write HostFS boot files that load modern RISC OS display modes."""

from __future__ import annotations

import argparse
from pathlib import Path


MODEINFO = """file_format:1
monitor_title:RPCEmu LCD
DPMS_state:1
startmode
mode_name:1280 x 800
x_res:1280
y_res:800
pixel_rate:71000
h_timings:32,80,0,1280,0,48
v_timings:6,14,0,800,0,3
sync_pol:2
endmode
startmode
mode_name:1280 x 1024
x_res:1280
y_res:1024
pixel_rate:135000
h_timings:144,248,0,1280,0,16
v_timings:3,38,0,1024,0,1
sync_pol:0
endmode
"""


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create HostFS !Boot and ModeInfo files for RPCEmu."
    )
    parser.add_argument("hostfs", type=Path, help="RPCEmu Data/hostfs directory")
    parser.add_argument(
        "--desktop-mode",
        default="X1280 Y1024 C256 EX1 EY1",
        help="Mode string to pass to RISC OS WimpMode",
    )
    args = parser.parse_args()

    args.hostfs.mkdir(parents=True, exist_ok=True)
    (args.hostfs / "RPCEmuModes,fff").write_text(MODEINFO, encoding="ascii")

    boot_commands = [
        "LoadModeFile HostFS::HostFS.$.RPCEmuModes",
        f"WimpMode {args.desktop_mode}",
    ]
    (args.hostfs / "!Boot,feb").write_bytes(
        ("\r".join(boot_commands) + "\r").encode("ascii")
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
