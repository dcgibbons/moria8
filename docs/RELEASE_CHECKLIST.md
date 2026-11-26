# Release Checklist

Replace `vX.Y.Z` below with the chosen base release version (verify
`version.json` matches `X.Y.Z` across all 8 ports before tagging).

## Build Channels (`dev` -> `rc` -> `release`)

Version suffixes are resolved centrally by `tools/version_info.py` across all
8 ports (`c64`, `c128`, `plus4`, `apple2`, `cx16`, `atari8`, `bbcmaster`, `cpm`)
and all 5 cartridges:

- `version.json` stores only the base `MAJOR.MINOR.PATCH` SemVer (`"X.Y.Z"`).
- `BUILD_CHANNEL` selects the suffix (default `auto`):
  - `auto`: clean exact Git tag `vX.Y.Z` -> `release` (`vX.Y.Z`); clean exact
    Git tag `vX.Y.Z-rcN` -> `rc` (`vX.Y.Z-rcN`); untagged/dirty worktree -> `dev`
    (`vX.Y.Z-dev`).
  - `dev` (`BUILD_NUM` optional `0..999`): `vX.Y.Z-dev`, `vX.Y.Z-dev0`,
    `vX.Y.Z-dev1`, …
  - `rc` (`BUILD_NUM` required `0..999`): `vX.Y.Z-rc0`, `vX.Y.Z-rc1`, …
  - `release` (no `BUILD_NUM`): `vX.Y.Z`
- `VERSION_SUFFIX`: optional explicit override (must keep display string
  `<= 16` chars for Commodore directory art in `tools/diskart.py`).
- Run `make version-info` (with any overrides) to inspect the resolved string
  before building.

### Development Cycle (`dev [0..n]`)

After shipping `vX.Y.Z` (or starting a new feature cycle), bump `version.json`
to the next target version (`X.(Y+1).0`). Default local `make build` /
`make disk` automatically stamps **`vX.(Y+1).0-dev`** across title screens,
System Info, disk directory art, CX16 `manifest.json`, and CP/M `README.TXT`, or
pass `BUILD_CHANNEL=dev BUILD_NUM=1` for numbered test builds (`[0..n]`).

## Pre-Tag Readiness

- Confirm `version.json` matches the release target `X.Y.Z` across all 8 ports
  (`c64`, `c128`, `plus4`, `apple2`, `cx16`, `atari8`, `bbcmaster`, `cpm`).
- Add `docs/release_notes/release_notes-vX.Y.Z.md` and confirm versioned
  download URLs (`.../releases/download/vX.Y.Z/moria8-*-vX.Y.Z.<ext>`) and
  notes links in `README.md` and `docs/index.html` match `vX.Y.Z`.
- Confirm player-facing docs (`docs/MANUAL.md`, `docs/MONSTERS.md`,
  `docs/SPELLS.md`, `docs/TROUBLESHOOTING.md`, `docs/monsters.html`) match the
  release scope.
- Confirm zero hardcoded external paths (`/home/`, `/Users/`, `/tmp/`, `$HOME`,
  `~/`) or non-empty ROM defaults in Makefiles, tools, harnesses, and workflows
  (`AGENTS.md` Rule 9).

## Release Candidate Tag (`rc [0..n]`)

Create an annotated release-candidate tag from the commit intended for release:

```sh
git tag -a vX.Y.Z-rc1 -m "Moria8 vX.Y.Z release candidate 1"
git push origin vX.Y.Z-rc1
```

If the candidate fails release validation, fix the issue on `main` and create a
new candidate tag:

```sh
git tag -a vX.Y.Z-rc2 -m "Moria8 vX.Y.Z release candidate 2"
git push origin vX.Y.Z-rc2
```

Do not move a public release-candidate tag after pushing it.

## Clean Tag Worktree

Build, test, checksum, and upload artifacts from a clean checkout of the tag,
not from a dirty development worktree:

```sh
git fetch --tags
git worktree add ../moria8-vX.Y.Z-rc1 vX.Y.Z-rc1
cd ../moria8-vX.Y.Z-rc1
git status --short
```

Expected status before release validation:

```text
```

The empty output matters. Do not build release artifacts from a worktree with
untracked files, unstaged edits, local planning docs, or generated leftovers.

## Clean Build

