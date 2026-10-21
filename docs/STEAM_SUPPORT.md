# Steam Support Plan

## Status And Scope

Steam support is a proposal, not an implemented or announced feature. External
Steam requirements in this document were checked on 2026-10-21 and must be
rechecked before release. The recommended product is the existing C64 version
of Moria8 packaged with a pinned C64 emulator and a small desktop launcher. It
is not a native rewrite of the game.

The first release should target Windows and be tested through Proton on Steam
Deck. Native Linux and macOS depots, achievements, and controller-native game
UI can follow after the basic package is proven.

The largest release risk is permission to redistribute the required Commodore
ROMs. The largest engineering tasks are transparent save-media handling and a
usable controller mapping.

## Recommended Product Architecture

```text
Steam
  `-- Moria8 launcher
        `-- pinned SDL2 VICE/x64sc process
              |-- unit 8: installed game D64, read-only
              `-- unit 9: per-user save D64, read/write

Steam Auto-Cloud <--> per-user save D64 only
```

The launcher should:

* create or copy a valid save D64 into per-user storage on first launch;
* mount the installed program D64 read-only on unit 8;
* mount the per-user save D64 read/write on unit 9;
* start VICE with a packaged configuration, 512 KB REU, and game autostart;
* keep mutable emulator configuration, logs, and saves outside the install
  directory;
* provide sensible windowed/full-screen defaults and controlled hotkeys;
* provide an obvious way to close the emulator or honor Steam's Stop action;
* wait for VICE to exit so Steam playtime and Cloud synchronization are
  correct; and
* never replace an existing save D64 during install or update.

Use an unmodified, separately executed VICE binary for the first release. Do
not link VICE to the proprietary Steamworks API or apply Steam CEG/DRM to it
without a specific license review. A Steam-aware helper, if later needed,
should remain a separate process.

## Existing Repository Support

The current codebase already supplies most of the emulated-game side:

* `make disk64` builds `build/moria8-c64.d64` and the C64 distribution ZIP.
  Packaging rules live in `platforms/commodore/Makefile`.
* The current development launch uses `x64sc`, true-drive emulation, and
  autostart. Its audio option is host-specific and is not suitable as the
  packaged cross-host configuration.
* The disk subsystem already supports a program device and a separate save
  device. See `platforms/commodore/common/disk_swap.s` and
  `platforms/commodore/common/disk_setup_banked.s`.
* The save format has four slots, media identification, and compatibility
  handling. See `platforms/shared/save.s` and
  `platforms/commodore/c64/hal/storage.s`.
* The C64 runtime tests already create a valid blank save D64 and exercise a
  dual-drive VICE configuration. See
  `platforms/commodore/c64/run_tests.sh`.
* The C64 input implementation is keyboard-oriented. See
  `platforms/commodore/c64/input.s`, `core/input_tables.s`, and the command
  reference in `docs/MANUAL.md`.
* The tested 512 KB REU path should be enabled in the packaged configuration
  to reduce later overlay-load latency.

One game-side usability change is recommended. `disk_setup_done` is reset on
every process launch, so a player currently has to select `D)isk Setup` each
session even when a valid unit-9 save disk is already mounted. A Steam-specific
C64 startup path should probe unit 9 for `MORIA8.ID` and adopt it automatically.
This belongs in the platform layer rather than shared game logic.

Normal game quit and save-and-quit paths return to the title screen rather than
terminating the host process. Version one may rely on closing VICE or Steam's
Stop action, but that behavior must be intentional, documented, and usable
with the official controller layout.

## Legal And Distribution Gates

This section identifies release due diligence, not legal advice. Do not begin a
commercial release until each item has an affirmative answer.

### Moria8 And VICE

Moria8 and VICE can be distributed commercially under their respective free
software licenses, subject to their complete license, notice, and corresponding
source obligations. A Steam depot should include:

* the applicable Moria8 license and exact corresponding source;
* the VICE license, notices, dependency notices, and exact source/build
  materials for the shipped binary; and
* a third-party notices document that identifies the versions and licenses of
  all bundled components.

`data/SOURCE-OFFER` currently describes the Moria8 disk release and does not
cover a bundled VICE binary. The Steam package needs its own complete source
compliance materials. Before release, also reconcile the repository's GPLv3
wording with the GPLv3-or-later wording in `data/LICENSE`.

Valve says Steamworks API integration is not required for release and warns
that copyleft licenses can be problematic when software is combined with the
Steamworks SDK. The conservative first release therefore uses no code-level
Steamworks API integration.

References:

* [Valve guidance for open-source software](https://partner.steamgames.com/doc/sdk/uploading/distributing_opensource)
* [Steamworks API overview](https://partner.steamgames.com/doc/sdk/api)
* [VICE source and license notice](https://github.com/VICE-Team/svn-mirror/blob/main/vice/README)
* [GNU GPL commercial-distribution FAQ](https://www.gnu.org/licenses/gpl-faq.html#DoesTheGPLAllowMoney)

### Commodore ROMs

The VICE license does not grant rights to redistribute Commodore firmware. The
current true-drive launch path requires the C64 BASIC, KERNAL, and character
ROMs as well as the 1541 drive ROM. Obtain written commercial redistribution
rights that cover every required ROM, platform, territory, and distribution
method.

MEGA65 OpenROMs are worth evaluating but are not currently a drop-in solution
for this package and do not provide a replacement 1541 drive ROM. A ROM-free
VICE configuration would require disabling true-drive emulation and validating
the complete boot, overlay-loading, save, load, and error paths using virtual
device traps. Existing product tests do not establish that configuration as a
shipping mode.

References:

* [VICE ROM copyright notice](https://github.com/VICE-Team/svn-mirror/blob/main/vice/README)
* [C64 ROM licensing guidance](https://www.c64forever.com/kb/13-122)
* [MEGA65 OpenROMs](https://github.com/MEGA65/open-roms)
* [OpenROM implementation status](https://github.com/MEGA65/open-roms/blob/master/STATUS.md)

### Other Rights

Before charging for the game:

* confirm commercial redistribution rights for all commissioned artwork listed
  in `artwork/CREDITS.md`;
* document the provenance and applicable license of expressive content derived
  from Umoria or historical VMS Moria, and obtain specific review for anything
  copied from the original VMS distribution; and
* clear the `Moria8` name and any Commodore names, logos, or trade dress used in
  marketing.

The VMS provenance item is due diligence, not a conclusion that current Moria8
content is noncompliant.

References:

* [Umoria license information](https://github.com/dungeons-of-moria/umoria/blob/master/README.md#license-information)
* [Original VMS Moria distribution notice](https://raw.githubusercontent.com/dungeons-of-moria/vms-moria/master/aaareadme.1st)

## Save Data And Steam Cloud

Use Steam Auto-Cloud rather than SDK calls for the first release. Synchronize
only the per-user save D64, plus an intentionally designed set of rotating
backups if those are added. Do not synchronize machine-specific VICE video,
audio, window, or input configuration.

The save image must be flushed and closed before the launcher exits. Test abrupt
termination and Cloud conflict recovery so an interrupted emulator session
cannot silently replace the last known-good save.

If a blank save-template D64 is shipped in the depot, it is a shipping disk
image and must contain `data/LICENSE` and `data/SOURCE-OFFER` in accordance with
the repository release rules. Generating the blank image on first launch avoids
shipping an additional disk image but requires a deterministic, tested image
creator.

Reference: [Steam Cloud and Auto-Cloud](https://partner.steamgames.com/doc/features/cloud)

## Input And Steam Deck

Publish an official Steam Input legacy layout that maps controller inputs to
the existing C64 keyboard commands. A reasonable starting layout is:

* D-pad and left stick: eight-way movement;
* face and shoulder buttons: common contextual commands;
* radial or touch menus: the larger command vocabulary; and
* a dedicated binding for the virtual keyboard.

Keyboard support remains first class. Character naming and less-common
commands still require text entry, so the honest initial target is keyboard
support plus partial controller support and Steam Deck **Playable**.

Steam Deck **Verified** should be a later milestone. Valve's published criteria
require all functionality to be accessible with the default controller layout,
controller-appropriate prompts, automatic or controller-native text entry, a
controller-navigable launcher, readable text, and acceptable default
performance. Meeting those requirements will likely require controller-aware
game UI rather than only a legacy key mapping.

References:

* [Steam Input legacy mappings](https://partner.steamgames.com/doc/features/steam_controller/legacy_mode)
* [Steam Deck compatibility criteria](https://partner.steamgames.com/doc/steamhardware/compat)

## Steam Release Work

Valve's public documentation does not describe a separate approval track for
emulator-packaged games. Treat this as a normal game submission while fully
disclosing and documenting the rights to the game, emulator, ROMs, artwork,
and other bundled content.

Release work includes:

* Steam partner onboarding, tax and banking verification, and the per-app Steam
  Direct fee;
* a SteamPipe application with a Windows depot and a common game-data depot;
* at least one valid launch option and a near-final default-branch build;
* accurate system requirements and feature claims;
* store capsules, library artwork, actual-gameplay screenshots, and a trailer;
* the content survey and all applicable regional ratings; and
* separate store-page and build reviews before release.

For a new Steam partner account, account for the current 30-day waiting period
after paying the application fee, at least two weeks of public Coming Soon
presence, and review time. Some of this work can overlap, but six calendar
weeks is a prudent minimum after onboarding begins. Recheck Valve's current
requirements and asset dimensions when production starts.

References:

* [Steam Direct](https://partner.steamgames.com/steamdirect/)
* [SteamPipe upload process](https://partner.steamgames.com/doc/sdk/uploading)
* [Steam review process](https://partner.steamgames.com/doc/store/review_process)
* [Store graphical assets](https://partner.steamgames.com/doc/store/assets)
* [Store trailers](https://partner.steamgames.com/doc/store/trailer)
* [Steam content survey](https://partner.steamgames.com/doc/gettingstarted/contentsurvey)

## Proposed Delivery Phases

Estimates assume one experienced engineer, exclude external licensing lead
time, and are planning ranges rather than commitments.

| Phase | Deliverable | Estimate |
| --- | --- | ---: |
| 0 | ROM, artwork, branding, and game-content rights clearance | External dependency |
| 1 | Launcher/config/save proof of concept | 2-4 working days |
| 2 | Clean keyboard-first Windows package | 1-2 engineering/QA weeks |
| 3 | Auto-Cloud, official controller layout, Deck Playable, store QA | 3-6 weeks total |
| 4 | Deck Verified UI, achievements, and native OS depots | Additional 4-8 weeks |

Phases 1 and 2 should not become release work until Phase 0 establishes a
viable ROM-distribution path. A time-boxed technical prototype may still be
useful for validating launcher and save behavior, but it must not redistribute
unlicensed ROMs.

## Version-One Boundaries

The recommended first release includes:

* Windows plus tested Proton/Steam Deck operation;
* a pinned stock VICE build launched as a separate process;
* a read-only program disk and persistent per-user save disk;
* 512 KB REU enabled by default;
* Auto-Cloud for the save disk only;
* keyboard controls and an official Steam Input legacy layout; and
* complete third-party notices and corresponding-source compliance.

The first release should not depend on:

* a modified VICE fork;
* Steamworks API linkage, Steam DRM, achievements, or rich presence;
* native Linux or macOS depots; or
* a Steam Deck Verified rating.

## Verification And Acceptance Criteria

Before submission, verify all of the following:

* A clean Steam installation boots directly to Moria8 without showing setup
  dialogs or requiring emulator knowledge.
* Installation and launch work when Steam library and user-data paths contain
  spaces and non-ASCII characters.
* Unit 8 remains read-only and cannot modify the installed game image.
* First launch creates a valid save disk; later launches and application
  updates preserve it.
* A new game can save, exit completely, relaunch, and load every save slot.
* Steam Cloud synchronizes only intended save data and handles conflicts
  without silent loss.
* Keyboard and the published controller layout can reach all functionality
  claimed on the store page.
* The default presentation preserves the game's 4:3 aspect ratio, produces
  readable text, and behaves correctly in windowed and full-screen modes.
* The launcher exits cleanly after VICE and reports the correct lifetime to
  Steam.
* Closing the emulator and using Steam's Stop action both terminate the package
  without corrupting the save image.
* The Windows build works on supported Windows versions and under the tested
  Steam Deck Proton configuration.
* Every bundled binary, ROM, artwork asset, and data file has documented
  redistribution authority.
* The depot contains complete license, third-party notice, and corresponding
  source materials.
* The repository's normal release gate, `make test`, passes from a clean
  release-candidate checkout, and Steam-specific package smoke tests pass.

## Recommended Next Decision

Resolve the C64 and 1541 ROM distribution path first. If written rights are
available, proceed with a stock-VICE Windows/Proton proof of concept. If they
are not, run a separate compatibility investigation for a ROM-free virtual
drive configuration before estimating the release again.
