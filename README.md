# RISC OS on macOS

Two independent macOS launch paths live in this repo:

- [RISCOS_4](RISCOS_4/README.md): RISC OS 4.02 on the native macOS RPCEmu app. This is the easiest desktop route; from that folder, run `./run.sh`.
- [RISCOS_5](RISCOS_5/README.md): RISC OS Direct/RISC OS 5 via a local QEMU Linux VM. This is a more experimental route.

I only tested on mac(OS Tahoe). It might work on Linux. It almost certainly won't work on Windows.

&nbsp;

For RISC OS 3, try [arculator](https://github.com/richstokes/arculator-mac), which is a dedicated emulator and significantly less jank than these scripts, but doesn't support later RISC OS versions as far as I can tell. If your goal is to play games I would start here :-) 