```sh
make version-info
make clean
make artifact-checksums   # or: make artifacts (runs check-release-clean + GPG signs)
```

In a clean `vX.Y.Z-rc1` tag worktree, `BUILD_CHANNEL=auto` resolves
`vX.Y.Z-rc1` automatically (embedding `vX.Y.Z-rc1` in binaries and staging
`build/release/moria8-*-vX.Y.Z-rc1.*`). In a clean `vX.Y.Z` final tag worktree,
`BUILD_CHANNEL=auto` resolves `vX.Y.Z`.

`make artifacts` enforces `--check-release-clean` (requiring a clean Git tree on
the matching `vX.Y.Z` or `vX.Y.Z-rcN` tag unless `ALLOW_DIRTY_RELEASE=1`), signs
with GPG, and is intended to run from your own interactive terminal after
preparing or unlocking the signing key. Use `make artifact-checksums` (with
optional `BUILD_CHANNEL=dev|rc|release BUILD_NUM=N`) when you only need to
rebuild all 18 unversioned images in `build/`, stage versioned copies under
`build/release/`, and write `build/release/SHA256SUMS` without touching GPG.

Expected staged release artifacts (`RELEASE_ARTIFACTS` under `build/release/`,
built from `BUILD_ARTIFACTS` in `build/`, where `<ver>` is `vX.Y.Z-rcN` for an RC
or `vX.Y.Z` for final release):

- `build/release/moria8-c64-<ver>.d64`
- `build/release/moria8-c64-<ver>.crt` (C64 cartridge)
- `build/release/moria8-c128-<ver>.d64`
- `build/release/moria8-c128-<ver>.d71`
- `build/release/moria8-c128-<ver>.d81`
- `build/release/moria8-c128-<ver>.crt` (Magic Desk 128 cartridge)
- `build/release/moria8-plus4-<ver>.d64`
- `build/release/moria8-plus4-<ver>.crt` (c264 Magic Cart cartridge)
- `build/release/moria8-apple2-<ver>.po`
- `build/release/moria8-cx16-<ver>.zip`
- `build/release/moria8-cx16-<ver>.crt` (Commander X16 cartridge)
- `build/release/moria8-atari8-<ver>.atr`
- `build/release/moria8-atari8-<ver>.car` (AtariMax 128 KB cartridge)
- `build/release/moria8-bbcmaster-<ver>.ssd`
- `build/release/moria8-cpm-<ver>.zip` (universal CP/M 2.2 Z80 bundle)
- `build/release/moria8-cpm-kaypro2-<ver>.dsk` (Kaypro II SSDD disk)
- `build/release/moria8-cpm-kaypro4-<ver>.dsk` (Kaypro 4 DSDD disk)
- `build/release/moria8-cpm-c128-<ver>.d71` (Commodore 128 CP/M Plus 1571 disk)
- `build/release/SHA256SUMS`
- `build/release/*.asc` (detached GPG signatures for all 18 versioned artifacts and `SHA256SUMS`)

## License & Source-Offer Compliance (`AGENTS.md` Rule 7)

Every shipping disk image, archive, and cartridge must include `data/LICENSE`
and `data/SOURCE-OFFER` (with platform EOL conversion on disks, or embedded in
ROM for Title `A` (`About`) and Help `L` on cartridges). Verify before upload:

