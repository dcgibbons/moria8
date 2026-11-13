# License and source viewer

## Initial design and baseline verification (2026-11-10)

- Authority/success: maintainer requests readable license/source-offer text on
  every port, disk-backed except on cartridges; copyright year is 2026.
  Explicit scope: use the existing `data/LICENSE` notice and
  `data/SOURCE-OFFER`, without adding the complete GPL text or changing media.
  Title `A)bout` and Help `L:License` open the same two-document viewer.
- Search/readers/writers: title input/rendering in seven main files, shared
  Help dispatch, overlay loaders/caches, byte-stream storage, cartridge
  descriptors and release builders. No changes to save representation.
- State/lifecycle: viewer-local document/row/column/EOF/channel state and
  142-byte core-ZP snapshot; all initialized on entry/open and closed on
  document switch, restart, error or exit. C64 disk stages a filename in the
  otherwise inactive BASIC-exit ZP snapshot, saving/restoring its first 16
  bytes in overlay-local state for the entire OPEN lifetime. No gameplay
  record or save-file buffer is borrowed.
- Production sequence: title/Help -> resident loader -> uncached `LEGALUI`
  -> program-device file stream or read-only ROM chunks -> HAL rendering ->
  close -> restore core ZP -> title redraw or reload Help.
  Page waits clear the input channel, then reselect it on the next read.
  Commands consume no turns or RNG and do not mutate map/inventory/save state.
- Ownership: ordinary overlay window, C64/C128/Plus4/Atari `$E000-$EFFF`,
  Apple main `$A400-$B9FF`, BBC Bank 4 `$A800-$BFFF`; X16 temporarily uses
  otherwise free Bank 23 `$A000-$BFFF`. Code must end before base+$600;
  ZP snapshot is base+$600..+$68D, disk/ROM input cache base+$700..+$7FF.
  BSS is not padded into PRGs. Invalidate current-overlay tags, preserve caches.
- Resident limits: C64 Help owns its heading in HelpOverlay; its unreachable
  blank fallback page is not emitted in product builds (the trampoline
  always installs real pages). Reuse existing storage bridges, including C128 `w_*`
  KERNAL wrappers. Atari puts its DOS 8.3 legal filenames, filename staging,
  and Help controller (`cmd_show_help_view`) in low resident memory (`< $4000`)
  and its legal entry (`tramp_ui_legal_display`, `legal.s`) in RuntimeBanked;
  SIO executes in low helpers and restores RAM before returning to them.
- C128 five facts: `LEGALUI` links/loads at `$E000` in Bank 0; the existing
  loader uses KERNAL-visible configuration, then `$FF00=$3E` exposes RAM for
  execution. Existing resident wrappers restore MMU/common RAM/ZP. No Bank 1
  cache allocation or VDC layout change; copied source cannot overlap owners.
- Data/widths: byte-stream input, 8-bit row/column and document index 0..1.
  CR/LF/ATASCII EOL normalize only at display. ROM text is NUL-terminated,
  padded to 256-byte chunks, capped at 32 KB; offset overflow is an error.
  Existing disk license/source-offer files and their EOL encodings remain.
- Verification: packaged assets, linked headers/workspace bounds and platform
  memory gates; production title/Help entry, both documents, paging/restart,
  missing-file recovery, return before movement and unchanged game state.
  Shared rendering and modal re-entry rows apply. Visibility, repeat,
  monsters, generation and RNG changes are N/A because semantics are unchanged.
  Full gate: `make -j7 -O test`. Release publication and flash saves are out
  of scope. No unresolved ownership or behavior questions.

Verification completed: `make -j7 -O test` passed on 2026-11-10, including
C64 209/209, C128 139/139, Plus/4 44/44, all non-Commodore runtime suites,
and 64 PAL/NTSC cartridge runtime checks plus the harness regressions.
The TURN_RENDER modal-return/shared-rendering rows and each affected platform's
payload/loader ownership rows are complete. Visibility, repeat, generation and
physical VDC layout changes are N/A; their implementations were not changed.

The C64 disk-swap regression exposed a harness checkpoint at a shared ROM/RAM
address. Scripted breakpoints now combine CPU ROM visibility with explicit
overlay ownership; the Help swap requires overlay 5 with KERNAL ROM hidden.
Four harness regressions cover the captured $EA63 KERNAL false hit, all eight
C64 CPU-port mappings, fixed-RAM delegation and non-C64 overlay filtering.
The original load-then-save-to-new-media scenario and the full gate pass
without changing their timeouts or success criteria.

