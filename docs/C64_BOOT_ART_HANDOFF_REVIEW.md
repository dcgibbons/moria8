# C64 Boot-Art Handoff Design Review

## Revision 5 Independent Review (2026-09-16)

- **Design reviewed:** Revision 5 of `docs/C64_BOOT_ART_HANDOFF_DESIGN.md`
- **Verdict:** **APPROVED**
- **Implementation clearance:** Implementation may proceed. No unresolved
  safety, memory-ownership, control-flow, device-ownership, or observable-
  behavior decision remains in the design.

The approval is for the specified design and its non-weakenable assertions and
verification plan. It is not evidence that the future implementation already
fits or passes its runtime gates.

### Revision 4 Blocker Resolution

#### 1. `$0340-$038C` terminal-error trampoline: resolved

The proposed trampoline is executable and survives every operation that needs
it:

- Its instruction stream is exactly 74 bytes. Counting zero-page encodings for
  `$01` and `$9D`, absolute encodings for `$D011/$D016/$D018/$D020/$D021`, the
  three destination-state references, `JSR $E544`, and `JMP ($A002)` places the
  first state byte at `$0340+74=$038A`. Three state bytes occupy
  `$038A-$038C`; exclusive end is `$038D`; total size is 77 bytes
  (`C64_BOOT_ART_HANDOFF_DESIGN.md:194-252`).
- The copy loop is exactly 11 bytes (`LDX #77`, absolute-indexed load/store,
  `DEX`, `BNE`) and the absolute saved-`MSGFLG` patch is six bytes. The embedded
  object plus setup therefore adds the claimed 94 boot-image bytes: 77+11+6
  (`C64_BOOT_ART_HANDOFF_DESIGN.md:253-260`).
- `$0340-$038C` is inside the later `$033C-$03FF` dungeon scratch owner
  (`platforms/commodore/c64/memory.s:48-49`) but is a valid boot-phase overlay:
  the game has not entered and terminal error never enters it. It is disjoint
  from handoff state `$0334-$033B`, KRES64 `$0400-$04ED`, and chain
  `$0500-$07FF` (`C64_BOOT_ART_HANDOFF_DESIGN.md:139-158,283-288`).
- Krill install may overwrite `$0200-$03FF`, so Revision 5 correctly delays the
  destination copy until installer return or the skipped-install path and until
  the BOOTART64 transaction finishes. The embedded source remains below `$2000`
  until MORIA64 overwrites `$0801+` (`C64_BOOT_ART_HANDOFF_DESIGN.md:262-270`;
  `tools/krill/loader/README:178-181`). The current product already executes its
  complete chain and filenames from `$0340-$03FA` across KERNAL MORIA64 LOAD
  (`platforms/commodore/c64/boot.s:395-519`); Revision 5 additionally requires
  canaries across every later LOAD.
- All terminal chain callers use `JMP $0340` only after their preserving helper
  restores LOAD's A/P. `PHA; PHP` captures that state before `SEI`; the two
  `PLA`s balance those pushes and store exact evidence at `$038B/$038C`.
  `LDX #$FF; TXS` intentionally discards obsolete chain/helper frames before
  the trampoline's sole `JSR $E544`. Page-one stack RAM is outside the clear,
  so `$E544` returns with SP normalized and no execution resumes in erased
  `$0500-$07E7` bytes (`C64_BOOT_ART_HANDOFF_DESIGN.md:196-246,272-281`).
- Before the clear, `$01=$37` makes KERNAL/BASIC/I/O and ROM vectors visible
  while low RAM `$0340` remains executable. Thus an NMI before that store uses
  the intact copied-chain handler; after it, ROM owns the vectors before the
  chain handler is erased. IRQs remain masked until `$E544` returns. The
  trampoline restores `MSGFLG`, clears while blank, enables only the clean text
  screen, clears decimal mode, enables IRQs, and jumps rather than returns to
  BASIC warm start (`C64_BOOT_ART_HANDOFF_DESIGN.md:203-245,392-416`).

The required base, instruction size, state addresses, total size, end,
copy-count, patch-target, source-end, and disjointness assertions are complete
(`C64_BOOT_ART_HANDOFF_DESIGN.md:625-634`).

#### 2. KINST64 and KERNAL BOOTART64 failure coverage: resolved

Revision 5 applies the same `PHP; PHA; CLOSE; CLRCHN; PLA; PLP` contract to a
named boot helper and explicitly identifies both real `$FFD5` call sites
(`C64_BOOT_ART_HANDOFF_DESIGN.md:461-500`). Separate injected scenarios now
require:

- KINST64 failure: exact distinct A/full P captured immediately, logical file 2
  absent, default channels restored, magic/family clear, installer skipped, and
  control reaching the KERNAL BOOTART64 attempt;
- KERNAL BOOTART64 failure: independently captured A/full P and cleanup,
  `$033A.0` clear, no display copy/CRC setup, and continuation through trampoline
  and chain copying to MORIA64.

