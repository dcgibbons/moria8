# Moria8

Moria8 is a port of the classic roguelike game, Moria, for 8-bit platforms
written in platform-specific assembly. Current releases target the Commodore
64, Plus/4, and 128 systems.

![Animated GIF of Commodore 64 Play Testing](docs/assets/moria8-c64-gameplay.gif)

## Port Status

| Platform | Status | Download |
| -------- | ------ | -------- |
| Commodore 64 (C64) | Released ([notes](docs/release_notes/release_notes-v1.3.0.md)) | [moria8-c64.d64](https://github.com/dcgibbons/moria8/releases/download/v1.3.0/moria8-c64.d64) [moria8-c64.zip](https://github.com/dcgibbons/moria8/releases/download/v1.3.0/moria8-c64.zip) |
| Commodore Plus/4 | Released ([notes](docs/release_notes/release_notes-v1.3.0.md)) | [moria8-plus4.d64](https://github.com/dcgibbons/moria8/releases/download/v1.3.0/moria8-plus4.d64) |
| Commodore 128 (C128) | Released ([notes](docs/release_notes/release_notes-v1.3.0.md)) | [moria8-c128.d64](https://github.com/dcgibbons/moria8/releases/download/v1.3.0/moria8-c128.d64) |
| Commodore PET | Maybe | |
| Commodore VIC-20 | Maybe | |
| Commander X16 | In progress: boot-to-title PRG slice | |
| Acorn BBC Master | Planned | |
| Apple II | Planned | |
| Apple IIgs | Planned | |
| Atari 8-bit | Planned | |
| CP/M (Z80) | Planned | |
| MSX | Planned | |
| Nintendo Entertainment System | Planned | |
| ZX Spectrum | Planned | |

Release notes describe the current feature set, known limits, and
platform-specific behavior for each target.

See the [Cross Platform Strategy](docs/CROSS_PLATFORM_STRATEGY.md) for more
details on upcoming ports.

### Real Floppy Users

Want a real floppy disk of Moria8? Please fill out fill out the
[Google Form](https://forms.gle/aVDEXfVxjjsaLFNm6) to indicate interest.

## Building from Source

### Requirements

- macOS or Linux host
- `make`
- Java, for Kick Assembler
- VICE (`x64sc`, `x128`, `xplus4`, and `c1541`)
- Python 3 for build and test helper scripts

Kick Assembler is downloaded into `tools/kickass/` by the makefiles on first
use. To use an existing jar, pass `KICKASS=/path/to/KickAss.jar`.

VICE tool paths can be overridden through make variables when needed, for
example `make run VICE=/path/to/x64sc`.

### Build

```sh
make
make build
make disk64
make disk128
make diskplus4
make buildcx16
```

`make` and `make build` will build the entire project for all platforms.
`make disk64`, `make disk128`, and `make diskplus4` build the individual disk
images. `make buildcx16` builds the current Commander X16 boot-to-title PRG
slice.

Disk images are emitted under `build/`:

- `build/moria8-c64.d64`
- `build/moria8-c128.d64`
- `build/moria8-c128.d71`
- `build/moria8-c128.d81`
- `build/moria8-plus4.d64`

### Run

```sh
make run
make run64
make run128
make runplus4
make run cx16
```

`make run` and `make run64` launch the C64 disk. `make run128` launches the
C128 disk. `make runplus4` launches the Plus/4 disk in `xplus4` with a 1541
drive configuration. The Plus/4 artifact is a standard Commodore D64 image.
`make run cx16` launches the in-progress Commander X16 PRG under `x16emu`.
Set `X16EMU=/path/to/x16emu` and `X16_ROM=/path/to/rom.bin` when those are not
available through the default local environment.

### Test

```sh
make test
make test128-fast
make test128-fast-smoke
make test128
make testplus4
make testcx16
```

`make test` runs the default regression mix. `make test128-fast` is the fast
C128 unit batch, `make test128-fast-smoke` covers high-value C128 runtime boot
and town paths, and `make test128` is the broader C128 shell harness.
`make testcx16` runs the current Commander X16 checks: build/setup smoke,
x16emu testbench runtime coverage, and the guarded shared-gameplay link probe.
Set `X16EMU` and `X16_ROM` when needed.

## Documentation

- [Player Manual](docs/MANUAL.md)
- [Monster Reference](docs/MONSTERS.md)
- [Spell And Prayer Reference](docs/SPELLS.md)
- [Player Guide](docs/PLAYER_GUIDE.md)
- [Development Process](docs/DEVELOPMENT_PROCESS.md) - the story of Moria8,
  including how it was built with modern tooling.

## Community

Join our [Discord Server](https://discord.gg/b5rFSDZ8Yk) to get help, chat
with community, and discuss new features!

## Credits

The Dungeons of Moria is a single player dungeon simulation originally written
by Robert Alan Koeneke, with its first public release in 1983. The game was
originally developed using VMS Pascal as
[VMS Moria](https://github.com/dungeons-of-moria/vms-moria) before being
ported to the C language by James E. Wilson in 1988, and released as
[Umoria](https://github.com/dungeons-of-moria/umoria).

Moria8 is developed by [Chad Gibbons](https://github.com/dcgibbons).

## License Information

Moria8 is released under the [GNU General Public License v3.0](LICENSE).