The baseline above did not include the HAL audit, multiport missing-file
coverage or exact-width/EOF boundary fixtures; the repair below adds them.

## Review repair (2026-11-11)

Problem/success: repair media/device selection, missing-file handling, case-only
output copies, incremental dependencies, line wrapping/EOF, and test entry points.
Shared code must contain no platform filenames or target conditionals.
State: modal document/cache/EOL state and caller core ZP; no save representation
changes. Save ZP before loading, retain UI invalidation and live sound state.
Readers/writers: seven platform legal entries and storage adapters, ui_legal,
Help controllers, product Makefiles and legal runtime harnesses.
Lifecycle: entry completes overlay-using media handling, then snapshots caller state
into existing modal workspace before required
asset loading prompts/retries; OPEN validates drive status before selecting data;
refills return input to the keyboard; close/restart/error invalidate local cache.
Widths: unsigned 8-bit columns/rows, 128-byte disk chunks, 256-byte ROM chunks;
CRLF counts once, CR/LF/ATASCII EOL remain supported; exact row/page EOF is final.
Ownership: existing LEGALUI windows; code below base+$600, saved ZP at +$600,
cache at +$700. Filenames and banking remain platform-owned. C128 links/loads
at Bank 0 $E000, executes under $FF00=$3E, and fills underlying cache RAM from
low resident code while KERNAL is mapped. X16 restores Bank 23 after low-RAM
refills and retains overlay tags for its untouched cached banks.
Cold Apple title entry must not call the play-slot verifier before A2.PLAY
has loaded. Apple, Atari and BBC use the resident optional retry/cancel entry described
below; Commodore entries use resident media policy before the required load.
No RNG, monster, visibility producer, VDC layout, save encoding, persistent
cache allocation or gameplay rule changes. Those contract rows are N/A.
Required tests: HAL audit, incremental output recovery, platform legal gates,
40/80-column production rendering boundaries and missing-file recovery, title/
Help modal return, cached Atari/C64 Ultimate paths, then make -j7 -O test.
Unresolved design questions: none; reuse settled platform loaders/ownership.
Verification: `make -j7 -O test` passed on 2026-11-11.

Repair decisions and scope:

- Platform `legal.s` owns disk names, KERNAL bindings, OPEN validation and
  banking. Shared stream code uses capability policy only. Three naming/binding
  indirection files were removed; the small Help heading import is retained
  because C64 must own that text in HelpOverlay while other callers need it
  resident. `HAL_PLATFORM_LEGAL_VIEWER` fallbacks remain for unit fixtures that
  do not link the product's legal entry; they are not alternate shipping modes.
- The existing breakpoint harness correction remains: it fixes a demonstrated
  ROM/RAM alias and has four static regressions. This repair explicitly includes
  test infrastructure, as requested by the maintainer on 2026-11-11.
- Each emulator keeps its own 30-second deadline. Media-swap coverage is a
  separate title experiment, avoiding character-generation cost in that budget;
  the normal Help experiment independently checks gameplay-state preservation.
- Rendering cases execute the linked production viewer: 38/39/40-column text
  (and 78/79/80 on C128), CRLF split at byte 127/128, and a trailing newline at
  the last body row. Missing-file recovery is exercised on all seven disk ports.
  Normal title/Help modal checks also run with Ultimate detection and on 130XE.
- Incremental recovery was checked by removing each C64 disk, Plus/4 disk and
  cartridge LEGALUI output, rebuilding its target, and comparing identical bytes.
- No expansion of overlay slots or relaxation of asserts: C64 resident ends at
  $BF7A (134 bytes free); Atari Default at $C0DB (37 bytes free), RuntimeBanked
  at $FF57 (163 bytes free); C128 Help remains at $EFDE (34 bytes free). These
  are tight budgets, not evidence of overlap, and remain enforced by assertions.

The full gate now includes `make check-hal-boundaries`; platform `test64`,
`test128` and `testplus4` include their legal tests, and the root Makefile exposes
all three focused legal targets. Final repair verification passed: `make -j7 -O test` (2026-11-11).

Fixture discipline: the 40/80-column layout disk has a distinct disk ID and is
initialized through the production drive HAL after monitor attach. Its short
driver borrows C64 idle title-map $C600-$C605 or C128 title-time CREATURE_BASE
$1B00-$1B05, restores those bytes, and never resumes gameplay. BBC input taps
the linked input_get_key empty-buffer read before injecting each key, so text
appearing mid-render cannot cause the following key to be flushed.

