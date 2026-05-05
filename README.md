# RISC OS 5 on macOS with QEMU

This repo wraps [RISC OS Direct for Pi 5](https://www.riscosdev.com/projects/risc-os-direct-for-pi-5/) so it can run on macOS via a local QEMU VM. It does not redistribute RISC OS Direct, Ubuntu, QEMU, or any VM disk image. The scripts download the upstream files at setup time.

## How It Works

RISC OS Direct for Pi 5 is not a normal Pi disk image. It is a Linux-hosted RISC OS build: the bundled `RISCOS.IMG` is a 32-bit ARM Linux executable, and the desktop is presented through Direct's Linux-side SDL/OpenGL frontend.

On an Apple Silicon Mac, QEMU virtualizes a local ARM64 Linux guest with HVF. Inside that guest, Direct's patched `qemu-arm` user emulator runs the 32-bit ARM `RISCOS.IMG`, while Direct's SDL frontend exposes the RISC OS desktop over VNC.

The stack is:

```text
macOS
  -> local QEMU ARM64 Linux VM
    -> RISC OS Direct Linux frontend
      -> Direct's patched qemu-arm
        -> 32-bit ARM RISCOS.IMG
```

Do not try to emulate a Raspberry Pi 5 board directly for this package. Current QEMU documents Raspberry Pi board models only up to `raspi4b`, while the generic ARM `virt` board is the recommended target for Linux guests when exact hardware reproduction is not needed.

## Quick Start

Install QEMU:

```bash
brew install qemu
```

Create the local QEMU disk:

```bash
./scripts/create-vm.sh
```

Start it:

```bash
./scripts/start-vm.sh
```

By default, this waits until RISC OS is reachable over VNC, opens `vnc://localhost:5901` with macOS, and stops the VM when the VNC viewer exits. It also keeps the serial console in `vm/serial.log` instead of taking over your terminal.

Start it without opening VNC:

```bash
./scripts/start-vm.sh --no-open-vnc
```

In this mode, QEMU stays attached to your terminal. Quit QEMU from that terminal with `Ctrl-A`, then `X`, or use `./scripts/stop-vm.sh` from another terminal.

Start it with an Acorn/RISC OS hard disc image attached:

```bash
./scripts/start-vm.sh --disc /path/to/disc.hdf
```

Start it with an Acorn/RISC OS floppy image attached:

```bash
./scripts/start-vm.sh --floppy /path/to/floppy.adf
```

You can pass both `--disc` and `--floppy` in the same launch. The launcher exposes the selected images to the Linux guest over a read-only QEMU 9p share. The guest then imports HDF images into `HardDisc4/ImportedDiscs` as `,ffc` FileCore images.

For ADF floppy images, the launcher also looks for a local `adfslib/ADFSlib.py` checkout beside or above the image path, or in `ADFSLIB_PATH`. When found, it extracts the floppy contents into `HardDisc4/ImportedFloppies` so RISC OS shows a normal folder/application tree instead of only the raw Utility-typed image file. If ADFSlib is not available, the raw ADF is imported as a `,ffc` image instead.

Stop it:

```bash
./scripts/stop-vm.sh
```

First boot is not instant. The local seed ISO installs build/runtime dependencies, downloads `DirectPi5.tbz`, extracts it inside Linux so extended attributes and RISC OS filenames survive, builds/links Direct's patched `qemu-arm`, and starts a VNC session.

Watch progress from another terminal:

```bash
ssh -p 2222 ubuntu@localhost "tail -f ~/riscos-direct-bootstrap.log"
```

Password for SSH is `ubuntu`. When the bootstrap finishes, open:

```text
vnc://localhost:5901
```

The VNC password is `riscos`. The default VNC desktop is `1920x1080`, matching the Pi 5 Direct SDL window so the RISC OS desktop is not clipped.

After the first successful bootstrap, the guest has a `riscos-direct-vnc.service` systemd unit enabled, so later boots should bring the VNC/RISC OS session back automatically.

The launcher uses Direct's `--swapmouse` SDL option by default. That makes a Mac right-click act as the RISC OS Menu button. RISC OS traditionally treats the physical right button as Adjust and the middle button as Menu, so this default is friendlier for two-button/trackpad Mac setups.

## Useful Commands

Restart RISC OS inside the guest:

```bash
ssh -p 2222 ubuntu@localhost /usr/local/bin/riscos-direct restart-vnc
```

Check bootstrap status:

```bash
ssh -p 2222 ubuntu@localhost /usr/local/bin/riscos-direct status
```

Gracefully stop the VM from another terminal:

```bash
./scripts/stop-vm.sh
```

If the guest SSH service is not responding, you can force-kill the matching QEMU process:

```bash
./scripts/stop-vm.sh --force
```

You can also quit QEMU from the terminal running it with `Ctrl-A`, then `X`.

## Notes

This is expected to be much better on Apple Silicon than Intel Mac. On Intel, QEMU can still emulate the ARM64 Linux guest with TCG, but then the guest also emulates 32-bit ARM for RISC OS, so it will be slow.

The VM uses Ubuntu 24.04 ARM64's prebuilt qcow2 only as a convenient local starting disk. It still runs under local QEMU, on your Mac. Ubuntu boots cleanly on QEMU's generic `virt` board and is close enough to Raspberry Pi OS/Debian for Direct's Linux-hosted model. Direct's upstream limitations still apply: no audio, and no VFP/NEON support for ARMv7-only RISC OS programs.

The guest bootstrap makes two local-VM-specific adjustments. It marks `bwrap` setuid because Ubuntu 24.04 restricts unprivileged user namespaces, and it runs Direct with `RISC_OS__INSECURE=YES` inside the guest because the QEMU VM is the isolation boundary. It also points the generic Linux launcher at the `hostfs/HardDisc4` tree that ships in the Pi 5 Direct archive, avoiding the stale `HardDisc4.5.28.util` download path.

The VNC session runs the SDL frontend directly, without Openbox. A small `xdotool` watchdog keeps the SDL window at the top-left of the VNC desktop and avoids title-bar/border clipping. To use a different VNC size, set `VNC_GEOMETRY` when preparing or restarting the guest session.

## Credits And Sources

This repo is glue and automation around other people's work:

- RISC OS Direct for Pi 5 is from RISC OS Developments: https://www.riscosdev.com/projects/risc-os-direct-for-pi-5/
- RISC OS itself comes from the RISC OS ecosystem and RISC OS Open: https://www.riscosopen.org/
- QEMU provides the local ARM64 VM and user-mode emulator source used by Direct's patch: https://www.qemu.org/
- QEMU Raspberry Pi board documentation: https://www.qemu.org/docs/master/system/arm/raspi.html
- QEMU ARM `virt` board documentation: https://www.qemu.org/docs/master/system/arm/virt.html
- QEMU HVF accelerator documentation: https://www.qemu.org/docs/master/system/introduction.html
- Ubuntu provides the ARM64 prebuilt qcow2 image used as the local Linux guest starting point: https://cloud-images.ubuntu.com/releases/24.04/release/