Static checks must enumerate these two boot continuations, ordinary/recovery
MORIA64, ordinary/recovery `64.INIT`, and P6 `64.BANK`; each distinct production
continuation executes once, and success paths also prove cleanup
(`C64_BOOT_ART_HANDOFF_DESIGN.md:521-550,649-654,672-704`). This closes the
Revision 4 coverage gap without relying on eventual title entry.

### Prior-Finding Audit

All prior findings remain resolved:

1. The complete chain remains at `$0500-$07FF` with a fixed 768-byte budget,
   component ceilings, 16-bit copier, and hard end assertion. The 77-byte error
   trampoline is separate and does not revive the rejected `$0340` chain.
2. Every KERNAL LOAD result uses A/full-P-preserving `CLOSE`/`CLRCHN` cleanup,
   with all seven continuations statically enumerated and injected as relevant.
3. Clean 238-byte KRES64 is embedded and copied to `$0400-$04ED` only after all
   installer message paths return.
4. Recovery blanks with `$D011=$0B` before uninstall or any VIC-bank/mode
   change, preventing a bank-0 bitmap flash.
5. Boot, chain, terminal, and runtime NMI ownership is continuous. The approved
   26-byte runtime handler plus 20-byte vector installer preserves the current
   46-byte `$BAA8-$BAD5` span, `kernal_load_safe=$BAD6`, and
   `program_end=$C000`.
6. KINST64 remains correctly owned at `$2000-$3B53` for 6996 content bytes.
7. Captured device `$033B` is adopted after session reset and before P6; both
   Krill and fallback device-9 paths are required.
8. Full bitmap, matrix, and color CRCs plus all load/failure/message/NMI paths
   provide production-path integrity evidence.
9. Intervening writes are proved disjoint; vendor ZP prerequisites remain
   explicitly incomplete; waits remain empirical; and `$D000` write and timing
   claims remain correctly narrowed.
10. Shipping D64, dist, and ZIP inventories and byte identity are explicitly
    checked; `64.INIT` remains an asserted 875-byte PRG with `$00,$C0` header,
    873-byte content, and collision-check membership.
11. Complete unmodified Krill warning/error display is the user's settled
    behavior; KERNAL status text alone remains suppressed.

### Implementation-Time Measurements

These are mandatory implementation gates, not unresolved design decisions:

- report exact assembled chain usage; each component must remain within its
  section 4.1 ceiling and the total must end at or below `$0800`;
- assemble the terminal trampoline to exactly 74 instruction bytes and 77 total
  bytes at `$0340-$038C`, with state at `$038A-$038C`, an immediate copy count
  of 77, and the patch targeting destination `$038A`;
- report the revised boot embedded-source end and assert it remains below
  `$2000`; the trampoline object/copy/patch contribution must be exactly 94
  bytes and all source/destination spans must remain disjoint;
- assemble the runtime NMI handler/vector installer to exactly 26/20 bytes,
  retain their 46-byte combined span, leave `kernal_load_safe=$BAD6`, and keep
  `program_end=$C000`;
- verify all generated PRG headers, lengths, linked spans, and boundary
  assertions for MORIA64, `64.INIT`, `64.BANK`, BOOTART64, KINST64, and KRES64;
- prove all seven KERNAL LOAD continuations route through their named preserving
  helpers and execute the required success/failure evidence;
- require one byte-identical `64.INIT` in D64, dist, and ZIP, retain license and
  source-offer files, and keep the filename hash set collision-free;
- run every specified device-9, CRC, installer-message, recovery, trampoline,
  NMI/vector, and KERNAL/Krill failure scenario through production paths, then
  pass the exact authoritative `make test64` gate;
- retain bounded per-scenario emulator timeouts and re-derive the empirical
  18/150-frame waits if supported-drive evidence disproves them.

---

## Revision 4 Independent Review (2026-09-16)

- **Design reviewed:** Revision 4 of `docs/C64_BOOT_ART_HANDOFF_DESIGN.md`
- **Verdict:** **REVISION REQUIRED - NOT APPROVED**
- **Implementation clearance:** **BLOCKED**. Revision 4 resolves all four
  Revision 3 decisions in principle, but its chain error transition is not
  executable as specified and its KERNAL failure matrix is not yet complete.

The user's choice to show the complete, unmodified Krill 1541U warning and
failed-mute-device error is settled. It is not an open behavior question.

### Blocking Findings

#### 1. The chain-resident clean-error transition erases itself before warm start

Revision 4 requires ordinary fallback MORIA64 failure to blank, restore
`MSGFLG`, clear `$0400-$07E7`, enable clean text, and then reach BASIC warm
start (`C64_BOOT_ART_HANDOFF_DESIGN.md:397-419`, especially line 409). The same
clean transition is required for ordinary/recovery `64.INIT` failure
(`C64_BOOT_ART_HANDOFF_DESIGN.md:410-412,552-555`). At those points execution
is still in the copied chain at `$0500-$07FF`. The current architecture confirms
that the chain owns this address until it jumps to `$080E`
(`platforms/commodore/c64/boot.s:397-516`), and Revision 4 itself states that
`$E544` clears `$0500-$07E7` (`C64_BOOT_ART_HANDOFF_DESIGN.md:178-183,295-297`).