Dirty-latch regression: the cartridge production Help/legal path seeds an
entry dirty bit and a new modal dirty bit and checks their OR before the
caller redraw consumes them. A one-tick sound seeded at the resident legal
entry expires during real input and stays expired after return. Both cases
also run under simulated Ultimate detection.

## Linked repair payloads

The window is an exclusive owner, not padded PRG data. Snapshot/cache labels
are uninitialized modal workspace beyond the linked payload. C128 loads into
Bank 0, runs with `$FF00=$3E`, and its resident reader writes through KERNAL ROM
to the same Bank 0 cache. All transfer sources remain resident/ROM or in the
platform OS staging buffers; no source overlaps the snapshot/cache destination.

| Port | Owner window | Emitted PRG payload | ZP snapshot | Input cache |
| --- | --- | --- | --- | --- |
| c64 | `$E000-$EFFF` | `$E000-$E472` (1139 B) | `$E600` | `$E700` |
| c64-cart | `$E000-$EFFF` | `$E000-$E35E` (863 B) | `$E600` | `$E700` |
| c128 | `$E000-$EFFF` | `$E000-$E3E3` (996 B) | `$E600` | `$E700` |
| plus4 | `$E000-$EFFF` | `$E000-$E40E` (1039 B) | `$E600` | `$E700` |
| apple2 | `$A400-$B9FF` | `$A400-$A7DC` (989 B) | `$AA00` | `$AB00` |
| cx16 | `$A000-$BFFF` | `$A000-$A3A9` (938 B) | `$A600` | `$A700` |
| atari8 | `$E000-$EFFF` | `$E000-$E3DC` (989 B) | `$E600` | `$E700` |
| bbcmaster | `$A800-$BFFF` | `$A800-$ABDC` (989 B) | `$AE00` | `$AF00` |

Apple legal input waits now use a keyboard-strobe read tap restricted to the
linked input_get_key routine, so replacing fixed sleeps does not feed keys
before the modal flush. Its host watchdog is strictly 30 seconds and a timeout
is always a failure, even if partial output contains successful assertions.

## Repair verification completed (2026-11-11)

`make -j7 -O test` passed: C64 209/209, C128 139/139, Plus/4 44/44;
Apple IIe 25 scenarios, X16 25, Atari 16 on 800XL plus 5 on 130XE, BBC 17.
Each PAL/NTSC cartridge run passed 27 runtime checks plus 10 persistence checks.
The legal harness's four static regressions passed, as did the HAL audit.
Final missing-output recovery checks regenerated identical C64/Plus4/cartridge
LEGALUI bytes. The scripted Detect Evil build assembles at resident end $BFFF
with its original boundary assertion intact; no player text was shortened.

Applicable contract rows are complete: payload/link/header/load/execution
ownership, shared modal re-entry before movement, exact-width and EOF rendering,
missing-file cleanup, dirty-latch preservation and live sound. Physical VDC,
monster visibility production, repeat commands and generation rules are N/A:
none of those implementations changed. No new MMU configuration/common-RAM
assignment was introduced; the C128 reader uses the established entry/exit path.
The final diff contains only the repair, its tests, and ownership/verification
documentation. No generated PRG/symbol/snapshot artifacts remain in source.


## Second review repair (2026-11-11)

Success criterion: no failed READST byte or failed refill reaches rendering;
EOI ($40) remains valid, whereas all other status bits are fatal. No additional
page prompt may hide a read failure. Retain live sound and OR redraw requests
on entry and exit; take the caller snapshot after media prompts which reset
message state, before loading LEGALUI. This restores the existing modal
contract, not gameplay or save semantics.

Search/readers/writers: shared ui_legal and legal_disk_stream, all seven legal
entries, storage policies, OS stream adapters, Commodore command-status probes,
and the legal/cartridge production harnesses. Reset/open/close invalidate the
cache. Refills commit only valid bytes and expose no prefix of a failed chunk.
Three bounded attempts reopen the DOS stream when its first status byte was
lost; a real DOS error does not retry. C128 uses its program-device status
probe, avoiding the save-device raw KERNAL adapter.

Ownership and widths remain unchanged: 142 saved ZP bytes at base+$600,
128-byte disk chunks at base+$700, existing low-resident C128/X16 readers.
Shared entry macros own the snapshot address and restoration policy. The
optional Apple/Atari/BBC viewer retains normal asset retries, then uses the
resident program-disk prompt with Escape cancellation; it never loads Storage
or calls an uninitialized Apple play slot. Failed-load scratch is restored
before that prompt and the next attempt takes a fresh snapshot.

