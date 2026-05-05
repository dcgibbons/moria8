# Moria8

Moria8 is a Commodore 64 and Commodore 128 port of the classic roguelike
Moria, based on the Umoria code line. The game is written in 6502 assembly and
built with Kick Assembler.

Original Moria was created by Robert Alan Koeneke. Moria8 is a Commodore 64/128
port based on the Umoria line, with this port by Chad Gibbons.

The port targets real hardware and VICE. Gameplay uses PETSCII character
display; the loading and title paths use platform-specific assets for each
machine.

## Targets

- Commodore 64: 40-column VIC-II display, `.d64` disk image.
- Commodore 128: 40/80-column capable runtime, VDC support, `.d71` disk image.

The C64 target is the constrained baseline. The C128 target shares gameplay
logic where practical and uses C128-specific boot, MMU, VDC, and loader code.

## Requirements

- `make`
- Java, for Kick Assembler
- VICE (`x64sc`, `x128`, and `c1541`)
- Python 3 for build and test helper scripts

Kick Assembler is downloaded into `tools/kickass/` by the makefiles on first
use. To use an existing jar, pass `KICKASS=/path/to/KickAss.jar`.

VICE tool paths can be overridden through make variables when needed, for
example `make run VICE=/path/to/x64sc`.

## Build

```sh
make
make build
make disk
make disk64
make disk128
```

Disk images are emitted under `commodore/out/`:

- `commodore/out/moria8-c64.d64`
- `commodore/out/moria8-c128.d71`

## Run

```sh
make run
make run64
make run128
```

`make run` and `make run64` launch the C64 disk. `make run128` launches the
C128 disk.

## Test

```sh
make test
make test128-fast
make test128-fast-smoke
make test128
```

`make test` runs the default regression mix. `make test128-fast` is the fast
C128 unit batch, `make test128-fast-smoke` covers high-value C128 runtime boot
and town paths, and `make test128` is the broader C128 shell harness.

## Documentation

- [Design Reference](docs/DESIGN.md)
- [Architecture Reference](docs/ARCHITECTURE.md)
- [Internal Mandates](docs/INTERNAL_MANDATES.md)
- [Release Checklist](docs/RELEASE_CHECKLIST.md)

## Current Launch State

This repository is a buildable source snapshot of an in-progress port. The core
build, disk, boot, and regression harnesses are maintained, but gameplay parity
with Umoria is not complete. Known deferred areas include monster recall depth,
some original content breadth, and long-term polish work.