A normal `JSR $E544` therefore overwrites the caller's next instructions before
returning. Blanking prevents visible corruption but does not preserve execution.
No surviving error trampoline, tail-call contract, or owner outside the clear
span is allocated. The warm-start transition is consequently unsafe as written.

Required revision: specify an exact surviving execution route for chain-stage
errors. For example, allocate and budget a trampoline outside `$0400-$07E7`
that performs or returns from the clear and then restores presentation/state and
enters warm start. Prove its source/destination survival, stack behavior,
`MSGFLG` restoration, NMI-vector ownership, and non-overlap. Alternatively,
select a different clean-error transition that never resumes in erased chain
bytes. This is a memory-ownership and control-flow decision, not an
implementation measurement.

#### 2. Injected KERNAL failure coverage still omits boot-stage LOAD call sites

Revision 4 correctly adds distinct ordinary/recovery MORIA64, ordinary/recovery
`64.INIT`, and P6 `64.BANK` failure injections
(`C64_BOOT_ART_HANDOFF_DESIGN.md:397-419,541-565`). It also retains the stronger
contract that **every** boot KERNAL LOAD preserves A/P and performs
`CLOSE`/`CLRCHN` on both outcomes (`C64_BOOT_ART_HANDOFF_DESIGN.md:38-39,356-366`).

The matrix does not explicitly inject or capture A/P and file-table/channel
state for:

- KINST64 KERNAL LOAD failure before install (`C64_BOOT_ART_HANDOFF_DESIGN.md:191-204,309-310`);
- KERNAL BOOTART64 LOAD failure on the missing-art fallback path
  (`C64_BOOT_ART_HANDOFF_DESIGN.md:311-312,548`).

Those failures are nonterminal and transition into later loads, so reaching the
title is not proof that returned A/full P survived cleanup. The current wrappers
only preserve carry, not A (`platforms/commodore/c64/boot.s:127-136,309-316`),
which is exactly the implementation being changed.

Required revision: add real-call-site failure injections for KINST64 and KERNAL
BOOTART64, with the same immediate A/P capture, logical-file absence, default
channel, and named continuation evidence required by section 7.4. If all boot
LOADs use one helper, static call-site proof is still required and each distinct
boot continuation must execute once.

### Revision 3 Blocker Audit

The prior four blockers are otherwise resolved:

1. **Runtime NMI semantics and placement: resolved.** The current handler is
   exactly 16 bytes at `$BAA8-$BAB7`; the current installer is exactly 30 bytes
   at `$BAB8-$BAD5`; `kernal_load_safe` begins at `$BAD6`; and
   `program_end=$C000`. These addresses were reconfirmed by static
   `make -C platforms/commodore build64` symbols. The proposed sequence uses
   zero-page encodings for `$01` and is exactly 26 bytes. The proposed
   `PHP; SEI`, four absolute vector stores, `PLP; RTS` installer is exactly 20
   bytes. The resulting `$BAA8-$BAC1` and `$BAC2-$BAD5` spans preserve every
   following address and the full resident boundary. Writing `$FFFA-$FFFF`
   reaches underlying RAM while KERNAL ROM is selected, and the first install
   occurs under `$36`, so partial writes cannot redirect an NMI. The handler
   preserves A, X, Y, P, stack balance, and interrupted `$01`, exposes I/O with
   `$35`, acknowledges CIA1/CIA2/VIC, and remains visible at `$BAA8` whenever
   HIRAM is clear (`C64_BOOT_ART_HANDOFF_DESIGN.md:222-303`;
   `platforms/commodore/c64/main.s:1096-1126`).
2. **Main/chain/P6 KERNAL failure transitions: resolved except for Finding 2.**
   Revision 4 now distinguishes the five requested MORIA64/`64.INIT`/`64.BANK`
   transitions and requires success-path cleanup too
   (`C64_BOOT_ART_HANDOFF_DESIGN.md:397-419,546-555`).
3. **Shipping proof: resolved.** `64.INIT` is required as a build dependency,
   explicit dist/ZIP copy, explicit D64 write, and collision-list member
   (`C64_BOOT_ART_HANDOFF_DESIGN.md:507-519`). `make disk64`, D64 extraction,
   dist and ZIP byte comparisons, unique inventory checks, 875-byte PRG size,
   `$00,$C0` header, and 873-byte content checks are all explicit
   (`C64_BOOT_ART_HANDOFF_DESIGN.md:521-539`). Independent evaluation of the
   current hash function gives `64.INIT = $1D,$D7` with no collision among the
   existing 32 names (`tools/check_krill_filenames.py:29-83`).