```sh
# Commodore disk images (SEQ files) and archives
for d in build/moria8-c64.d64 build/moria8-c128.d64 build/moria8-c128.d71 build/moria8-c128.d81 build/moria8-plus4.d64; do
  echo "=== $d ==="
  c1541 "$d" -list | grep -E 'license|source-offer'
done
unzip -l build/moria8-cx16.zip | grep -E 'LICENSE|SOURCE-OFFER'

# Apple IIe ProDOS image
tools/applecommander/ac -l build/moria8-apple2.po | grep -E 'LICENSE|SOURCE.OFFER'

# Atari 8-bit DOS 2.5 ATR (LICENSE.TXT, SRCOFFER.TXT) and BBC Master 128 DFS SSD ($.LICENSE, $.SRCOFFR)
python3 -B - <<'EOF'
import struct
from pathlib import Path

lic = Path("data/LICENSE").read_bytes()
off = Path("data/SOURCE-OFFER").read_bytes()
atr = Path("build/moria8-atari8.atr").read_bytes()
found_atr = set()
for s in range(361, 369):
    sec = atr[16 + (s - 1) * 128 : 16 + s * 128]
    for i in range(8):
        e = sec[i * 16 : (i + 1) * 16]
        if e[0] != 0:
            found_atr.add(e[5:16])
assert b"LICENSE TXT" in found_atr and b"SRCOFFERTXT" in found_atr, found_atr

ssd = Path("build/moria8-bbcmaster.ssd").read_bytes()
names_ssd = {f"{chr(ssd[8 + i * 8 + 7] & 0x7F)}.{ssd[8 + i * 8 : 8 + i * 8 + 7].decode('ascii').rstrip()}"
             for i in range(ssd[0x105] // 8)}
assert "$.LICENSE" in names_ssd and "$.SRCOFFR" in names_ssd, names_ssd
print("ATR and SSD legal files verified.")
EOF

# CP/M 2.2 Z80 zip bundle, disk images, and MORIA8.DAT container
unzip -l build/moria8-cpm.zip | grep -E 'LICENSE|SOURCE-OFFER|README\.TXT'
for d in build/moria8-cpm-kaypro2.dsk build/moria8-cpm-kaypro4.dsk build/moria8-cpm-c128.d71; do
  echo "=== $d ==="
  tools/ctools/ctools "$d" d | grep -E 'LICENSE\.TXT|SRCOFFR\.TXT'
done

# All 5 cartridges (verifies embedded ROM assets including LICENSE & SOURCE-OFFER)
python3 -B tools/check_easyflash.py build/moria8-c64.crt build/c64-cart
python3 -B tools/check_c128_md128.py build/moria8-c128.crt build/c128-cart
python3 -B tools/check_plus4_magic.py build/moria8-plus4.crt build/plus4-cart
python3 -B tools/check_cx16_cart.py --crt build/moria8-cx16.crt --bin build/cx16-cart/moria8-cx16.bin --manifest build/cx16-cart/moria8-cx16.json --build-dir build/cx16-cart --data-dir data
python3 -B tools/check_atari8_car.py build/moria8-atari8.car build/atari8-cart
```

## Automated Gates

Set all required emulator ROM/binary environment variables so MAME and `x16emu`
suites fail instead of skipping when `REQUIRE_ALL_ROMS=1` is enabled:

```sh
export A2ROMS=/path/to/apple2/roms
export ATARI8ROMS=/path/to/atari8/roms
export BBCMROMS=/path/to/bbcmaster/roms
export X16EMU=x16emu
export X16ROM=/path/to/cx16/rom.bin

make check-item-docs
make check-hal-boundaries
make check-zp && make check-6502-lint
REQUIRE_ALL_ROMS=1 make -j8 -O test
make playtest-gate
```

For focused iteration during candidate fixes:

- `make test64`, `make test64-cartridge`
- `make test128-fast`, `make test128-fast-smoke`, `make test128`, `make test128-cartridge`
- `make testplus4`, `make testplus4-cartridge`
- `make testapple2-runtime`
- `make testcx16`
- `make testatari8`
- `make testbbcmaster`
- `make testcpm` (`make testcpm-memory-contract`)

`make check-zp && make check-6502-lint`, `REQUIRE_ALL_ROMS=1 make -j8 -O test`
(failing non-zero if any required ROM/emulator env var is missing), and
`make playtest-gate` (with zero skipped targets) remain the mandatory release
gates.

## Manual Smokes

- **Cross-Geometry Save Compatibility Check:** Confirm pre-`$22` saves fail
  cleanly with `Unsupported save.` and note that `80x48` (**C64**, **Plus/4**,
  **Atari 8-bit**) saves are incompatible with `198x66` (**C128**, **Apple
  IIe**, **Commander X16**, **BBC Master 128**, **CP/M 2.2 Z80**) saves
  (`Save file corrupt!` across C64/C128 shared `"MORIA01"` disks;
  `Unsupported save.` on Plus/4).

- **Commodore 64 (`.crt`, Disk):** Boot `moria8-c64.crt` and `moria8-c64.d64`
  in VICE or on hardware; confirm title screen, Title `A` (`About`) / Help `L`,
  Disk Setup, new game to town, dungeon descent, and Save Format V2 save/reload
  (and rejection of pre-V2 saves).
