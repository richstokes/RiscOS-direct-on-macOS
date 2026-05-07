# RISC OS 4 on macOS

This folder launches a usable RISC OS 4.02 desktop on macOS with RPCEmu.
It downloads the Mac RPCEmu build, RISC OS 4 CD image, and RISC OS 4.02 ROM
zip on first run, then generates a local RPCEmu data directory and starts the
native Mac interpreter.

## Launch

```sh
cd RISCOS_4
./run.sh
```

That command prepares `run/rpcemu-riscos4/Data` and starts the native Mac
RPCEmu interpreter. On this machine the boot test reached the RISC OS desktop
with the icon bar visible, including HostFS, the mounted RISC OS 4 CD, and
Apps. `make rpcemu-riscos4` is kept as a shortcut, but `./run.sh` and its
script flags are the intentional interface.

To download and stage everything without opening the RPCEmu window, use:

```sh
./run.sh --prepare-only
```

The launcher also nudges the RPCEmu window to the top of the main display after
Qt creates it. The default is `20,24`; override it with
`--window-position X,Y`, or disable the nudge with `--no-window-position`.

You can also boot with an Acorn `.adf` floppy image already inserted in drive
`:0`:

```sh
./run.sh --floppy "/Users/rich/Library/CloudStorage/Dropbox/Games/emulators/Archie/Games/3D Tanks (19xx)(-).adf"
```

The launcher copies the image to RPCEmu's startup floppy filename
`run/rpcemu-riscos4/Data/boot.adf`, which RPCEmu loads as drive `:0` before
RISC OS starts. A second disk can be supplied with `--floppy1 FILE` for drive
`:1`. RPCEmu's Risc PC model already exposes floppy drives to RISC OS, so no
extra attach setting is needed; open the `:0` floppy icon once the
desktop has booted. By default this uses a working copy so the original game
disk image is not modified; pass `--link-floppy` if you want RPCEmu to write
directly to the original `.adf`.

Hard drive images work the same way, using RPCEmu's built-in `hd4.hdf` and
`hd5.hdf` startup filenames:

```sh
./run.sh --hard-drive "/Users/rich/Library/CloudStorage/Dropbox/Games/emulators/Archie/hubersn_diskimage.hdf"
```

`--hard-drive` mounts the image as ADFS drive `:4`; use `--hard-drive5 FILE`
for drive `:5`. Hard drive images are symlinked by default so
large images do not need to be copied and writes persist to the original `.hdf`
when the image already matches RPCEmu's Risc PC IDE geometry. If the launcher
detects a FileCore image that needs conversion, it creates a persistent
RPCEmu-compatible copy under `run/rpcemu-riscos4/hard-drives/`, normalises the
embedded geometry, clears the boot block's hardware-private byte that confuses
RISC OS 4 ADFS under RPCEmu, and links that copy as `hd4.hdf`; the original
image is left untouched. Pass `--copy-hard-drive` if you want a disposable
working copy instead.

For users interested in a ready-made Archimedes software archive, search for
`CROS42_082620.7z`. It expands to `CROS42.hdf`, a large Classic RISC OS image
with lots of apps, games, demos, and utilities. The launcher will automatically
create the RPCEmu-compatible geometry-fixed copy needed for RISC OS 4.

Some older Archimedes games switch into legacy screen modes that do not always
behave well with the default Super-VGA/high-resolution desktop setup. If a game
resizes the RPCEmu window and then only shows a black screen, launch with the
game compatibility profile:

```sh
./run.sh \
  --game-compat \
  --hard-drive /Users/rich/Downloads/CROS42.hdf
```

That profile skips the generated high-resolution ModeInfo file, sets the RISC OS
monitor type to VGA, uses mode 28 for the desktop, switches RPCEmu to its
`A7000+` model, and turns off follow-host-mouse mode and VRAM-backed display
memory. You can also tune these separately with `--model`, `--monitor-type`,
`--wimp-mode`, `--desktop-mode`, `--no-hostfs-display-boot`,
`--mouse-following`, `--no-follow-mouse`, or `--vram-size`.

For old Archimedes games, `.adf` floppies are the best thing to try in this
RPCEmu setup, but they may still black-screen: RPCEmu emulates Risc PC/A7000
hardware rather than older VIDC1/IOC/MEMC Archimedes machines. ADFFS's "Boot
floppy" path is not a complete workaround here either, since ADFFS notes RPCEmu
can open floppy images but games fail because RPCEmu's MMU emulation is
incomplete. For maximum game compatibility, use the same `.adf` images with an
Archimedes-class emulator/core such as MAME `aa310`.