4. **Installer-message behavior: resolved.** The user selected complete,
   unmodified visible diagnostics. Revision 4 suppresses only KERNAL LOAD
   status text, allows direct-BSOUT vendor diagnostics, reblanks immediately,
   and copies clean KRES64 only after successful install
   (`C64_BOOT_ART_HANDOFF_DESIGN.md:185-220`). This matches the vendor paths at
   `tools/krill/loader/src/install.s:447-463,719-865,1351-1381`.

### Original Nine-Finding Audit

All nine final `moria8-x6t.1.2` findings remain resolved in the design:

1. `$0340` overflow: fixed `$0500-$07FF` owner, 768-byte hard limit, component
   ceilings, and 16-bit copier.
2. KERNAL cleanup/carry: universal A/P-preserving `CLOSE`/`CLRCHN` contract;
   Finding 2 requires the last two boot-stage injections.
3. Installer/KRES64 corruption: clean embedded 238-byte resident copied only
   after installer messages.
4. Recovery flash: `$D011=$0B` precedes uninstall and VIC-bank/mode changes.
5. RESTORE/NMI: exact boot/chain/runtime vector ownership and a valid 26-byte
   context-preserving handler; the linked runtime replacement is size-neutral.
6. KINST64 span: `$2000-$3B53`, 6996 content bytes.
7. Device ownership: `$033B` is adopted after session reset and before P6;
   device-9 Krill and fallback production scenarios are required.
8. Integrity/failures: full bitmap/matrix/color CRCs and distinct payload
   failure paths are retained.
9. Overclaims: intervening writes are proved disjoint, incomplete vendor ZP
   prerequisites remain explicit, waits remain empirical, and `$D000`/timing
   claims are correctly narrowed.

### Implementation Measurements, Not Blockers

Once Findings 1-2 are designed, these remain implementation-time gates rather
than open decisions:

- exact assembled chain usage must fit the fixed 768-byte allocation and every
  component ceiling;
- the assembled runtime NMI handler/installer must be exactly 26/20 bytes,
  retain their 46-byte combined span, leave `kernal_load_safe=$BAD6`, and keep
  `program_end=$C000`;
- generated MORIA64, `64.INIT`, `64.BANK`, BOOTART64, KINST64, and KRES64
  headers/spans must match the asserted values;
- generated D64, dist, and ZIP copies of `64.INIT` must be unique and
  byte-identical, and the filename checker must remain collision-free;
- device-9, NMI, CRC, installer-message, and all injected failure scenarios
  must execute through production paths, followed by the exact `make test64`
  gate;
- empirical 18/150-frame waits remain subject to runtime evidence and must be
  re-derived if a supported drive scenario disproves them.

Implementation may not proceed until the two blocking findings are incorporated
into the design and re-reviewed.

---

## Revision 3 Independent Review (2026-09-16)

- **Design reviewed:** Revision 3 of `docs/C64_BOOT_ART_HANDOFF_DESIGN.md`
- **Review basis:** current repository sources, the full Krill r194 README and
  interfaces, and the final nine-finding comment on `moria8-x6t.1.2`
- **Verdict:** **REVISION REQUIRED - NOT APPROVED**
- **Implementation clearance:** **BLOCKED**. The display layout is viable, but
  unresolved NMI layout/behavior and verification decisions remain.

This review supersedes the Revision 1 approval conclusions archived below. In
particular, the Revision 1 `$E400` staging/header-patch design is obsolete and
must not be implemented.

### Findings

#### 1. BLOCKER: the runtime NMI claim is false, and its target-location rule conflicts with the linked image

Revision 3 says the copied-chain handler is equivalent to the runtime handler
and that installing the runtime vectors closes the final unsafe interval
(`C64_BOOT_ART_HANDOFF_DESIGN.md:198-216`). It also requires both boot and
runtime NMI targets to be below `$A000` (`C64_BOOT_ART_HANDOFF_DESIGN.md:385-386`).
Neither claim matches the current product:

- `c64_irq_hidden_rom` reads `$DC0D`, `$DD0D`, and `$D019` without saving,
  changing, or restoring `$01` (`platforms/commodore/c64/main.s:1096-1108`).
  Under `$01=$30` or `$34`, those addresses do not expose CIA/VIC I/O, so the
  handler does not acknowledge the hardware source. The proposed boot/chain
  handler, which temporarily selects `$35`, is materially different.
- `c64_install_ram_irq_vectors` points both RAM vectors at that handler
  (`platforms/commodore/c64/main.s:1110-1126`).
- A static `make -C platforms/commodore build64` linked
  `c64_irq_hidden_rom=$BAA8`, not below `$A000`, while `program_end=$C000`.
  The latter also means expanding or relocating the runtime handler has a real
  resident-byte/layout cost; there is no unallocated tail below `MAP_BASE`.