- **Commodore 128 (`.d64`/`.d71`/`.d81`, Magic Desk 128 `.crt`):** Boot in
  80-column VDC mode (`-80col -VDC16KB`); confirm title art/menu, Title `A` /
  Help `L`, town entry, dungeon descent, and save/reload.
- **Commodore Plus/4 (`.d64`, Magic Cart `.crt`):** Boot disk and cartridge;
  confirm title, Title `A` / Help `L`, town entry, dungeon descent, and
  separate-drive save/reload.
- **Apple IIe (`.po`):** Boot in MAME `apple2ee` (`A2ROMS`) or hardware;
  confirm `MORIA8  LOADING  n/8` ticks to 8/8, title screen & Title `A` /
  Help `L`, town entry, dungeon descent, and 4-slot ProDOS save/reload.
- **Commander X16 (`.zip`, `.crt`):** Boot `MORIA8.PRG` (`-fsroot`) and
  `moria8-cx16.crt` in `x16emu` or hardware; confirm VERA 80-column display,
  Title `A` / Help `L`, town entry, dungeon descent, and save/reload.
- **Atari 8-bit (`800XL`/`130XE` `.atr`, AtariMax `.car`):** Boot `.atr` on
  both `a800xl` (64 KB disk streaming) and `a130xe` (130XE RAM cache) plus
  `.car`; confirm ANTIC/DLI colors, Title `A` / Help `L`, Disk Setup separate
  save disk (`D1:`/`D2:`), town entry, dungeon descent, and save/reload.
- **Acorn BBC Master 128 (`.ssd`):** Boot `moria8-bbcmaster.ssd` (`*EXEC !BOOT`
  / Shift-Break); confirm Mode 0 80-column display, Title `A` / Help `L`, Disk
  Setup separate save disk (`:0`/`:1`), town entry, dungeon descent, and
  save/reload.
- **CP/M 2.2 Z80 (`.zip`, Kaypro II/4 `.dsk`, C128 `.d71`):** Boot under
  `tools/cpm_runner` / `RunCPM` or ≥52 KB TPA hardware (`MORIA8`, `MORIA8 /V`,
  `MORIA8 /M`); confirm TPA check, ADM-3A default and ANSI color/mono modes
  (`M` / `=`), Title `A` / Help `L`, Disk Setup (`A:`–`P:`), town entry,
  dungeon descent, and atomic save/reload.

## Artifact Review

- Verify all 18 unversioned `BUILD_ARTIFACTS` (`build/moria8-<port>.<ext>`) and
  all 18 versioned `RELEASE_ARTIFACTS` (`build/release/moria8-<port>-vX.Y.Z.<ext>`)
  plus `version.json` version strings on title screens.
- Verify `build/release/SHA256SUMS` covers all 18 uploaded artifacts.
- Verify detached GPG signatures (`build/release/*.asc`) for all 18 versioned
  artifacts and `SHA256SUMS`.
- Confirm generated outputs are not staged as source (`git status --ignored -s`
  shows clean source directories with no stray `.prg`, `.sym`, `.vs`, `.ovl`,
  `.lst`, `.com`, `__pycache__`, or root MAME dirs).
- Confirm no monitor logs, external paths, private planning notes, or agent
  process files are present in the public tree.

## Final Release Tag

After one release candidate passes validation, create the final tag on the exact
same commit:

```sh
git tag -a vX.Y.Z -m "Moria8 vX.Y.Z" vX.Y.Z-rc1
git push origin vX.Y.Z
```

Verify the final tag and accepted candidate point to the same commit:

```sh
git rev-parse vX.Y.Z^{commit}
git rev-parse vX.Y.Z-rc1^{commit}
```

Those two commit hashes must match. Check out a clean worktree on `vX.Y.Z`, run
`make clean && make artifacts`, and verify the signed final `vX.Y.Z` artifacts
and smoke checks before uploading.

Do not force-move a public final release tag.

## Post-Release Bugfix (`vX.Y.(Z+1)`)

If a bug is discovered after `vX.Y.Z` is published:

1. Leave the published `vX.Y.Z` tag untouched.
2. Land the fix on `main` (or a `release/X.Y` branch if `main` has already
   bumped to `X.(Y+1).0`).
3. Bump `version.json` to `X.Y.(Z+1)` across all 8 ports.
4. Optionally cut `vX.Y.(Z+1)-rc1`, validate, then tag and publish `vX.Y.(Z+1)`.