Required verification: injected status errors at byte zero, mid-chunk and the
last byte, EOI-only success, live sound/dirty entry state, media message reset,
optional-load cancellation, normal title/Help/restart/EOF/missing-file paths,
all platform ownership assertions and make -j7 -O test. Renderer/shared modal
re-entry and platform loader/header/bank/span rows apply. RNG, representation,
monster state, visibility production, repeat commands and physical VDC layout
are N/A: those implementations are unchanged. No unresolved ownership choice;
real JiffyDOS/CBDOS timing remains a hardware test limitation.


Second-pass verification completed: build, HAL audit and all seven disk runtime
suites passed (C64 209/209, C128 139/139, Plus/4 44/44; Apple 25, X16 25,
Atari 16+5, BBC 17). Injected read/status and entry-state tests passed on all
three Commodores. X16 rejected $42 without committing or copying a byte;
Apple/Atari/BBC cancellation passed. PAL and NTSC cartridge persistence each
passed 10 checks. The tight C64 scripted build still ends at $BFFF.

The preceding full-gate run exposed a cartridge console-capture race:
`capture_console` could return from its stop-event wait without draining newly
readable PTY bytes. The maintainer explicitly authorized repairing this
infrastructure defect. Capture now latches the stop notification and drains
until the next empty read or EOF; shutdown adds no delay or timeout extension.
A deterministic regression reproduces the old lost-output path and covers both
stop-before-wait and stop-during-wait, with multiple final chunks. All 11
harness tests pass, including the existing real-child SIGKILL test.

Final gate: `make -j7 -O test` exited 0 on 2026-11-11. Each PAL/NTSC
cartridge run passed 27 runtime checks and 10 persistence checks; all 11
cartridge harness tests passed. The BBC item-actions scenario passed at its
unchanged 30-second limit. No test, timeout, memory boundary or player-facing
text was weakened.

Final contract review completes the applicable payload/link/header/load/bank/
source-span, shared modal re-entry, dirty/sound lifetime, missing-file, injected
read/status error and cancellation rows. Physical display layout, visibility
production, repeat, generation, RNG and save representation are N/A: those
implementations were unchanged. C128 still links/loads LEGALUI at Bank 0 $E000,
executes with $FF00=$3E, and refills Bank 0 $E700 from resident code at $2F7E.
All modal payloads remain below their snapshot at base+$600; the updated table
above records emitted spans. C64 resident remains $BF7A; its scripted Detect
Evil variant fits at $BFFF. Atari Default remains $C0DB and RuntimeBanked ends
at $FF7F; C128 Help still ends at $EFDE.

The reviewed diff contains only the requested repairs, tests and contract
records. Generated outputs and runtime evidence remain under build/; no
generated PRG, symbol, monitor or bytecode artifacts remain in source trees.
Changes are uncommitted.


## Cold-overlay cancellation repair (Pass 3)

Problem/success: cancelling optional LEGALUI must return without requiring the
program disk for HELP or TITLE, and retry prompts must not replace the caller
ZP snapshot. The earlier tests removed only LEGALUI while leaving other cold
assets readable; the new cases mount an actual save disk on the program drive.

State/owners: one 142-byte snapshot at base+$600, written once before the first
attempt. It may overwrite the previous overlay, so current_overlay stays
invalidated even after cancellation. The loader, prompt and controller all
execute outside that window. A successful load tail-calls legal_viewer (C=0);
Escape restores ZP after the prompt and returns C=1. Help cancellation exits
through the existing gameplay redraw; title cancellation clears the display
and draws the resident menu without TitleOverlay, art or sysinfo loading.
There is no backup allocation, new bank, cache owner or persistent state.

Search/readers/writers: three platform legal entries, title A dispatches,
shared ui_help_command, LegalSnapshot/LegalRestore, asset retry/prompt code,
ui_restore and the three MAME legal scenarios. The optional return capability
lives in the three early lifecycle policies; other ports compile their existing
Help path unchanged. Snapshot bytes survive retries because LEGALUI payloads
end before +$600 and the resident prompt loads no overlay. Sound and dirty
retain their established live-state exceptions on restore. Counts remain
unsigned bytes; carry is the completion/cancellation result. RNG and save
representation are N/A: neither changes.