Required revision: choose and prove the runtime NMI target and semantics. Either
make the runtime handler preserve `$01`, select I/O while acknowledging the
source, restore `$01`, and budget any added resident bytes, or narrow the
claimed protected configurations with source-backed proof. Replace the false
`<$A000` rule with the actual visibility/survival invariant, or identify a
specific below-`$A000` owner and prove the move. Add production-path RESTORE/NMI
coverage for every supported hidden-ROM/I/O configuration, including `$30` and
`$34` if they remain supported.

#### 2. BLOCKER: the proposed tests do not verify every claimed KERNAL LOAD outcome

The design requires every boot KERNAL LOAD, on both carry outcomes, to close
logical file 2, clear channels, and preserve returned A/P
(`C64_BOOT_ART_HANDOFF_DESIGN.md:269-286`). The sequence itself is sound:
`PHP; PHA; ...; PLA; PLP` restores A and P after `CLOSE`/`CLRCHN`. The current
code demonstrates why cleanup is needed (`platforms/commodore/c64/boot.s:127-136`)
but does not preserve A, and the current P6 path changes interrupt state before
restoring P and does not preserve A (`platforms/commodore/c64/main.s:2649-2663`).

The Revision 3 matrix injects only KERNAL `64.INIT` failure
(`C64_BOOT_ART_HANDOFF_DESIGN.md:403-418`). It does not inject ordinary-fallback
MORIA64 failure, recovery-path MORIA64 failure, or P6 KERNAL `64.BANK` failure.
Those are distinct transitions and include the exact status-preservation code
the success criteria claim for all outcomes.

Required revision: add production-path failure scenarios for each distinct
KERNAL wrapper/transition, at minimum ordinary MORIA64 and P6 `64.BANK`, plus
the recovery wrapper if it is not literally shared. Assert file-table/channel
cleanup and captured A/P before the selected error transition. A shared wrapper
may reduce the scenario count only if the test proves every caller dispatches
through that same production routine.

#### 3. BLOCKER: shipping-package verification does not prove `64.INIT` is present

Revision 3 requires `64.INIT` in every C64 disk recipe
(`C64_BOOT_ART_HANDOFF_DESIGN.md:389-390`), but its static plan runs only
`make build`, the filename checker, and symbol inspection
(`C64_BOOT_ART_HANDOFF_DESIGN.md:392-401`). `make build` does not execute the
C64 distribution or disk recipes. The current shipping D64 and loose archive
recipes independently enumerate files (`platforms/commodore/Makefile:484-517`
and `523-562`), and the current collision list does not contain `64.INIT`
(`tools/check_krill_filenames.py:29-44`). Updating only the build artifact or
test disks could therefore pass the proposed checks while shipping without the
required file.

Required revision: add `make disk64` or equivalent static recipe/inventory
checks that prove the generated D64 and loose-file ZIP/dist each contain the
true-address `64.INIT`; verify its `$00,$C0` header and 873-byte content in the
packaged copies; and require `64.INIT` in the filename-collision set.

#### 4. BLOCKER: visible installer-message behavior is explicitly unresolved

Section 14 says review must decide whether the visible 1541U warning and
failed-mute error are acceptable presentation
(`C64_BOOT_ART_HANDOFF_DESIGN.md:439-445`). This review has no maintainer
authority to create that product decision. The messages are real: the 1541U
path invokes `message` and can then return success
(`tools/krill/loader/src/install.s:719-733`), while `message` enables `$0400`
text output and calls `BSOUT` (`install.s:735-865`); the mute failure invokes
the same renderer (`install.s:447-463`). The repository also forbids degrading
player-visible text merely to recover bytes (`AGENTS.md:32-35` and
`docs/INTERNAL_MANDATES.md:15-23`).

Required decision: the maintainer must explicitly select visible vendor
warning/error output, or specify a different presentation without shortening
or silently suppressing player-visible text. Until then, Revision 3's own
architectural record has unresolved observable behavior, which blocks
implementation under `docs/BEHAVIOR_CHANGE_PROTOCOL.md:99-101`.

### Verified Revision 3 Claims

The following points were independently checked and are not blockers:

- The selected live spans are mutually compatible: bitmap `$C000-$DF3F`
  (8000), matrix `$E000-$E3E7` (1000), color `$D800-$DBE7` (1000), and
  `64.BANK` `$F000-$FFF7` (4088 content bytes). `$DD00=$00` and `$D018=$80`
  select VIC bank 3, matrix offset `$2000`, and bitmap offset `$0000`.
- The static build produced main content `$0801-$C368`,
  `program_end=$C000`, and RuntimeBanked `$F000-$FFF7`. Therefore the proposed
  split is arithmetically exact: MORIA64 `$0801-$BFFF` is 47103 content bytes
  and `64.INIT` `$C000-$C368` is 873 content bytes.
- BOOTART64 is 10002 bytes including its `$A000` PRG header, so its 10000-byte
  content ends at `$C70F`. Color `$C328-$C70F`, matrix `$BF40-$C327`, then
  bitmap `$A000-$BF3F` is the required source-safe copy order when the bitmap
  destination begins at `$C000`.