The prep step seeds RPCEmu's CMOS file to boot from HostFS, then writes a small
HostFS `!Boot` file that loads an RPCEmu ModeInfo file and switches the desktop
to 1280x1024 in 256 colours with `EX1 EY1` eigen factors. The eigen factors are
important for RPCEmu's follow-host-mouse mode: `EX0 EY0` boots, but it gives the
desktop a half-width pointer bound. CMOS Wimp mode 31 is still set as a
fallback, so the desktop lands at 800x600 instead of the default 640x480 if the
HostFS boot file is unavailable.

The verified boot log includes:

```text
romload: Loaded 'riscos402.rom' 4194304 bytes
romload: Total ROM size 4 MB
romload: ROM patch applied: 8MB VRAM RISC OS 4.02
HostFS: Registration request version 3 accepted
```

## Optional Make Targets

```sh
make fetch-riscos4-roms
make fetch-rpcemu-mac
make fetch-riscos4-cd
make prepare-rpcemu-riscos4
make rpcemu-riscos4
make check-scripts
```

`make rpcemu-riscos4` is equivalent to `./run.sh`. The plain script path is
preferred because it supports all runtime flags directly.

The helper shell scripts are Bash scripts, not zsh scripts. They can be run
directly via their `#!/usr/bin/env bash` shebangs or explicitly with
`bash ./run.sh ...`. `make check-scripts` runs `bash -n` over `run.sh` and
every `scripts/*.sh` file; use `make check-scripts BASH_CMD=/bin/bash` to check
against macOS's bundled Bash 3.2.

## What Gets Used

- `emulators/rpcemu-0.9.4a-mac/`: Mac RPCEmu 0.9.4a app bundle.
- `downloads/archive-org/riscos-4-cdrev-3/RISCOS4CDREV3.iso`: RISC OS 4 CD
  Rev 3 mounted as the emulator CD-ROM.
- `roms/a7000p.zip`: split RISC OS 4 ROM zip.
- `run/rpcemu-riscos4/Data/roms/riscos402.rom`: generated 4MiB RPCEmu ROM.
- `run/rpcemu-riscos4/Data/rpc.cfg`: generated RPCEmu config.
- `run/rpcemu-riscos4/Data/hostfs/!Boot,feb`: generated HostFS boot file.
- `run/rpcemu-riscos4/Data/hostfs/RPCEmuModes,fff`: generated ModeInfo file
  containing 1280x800 and 1280x1024 display timings.

ROMs and downloaded binaries are intentionally ignored by this workspace.

## ROM Handling

RPCEmu wants files in its `roms` directory to concatenate into one 2/4/6/8MiB
ROM image. The `a7000p.zip` ROM set stores RISC OS 4.02 as two
16-bit chip images:

```text
riscos402_1.bin
riscos402_2.bin
```

The prep script merges them into:

```text
run/rpcemu-riscos4/Data/roms/riscos402.rom
```

You can run the merge directly:

```sh
scripts/merge-rpcemu-rom.py roms/a7000p.zip \
  --bios 402 \
  --output run/rpcemu-riscos4/Data/roms/riscos402.rom
```

Verified local merged ROM:

```text
riscos402.rom   4,194,304 bytes   sha1 37acd8573da51493beb0fa6eef29623ce382822f
```

## Notes

Stock QEMU is not a configuration-only route for RISC OS 4 because it lacks an
Acorn A7000/Risc PC board model. Stock MAME can identify and start the RISC OS
4.02 ROM set, but its A7000+/Risc PC drivers were not usable as a desktop path
here.

## Sources

- RPCEmu home/downloads: <https://www.marutan.net/rpcemu/index.php>
- RPCEmu ROM image manual: <https://www.marutan.net/rpcemu/manual/romimage.html>
- Mac RPCEmu 0.9.4a release: <https://github.com/Septercius/rpcemu-dev/releases/tag/0.9.4a>
- RISC OS 4.02 hardware compatibility: <https://www.riscos.com/riscos/402/index.php>
- RISC OS CMOS allocation: <https://www.riscos.com/support/developers/prm/cmos.html>
- RISC OS mode table: <https://www.riscos.com/support/developers/prm/modes.html>
- RISC OS ModeInfo and `LoadModeFile`: <https://www.riscos.com/support/developers/prm/video.html>
- RISC OS FileCore hard disc maps and disc records: <https://www.riscos.com/support/developers/prm/filecore.html>
- RISC OS 4 CD Rev 3 ISO: <https://archive.org/details/riscos-4-cdrev-3>
- MDK `a7000p` ROM set details: <https://mdk.cab/game/a7000p>
- RPCEmu HDF geometry discussion: <https://www.mail-archive.com/rpcemu%40riscos.info/msg00736.html>
- RPCEmu hard drive creation notes: <https://stardot.org.uk/forums/viewtopic.php?t=11822>