Required tests: cold-title cancellation with the program disk absent, Help
cancellation to gameplay without disk access, repeated failed attempts retaining
the original snapshot, and caller ZP inspection at the cancel-return boundary.
Retain normal viewer/restart/EOF/error tests, boundary assertions and full gate.
BBC input observation now installs a tap only during each key-readiness wait,
short-circuits after the first poll and removes it before injecting input;
there is no idle tap or timeout extension. Its API is documented in
[MAME Lua memory handlers](https://docs.mamedev.org/luascript/ref-mem.html#pass-through-handler).
C128 also runs the shared scripted-breakpoint harness tests. The cartridge
PHONY entries already existed. Multi-emulator Make targets retain independent
30-second deadlines per emulator, not an overall target deadline.

Unresolved questions: none. Physical display-layout, monster, generation,
visibility-production and repeat contracts are N/A: their code is unchanged.


Pass 3 focused evidence: Apple IIe and both Atari configurations pass the new
save-disk cancellation, failed/successful retry and final-ZP-write observer
checks. The BBC fixture must wait for WD1770 motor-off (status $FE28 bit 7)
before changing media. An immediate hot swap reused DFS's program catalogue,
loaded blank save-disk sectors as LEGALUI and BRKed at $A800; waiting for the
actual motor-off state makes the same 31-assertion cancellation case pass.
This is an observed hardware-state precondition, not an added fixed sleep or
a relaxed test deadline. BBC key observation has no tap installed during that
wait. Register mapping and status masks follow the
[MAME Master driver](https://github.com/mamedev/mame/blob/master/src/mame/acorn/bbcm.cpp)
and [WD1770 controller implementation](https://github.com/mamedev/mame/blob/master/src/devices/machine/wd_fdc.h).
The separate BBC save/load regression also passed after the tap change.


Pass 3 verification completed: `make -j7 -O test` exited 0 on 2026-11-11.
C64 passed 209/209, C128 139/139, Plus/4 44/44; Apple IIe 25 scenarios,
X16 25, Atari 16+5, and BBC 17. Cancellation/retry/ZP observers pass on Apple,
800XL, 130XE and BBC; each Atari/BBC Help case contains 31 assertions. The
parallel BBC item-actions case also passes 31 assertions with the transient
tap. Each PAL/NTSC cartridge run passed 27 runtime and 10 persistence checks;
all 11 cartridge harness tests passed. Timeout limits and success criteria
were retained.

Applicable final contract rows are complete: linked bounds/headers and execution
owners, modal return before movement, failed and successful retry with an
immutable caller snapshot, live sound/redraw exceptions, and Escape with the
program disk absent. Current resident ends are Apple $7B0B, Atari $C0E6
(26 bytes free, RuntimeBanked $FF7F), BBC $7F9E; all existing assertions pass.
C64/C128/Plus4/X16 compile their existing Help return path because the new
optional-cancel capability is defined only for Apple/Atari/BBC. No cache,
map, platform-ZP, save encoding or bank allocation changes were introduced.
No generated artifacts remain in source directories; the diff is reviewed
and uncommitted.


## Paging and shortcut repair (2026-11-12)

Routine repair under the screen HAL's full-clear contract: every one of the
1,000 visible C64/Plus4 character and attribute cells must belong to the new
page. The old signed tail loop stopped after one byte because X started at
231. A pre-decrement, zero-terminated loop covers indices 231 through 0 with
no code-size growth. Required regression: poison the tail, enter/restart/advance
real disk and ROM document pages, and inspect all visible cells before drawing.
The cartridge regression failed on the old production code with stale text.

Maintainer chose `A)bout` on Title; Load retains L and Help retains L for the
reader. Help's header hint and an explicit second-page `L License / Source`
entry must be rendered and tested. The entry uses existing blank rows/columns in
both Help data layouts, within each existing overlay and cache slot; it owns
no resident state. Existing dispatch, load headers, bank ownership and copy
paths remain. C128 Help still loads and executes in Bank 0 at $E000; no VDC
register access changes. RNG, turns, persistence, MMU/interrupt protocols and
new copy sources are N/A because only bounded clear loops, menu keys and Help
text change. No unresolved behavior or ownership questions remain.

The Apple IIe, CX16 and BBC Makefiles now explicitly depend on the imported
`ui_help_data_80.s`; dry-run checks with that prerequisite marked newer schedule
all three assemblers. Fresh overlays contain the entry in a visible row/column.
Focused CX16 Help passed 21 assertions. The combined gate passed the disk
viewer tests on C64/C128/Plus4 and the Apple/Atari/CX16 Help scenarios; BBC Help
passed 33 assertions. Full verification remains blocked: two `make -j7 -O test`
runs hit the existing 30-second watchdog in BBC `save_load` after load-slot
selection, while a focused isolated run passed all eight assertions. No timeout,
assertion or scenario was weakened. The full gate has not passed for this repair.