- KINST64 is 6998 bytes including its `$2000` header: 6996 content bytes end at
  `$3B53`. KRES64 is 240 bytes including its `$0400` header: 238 content bytes
  occupy `$0400-$04ED`, with `loadraw=$0400` and `uninstall=$04E1`. These agree
  with the generated/current runtime constants (`platforms/commodore/c64/main.s:38-50`
  and `config.s:104-116`).
- Embedding clean KRES64 bytes in boot and copying them only after install
  returns follows Krill's explicit below-`$0400` rule
  (`tools/krill/loader/README:172-184`) and prevents installer messages from
  corrupting executable resident bytes. The source must remain asserted below
  `$2000`, before KINST64's destination.
- `$0500-$07FF` is exactly 768 bytes and is disjoint from KRES64, MORIA64, and
  all payload destinations. It is screen/dungeon scratch
  (`platforms/commodore/c64/memory.s:43-49,155-157`), but it survives until
  `entry_main` reaches the intentional `$E544` clear
  (`platforms/commodore/c64/main.s:678-687,2605-2615`). The proposed 16-bit
  copier and non-weakenable end assertion are necessary. The exact assembled
  usage remains a valid implementation-time measurement, not permission to
  move the boundary.
- Writing `$D011=$0B` before uninstall or `$DD00` changes resolves the prior
  bank-0 bitmap flash. The recovery path correctly treats uninstall outputs as
  undefined, matching `tools/krill/loader/include/loader.inc:398-405`.
- Capturing device 8-30 in `$033B` is compatible with the `$033C` scratch
  boundary (`platforms/commodore/c64/memory.s:48-49`; `config.s:91-102`).
  Explicitly assigning it to `program_device` after
  `disk_reset_session_state` and before `init_load_banked` resolves the current
  device-8 default (`platforms/commodore/common/disk_swap.s:117-180` and
  `main.s:678-687,2637-2652`). Device-9 production tests remain required.
- Krill's host contract is represented accurately: install needs KERNAL ROM and
  additional incompletely documented KERNAL ZP state (`README:172-184`);
  `loadraw` takes X/Y filename, reports carry/A, and with `LOAD_TO_API=0` obeys
  the PRG header (`loader.inc:196-212`; `platforms/commodore/c64/krill/loaderconfig.inc:22-31`);
  active-load ZP is `$E0-$E4`; legal installed `$DD00` writes are literal 0-3
  (`README:249-283`); and r194 supplies no 18/150-frame timing guarantee
  (`README:526-533`).
- The CRC checkpoints cover every byte of bitmap and matrix and the meaningful
  low nibble of color RAM. Keeping `$FB-$FE` use to loader-idle intervals is
  compatible with Krill's active-load ownership.

### Unresolved Questions

1. What exact runtime NMI handler/address and resident-byte source will satisfy
   all supported `$01` configurations?
2. Are the vendor 1541U warning and failed-mute error intentionally visible in
   the shipped boot experience?
3. Will all KERNAL boot loads share one result-preserving cleanup routine, or
   must each distinct implementation receive its own failure injection?

Implementation may not safely proceed until these questions and Findings 1-4
are incorporated into a revised design and re-reviewed.

---

## Archived Revision 1 Review (Superseded)

The material below is retained as review history only. Its approval verdict,
`$E400` staging, tail-copy loop, and PRG-header patch do not apply to Revision 3.

# C64 Boot-Art Handoff Design Review (mr_spock)

- **Task:** `moria8-x6t.1.2` (Review visible C64 boot-art handoff design)
- **Parent:** `moria8-x6t.1` (Boot: install Krill before bootart, fast-load BOOTART64)
- **Design under review:** `docs/C64_BOOT_ART_HANDOFF_DESIGN.md` (by `captain_kirk`, `moria8-x6t.1.1`)
- **Reviewer:** `mr_spock` (`BEADS_ACTOR=mr_spock`)
- **Verdict:** **APPROVED WITH REQUIRED REVISIONS**. Implementation may proceed once the five concrete requirements in Section 3 are addressed.

---

## 1. Executive Summary & Architecture Evaluation

The proposed architecture solves the root cause of the C64 boot-art corruption bug cleanly and decisively:

1. **Root cause analysis confirmed:** In the existing tree, `64.BANK` is 4090 bytes (`$F000-$FFF7` including its 2-byte header, content span 4088 bytes) and collides directly with the live boot bitmap at `$E000-$FF3F` (`$F000-$FF3F`, 3904 bytes). Blanking before `64.BANK` was an incomplete symptom fix that violated the goal of maintaining visible boot art throughout all disk loading.
2. **Structural solution verified:** Shifting the bitmap to `$C000-$DF3F` (VIC Bank 3 offset `$0000`) and the screen matrix to `$E000-$E3E7` (VIC Bank 3 offset `$2000`) completely decouples the live display from `$F000-$FFF7`.
3. **Init-tail split mathematically proven:** `MORIA64` is split cleanly at `program_end == MAP_BASE` into `moria64` (`$0801-$BFFF`, 47103 bytes) and `64.init` (`$C000-$C368`, 873 bytes). `64.init` is assembled and linked at its true execution address `$C000-$C368`, staged on-disk at `$E400-$E768` (24 bytes above the screen matrix end at `$E3E7`, and 2200 bytes below `64.BANK` at `$F000`), and copied to `$C000` by the chain stub during the final ~15 ms blanked transition to text mode.
4. **Zero live-display overlap:** There is zero byte intersection between any disk write span and any live display span across all phases (P0–P6).

