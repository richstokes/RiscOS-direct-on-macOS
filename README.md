# RISC OS on macOS

Two independent macOS launch paths live in this repo:

- [RISCOS_4](RISCOS_4/README.md): RISC OS 4.02 on the native macOS RPCEmu app. This is the easiest desktop route; from that folder, run `./run.sh`.
- [RISCOS_5](RISCOS_5/README.md): RISC OS Direct/RISC OS 5 via a local QEMU Linux VM. This is the older experimental route.

Generated emulator builds, VM disks, downloaded ROM/CD archives, and mounted
disc images are ignored by git and are downloaded or created locally by the
subproject scripts.