---

## 2. Verification of Contract & Source Evidence

All citations and technical claims in `docs/C64_BOOT_ART_HANDOFF_DESIGN.md` were independently checked against the repository source code, vendored loader documentation, and Commodore 64 hardware architecture:

| Claim / Citation | Source Reference | Audit Result | Notes |
| --- | --- | --- | --- |
| Krill install environment (`$01=$36/$37`) | `tools/krill/loader/README:173-174` | **Verified** | KERNAL must be enabled during install. |
| Krill install lowmem clobber (`$0200-$03FF`) | `tools/krill/loader/README:178-181` | **Verified** | Handoff bytes at `$0334-$033B` must be written after install; stub relocation to `$0500` isolates it completely. |
| Krill loadraw call & conventions | `tools/krill/loader/README:192-234` | **Verified** | Filenames are 0-terminated; carry flag indicates error. |
| Loader idle inertness | `tools/krill/loader/README:236-238` | **Verified** | Code at `$0400` is inert when idle; copying tail under `$01=$35` is legal; `$e544` screen clear in P6 is legal. |
| `$DD00` discipline | `tools/krill/loader/README:250-274` | **Verified** | Upper 6 bits must be 0; write `$00` or `$03` directly without RMW. |
| Loader ZP range | `tools/krill/loader/README:279-284` | **Verified** | `$E0-$E4` is reserved during loading; bootloader copy routines touch only `$FB-$FE`. |
| Loading to RAM under I/O | `tools/krill/loader/README:441-445` | **Verified** | `LOAD_UNDER_D000_DFFF=0` confirmed in `krill/loaderconfig.inc:23`. |
| Watchdog non-issue | `tools/krill/loader/README:526-533` | **Verified** | Loader runs without raster starvation. |
| VIC-II Bank 3 memory mapping | Hardware architecture | **Verified** | VIC reads system RAM for the full 16 KB (no Char ROM mirror in Bank 3). Bitmap at offset `$0000` (`$C000-$DF3F`) and Screen matrix at offset `$2000` (`$E000-$E3E7`) is configured by `$DD00=$00` and `$D018=$80`. |
| 6510 write-through to RAM under ROM | Hardware architecture | **Verified** | With `$01=$37`, writes to `$E400-$E768` (`64.INIT`) and `$F000-$FFF7` (`64.BANK`) write directly to underlying RAM. This matches existing `main.s:2638-2653` KERNAL LOAD behavior. |
| Phase 3 copy order | `platforms/commodore/c64/boot.s:26-31, 148-285` | **Verified** | `BOOTART64` stages at `$A000-$C70F` (color at `$C328-$C70F`, screen at `$BF40-$C327`, bitmap at `$A000-$BF3F`). Because the new bitmap destination `$C000-$DF3F` overlaps the staged color and screen areas, copy order **must** be Color -> Screen -> Bitmap. |
| Handoff byte `$033B` fit | `platforms/commodore/c64/config.s:91-102`, `memory.s:48` | **Verified** | Gap `$0334-$033B` is always-RAM; `$033C` is `DUNGEON_GEN_DOOR_SCAN_BASE`. `$033B < $033C` preserves all boundary contracts. |
| Init-tail survival until `title_load_and_draw` | `platforms/commodore/c64/main.s:678-778`, `title_screen.s:58-75` | **Verified** | All init-tail functions execute once before `T64` loads to `$C000-$CEFF`. No init-tail routines are ever re-entered. |

---

## 3. Concrete Required Revisions (Implementation Directives)

The following five items were identified as defects, unsafe assumptions, or omission risks in the design text and **must be corrected during implementation**:

### 1. Phase 5 Tail Copy Loop Must Support 873 Bytes (Multi-Page)
- **Defect in Design (§11):** Section 11 stated:
  > *"Copy loops use the existing count-down pattern (bne, not bpl — boot.s:101-104 lesson retained); tail size 873 ($369) exceeds 128, so the same rule applies to the P5 copy."*
- **Correction:** 873 bytes exceeds 256 bytes ($100). A single 8-bit index register countdown loop (`dex; bne`) wraps around at 256 and will copy only 105 bytes ($69), corrupting the game initialization.
- **Requirement:** The Phase 5 copy routine in `chain_stub` must use a multi-page copy routine. An unrolled 3-page loop plus tail (or a 16-bit pointer loop) must be used:
  ```assembly
      ldx #0
  !copy_pages:
      lda $e400,x
      sta $c000,x
      lda $e500,x
      sta $c100,x
      lda $e600,x
      sta $c200,x
      inx
      bne !copy_pages-
      ldx #0
  !copy_tail:
      lda $e700,x
      sta $c300,x
      inx
      cpx #$69        // 873 - 768 = 105 ($69)
      bne !copy_tail-
  ```

### 2. Bootloader Copier for `chain_stub` Must Support > 256 Bytes
- **Defect in Design (§4, §5.1):** The design relocates `chain_stub` to `$0500-$07FF` (budget ≤ 768 bytes). With three `loadraw` invocations, two 18-frame waits, 150-frame uninstall recovery, KERNAL loading for two files, the 873-byte tail copier, error handling, and three filenames, `chain_stub` will exceed 256 bytes (est. 280–320 bytes).
- **Correction:** The existing copy loop in `boot.s:104-109` (`ldx #chain_stub_end - chain_stub; ... dex; bne`) uses an 8-bit index and will fail at assembly time or truncate when `chain_stub_end - chain_stub > 256`.
- **Requirement:** `load_main_program` in `boot.s` must copy `chain_stub` using a multi-page copy loop (e.g., 2 unrolled pages or 16-bit pointer copy) with a boundary assertion guarding `$0500 + STUB_SIZE <= $0800`.

### 3. Explicit Display Blanking in Mid-Boot Failure Recovery (`!cs_fail`)
- **Defect in Design (§5.3):** In the existing tree, the display was already blanked before `64.BANK` was loaded. In the new design, the display remains in Bank 3 multicolor bitmap mode (`$D011=$3B`, `$DD00=$00`) during all three file loads. If any `loadraw` fails and jumps to `!cs_fail`, `!cs_fail` uninstalls the loader and writes `VIC_BANK0_SELECT` (`$03`) to `$DD00` while `$D011` is still `$3B`. This causes the VIC to display Bank 0 system RAM in bitmap mode for the 150-frame (3-second) drive reset settle, flashing severe screen garbage.
- **Requirement:** `!cs_fail` must explicitly blank the display (`lda #$0b; sta $d011`) **before** restoring `$DD00=$03`.

### 4. File Table Hygiene (`CLOSE` and `CLRCHN`) in KERNAL Fallback
- **Risk in Design (§5.2, §5.3):** When KERNAL fallback loads `MORIA64` and then `64.INIT`, KERNAL leaves the logical file active in the internal tables after `LOAD` finishes.
- **Requirement:** In `chain_stub`, after `MORIA64` is loaded via KERNAL LOAD, `chain_stub` must call `CLOSE` (`$FFC3`) and `CLRCHN` (`$FFCC`) on `LOGICAL_FILE` before issuing `SETNAM`/`SETLFS`/`LOAD` for `64.INIT`.

### 5. Idempotent Makefile Patching for `64.init` PRG Header
- **Risk in Design (§8.3, §10):** Patching the PRG load header of `64.init` from `$C000` to `$E400` must not break repeated or incremental `make` invocations.
- **Requirement:** The Makefile rule must patch idempotently (overwriting the first two bytes to `\x00\xE4` regardless of previous state, or using an intermediate target `64.init.raw -> 64.init`) and verify `p[:2] == bytes((0x00, 0xE4))` and `len(p) <= 0x402`.

---

## 4. Formal Responses to Open Questions (§12)

1. **Question 1 (Disk-layout change / `64.INIT`):** **APPROVED**. Staging `64.BANK` is physically impossible because no contiguous 4088-byte RAM block is free while the art is live. Staging the 873-byte `64.INIT` at `$E400-$E768` is mathematically sound and leaves ample margins.
2. **Question 2 (P5 ~15 ms blanked transition duration):** **APPROVED**. Blanking during the final memory relocation (~1 frame, no disk activity) avoids drawing raw binary data as screen pixels. It fully satisfies "visible throughout disk loading".
3. **Question 3 (Boot-time cost of third loadraw / settle):** **APPROVED**. An 18-frame settle (~0.36 s PAL, negligible under VICE warp) is safe and prevents 1541 directory desynchronization.
4. **Question 4 (Filename `64.INIT`):** **APPROVED**. Follows repository naming patterns (`64.START`, `64.BANK`, etc.) and is verified collision-free in `check_krill_filenames.py`.
5. **Question 5 (Evidence byte `$033B`):** **APPROVED**. Sampling `$D011` into `$033B` at P5 proves the bitmap display was active at handoff. Paired with reaching `.c64_test_fastload_pass_sym` (which requires `64.INIT` to have copied and executed), this provides rigorous proof without intrusive harness hooks.

---

## 5. Conclusion & Clearance

The design in `docs/C64_BOOT_ART_HANDOFF_DESIGN.md` satisfies all safety, memory-contract, and behavioral requirements.

**Implementation may proceed** under `moria8-x6t.1`, incorporating Revisions 1–5 specified above. No product code was changed during this review.
