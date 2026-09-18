# C64 Boot-Art Handoff Design: Bitmap Visible Through Main Fast Loads

Design for bead `moria8-x6t.1.1` (parent `moria8-x6t.1`). **Design only: no
product code is changed by this document.**

> **Revision 5 (2026-09-16):** retains the explicit user choice from Revision
> 2: bitmap `$C000-$DF3F`, matrix `$E000-$E3E7`, and a true-address
> `64.INIT` loaded last, directly to `$C000`, after blanking. There is no
> `64.INIT` staging, copy, or PRG-header patch. It also records the user's
> settled choice to show Krill's unmodified installer warning/error messages
> before boot art. This revision resolves the nine final Beads corrections and
> the four blockers in the independent Revision 3 review and the two blockers
> in the independent Revision 4 review.

`docs/C64_BOOT_ART_HANDOFF_REVIEW.md` begins with the authoritative Revision 4
rejection and retains earlier reviews as history. The final Beads comment on
`moria8-x6t.1.2` and the Revision 3/4 reviews govern Revision 5. A fresh review
is required before implementation proceeds.

## 1. Problem and success criteria

The current bitmap occupies `$E000-$FF3F`, while `64.BANK` writes
`$F000-$FFF7`. Blanking before that transfer prevents visible corruption but
removes the art during a principal fast load. The selected layout moves the
bitmap below the banked runtime and splits only the existing `$C000+` init tail
from MORIA64.

Success means:

- On the Krill path, art remains live through MORIA64 and `64.BANK`.
- On the KERNAL path, art remains live through MORIA64. Its existing P6
  `64.BANK` load remains post-art.
- `64.INIT` is an ordinary PRG linked and file-addressed at `$C000`; both paths
  blank first and load it last. No staging, copy, or header patch is permitted.
- No disk write intersects a display span while that span is live.
- The resident remains byte-clean despite all installer-visible messages.
- Krill's complete, unmodified 1541U warning and failed-mute-device error are
  intentionally visible before boot art; they are not suppressed or shortened.
- All KERNAL LOAD outcomes close logical file 2 and clear channels while
  preserving LOAD's returned A and status flags.
- Chain-stage terminal errors transfer to a surviving `$0340` trampoline before
  clearing `$0400-$07E7`; no instruction returns into erased chain bytes.
- RESTORE/NMI is safe whenever KERNAL ROM and hardware vectors are hidden.
- Device 8 through 30 ownership remains coherent from boot through the P6
  fallback load; device 9 receives production-path coverage.
- Shipping D64, loose `c64-dist`, and ZIP inventories each contain one
  byte-identical `64.INIT` PRG with header `$00,$C0` and 873 content bytes;
  `64.INIT` participates in Krill filename-hash collision checking.
- The authoritative implementation gate is `make test64`. Emulator scenarios
  retain individual bounded hang-detection timeouts; the whole-suite timeout
  must allow the authoritative gate to finish.

## 2. Architectural record

```text
Problem and success criteria:
  Section 1.
State being changed:
  C64 boot display ownership, boot artifact packaging, boot-resident install,
  chain execution location, and boot-device handoff. No gameplay state changes.
Search scope and terms:
  AGENTS.md; INTERNAL_MANDATES.md; BEHAVIOR_CHANGE_PROTOCOL.md;
  TURN_RENDER_CONTRACT.md; boot.s; main.s startup through title; memory.s;
  config.s; common/disk_swap.s; Commodore Makefile and C64 harness recipes;
  Krill r194 README, loader.inc, install.s, hal-c64-c128.inc, generated
  loadersymbols-c64.inc; both m8-x6t.1.2 comments and the obsolete review.
Relevant readers/writers found and known exclusions:
  Sections 4-9. Runtime map, floor-item, tier, overlay, and title owners begin
  only after the boot art is dead.
Initialization, reset and persistence points:
  $0334-$033B is the boot handoff. $033A carries art-load/integrity evidence;
  $033B carries the captured boot device. A terminal-error trampoline at
  $0340-$038C survives its own screen clear. The chain at $0500 is consumed by
  the first P6 or terminal-error screen clear. Runtime RAM vectors replace boot
  vectors before init-tail execution.
Affected production sequence through the changed transition:
  Sections 6 and 7, including install messages and all recovery branches.
Contract decision or selected upstream oracle with source locations:
  C64 hardware and current ownership assertions; Krill r194 sources cited in
  section 10; explicit user choices for true-address postblank 64.INIT and
  visible vendor diagnostics quoted above. VMS/Umoria do not govern platform
  boot mechanics.
Intentional Moria8 deviations:
  The 18-frame inter-load waits and 150-frame post-uninstall wait are retained
  repository workarounds, not Krill API requirements.
Input/intermediate widths, signedness, carry, range and overflow policy:
  Stub lengths and copies use 16-bit bounds. KERNAL LOAD cleanup preserves A
  and the complete returned P. CRC-16/CCITT-FALSE uses polynomial $1021,
  initial value $FFFF, no reflection, and no final XOR. Color RAM input is
  masked to its low nibble.
RNG reduction and bias, if applicable:
  N/A; no RNG behavior changes.
Affected platforms, overlays, banks and owners:
  C64 boot only. No runtime map, overlay, C128, Plus/4, or Apple IIe ownership
  changes.
Required production-path tests:
  Section 12, including every distinct KERNAL error transition, every supported
  hidden-ROM/I/O $01 state, and shipping-package inventories.
Known behavior explicitly out of scope:
  Loader throughput optimization and replacement of the empirical waits.
Unresolved uncertainty and risk:
  Section 14.
```

The `TURN_RENDER_CONTRACT.md` gameplay visibility, dirty-event, and repeat
rows are N/A: this change precedes gameplay and changes no visibility producer,
dirty state, repeat lifecycle, or gameplay renderer. Its applicable physical
render obligation is that the C64 boot display has one owner per phase and is
blanked before any incompatible bank/mode or payload write.

## 3. Selected layout and rejected alternatives

VIC bitmap mode permits bitmap offset `$0000` or `$2000` in a 16 KiB bank.
MORIA64 must load through `$BFFF`, so a live boot bitmap must use bank 3.
`64.BANK` is fixed at `$F000-$FFF7`; therefore the only compatible display
layout is:

- bitmap: `$C000-$DF3F` (8000 bytes)
- matrix: `$E000-$E3E7` (1000 bytes)
- color: `$D800-$DBE7` (1000 hardware color cells)
- `$DD00=$00`, `$D018=$80`, `$D016=$18`, `$D011=$3B`

MORIA64 is split at the existing `program_end == MAP_BASE` boundary:

- `MORIA64`: `$0801-$BFFF`, 47103 bytes
- `64.INIT`: `$C000-$C368`, 873 bytes, with PRG header `$00,$C0`
- `64.BANK`: `$F000-$FFF7`, 4088 content bytes

`64.INIT` is loaded only after `$D011=$0B`. Revision 1's `$E400` staging,
copy loop, and header patch remain rejected by explicit user direction.
Staging `64.BANK`, changing its destination, enabling `LOAD_TO_API`, degrading
the art, or loading an unsplit MORIA64 retain the conflicts documented by
Revision 2 and are not selected.

## 4. Exact memory ownership

All ranges are inclusive.

| Range | Size | Boot owner and lifetime |
| --- | ---: | --- |
| `$0200-$0333` | 308 | KERNAL/install low memory; never used for persistent boot code |
| `$0334-$0335` | 2 | Krill handoff magic `$4B,$D2`, written only after install |
| `$0336-$0339` | 4 | Existing runtime Krill state/family handoff |
| `$033A` | 1 | bit 0: BOOTART64 used Krill; bit 7: post-load display CRCs passed |
| `$033B` | 1 | captured boot device, valid range 8-30 |
| `$033C-$033F` | 4 | KERNAL/cassette guard; not borrowed |
| `$0340-$038C` | **77** | temporary terminal-error trampoline, saved `MSGFLG`, and exact LOAD A/P evidence; copied after install, dead on normal game entry |
| `$038D-$03FF` | 115 | KERNAL/cassette and later dungeon scratch; not borrowed |
| `$0400-$04ED` | 238 | KRES64 after install messages finish; `loadraw=$0400`, `uninstall=$04E1` |
| `$04EE-$04FF` | 18 | unallocated guard between resident and chain |
| `$0500-$07FF` | **768** | copied chain code, NMI bridge, CRC state, and three filenames |
| `$0801-<embedded end` | implementation-measured; hard end `<$2000` | revised boot/chain source, embedded clean 238-byte KRES64, and embedded 77-byte terminal trampoline; the trampoline source/copy addition is exactly 94 bytes |
| `$2000-$3B53` | 6996 | actual current KINST64 content span (6998-byte PRG minus header) |
| `$A000-$C70F` | 10000 | BOOTART64 stage, consumed color -> matrix -> bitmap |
| `$C000-$DF3F` | 8000 | live P3/P4 bitmap; dead before `64.INIT` writes `$C000-$C368` |
| `$D800-$DBE7` | 1000 | live color RAM; low nibbles are display data |
| `$E000-$E3E7` | 1000 | live P3/P4 matrix; post-art overlay staging may reuse `$E000-$EFFF` |
| `$F000-$FFF7` | 4088 | `64.BANK`; remains below CPU vectors at `$FFFA-$FFFF` |

### 4.1 Chain survival and byte budget

The current chain is 187 bytes, leaving only 5 bytes at `$0340-$03FF`; that
location is rejected for the complete chain. Revision 5 copies the complete
chain to `$0500-$07FF` and uses only the fixed 77-byte `$0340-$038C` prefix for
the independent terminal-error trampoline.
The exact available budget is `$0800-$0500 = $0300 = 768` bytes. Implementation
reserves the complete range with these hard sub-budgets:

| Component | Maximum bytes |
| --- | ---: |
| Main Krill/KERNAL/recovery control and waits | 256 |
| Two-load KERNAL setup/cleanup and device use | 112 |
| CRC-16 traversal/comparison and boot NMI bridge | 160 |
| `MORIA64`, `64.BANK`, `64.INIT` names and CRC/device state | 48 |
| Growth reserve | 192 |
| **Total** | **768** |

These are allocation ceilings, not estimates. Each component gets start/end
labels and an assertion; the final non-weakenable assertion is
`CHAIN_STUB_ADDR + (chain_stub_end-chain_stub) <= $0800`. The implementation
must report the assembler's exact used-byte count. A 16-bit pointer/count copy
copies the stub; the current one-byte X length is forbidden. Source and
destination are disjoint, and both are below MORIA64's first destination byte
`$0801`.

`$0500-$07FF` survives every operation that needs it: the install and its
messages finish before the copy; the resident ends at `$04ED`; MORIA64 begins
at `$0801`; the three payloads target `$0801+`, `$C000+`, and `$F000+`;
KERNAL messages are disabled before fallback LOADs; and a successful chain has
jumped to `entry_main` before P6 calls `$E544`. A failed chain tail-jumps to the
surviving trampoline before that trampoline calls `$E544`. The chain is dead
on either route, so clearing `$0500-$07E7` is intentional.

### 4.2 Surviving terminal-error trampoline

The terminal-error path is exactly 77 bytes at `$0340-$038C` inclusive. It is
not a shortened chain and has no filename, LOAD, recovery, or return-to-chain
logic. All chain-stage terminal errors converge only after the applicable
LOAD/CLOSE/CLRCHN helper has restored LOAD's A and full P. The chain then uses
`JMP ERROR_TRAMP_ADDR`, never `JSR`, with no later instruction expected in the
chain:

```assembly
error_trampoline:                  // $0340
    pha                            // PHA does not change LOAD's P
    php
    sei                            // after the exact returned P is stacked
    pla
    sta error_load_p
    pla
    sta error_load_a
    ldx #$ff                       // terminal tail-call discards chain frames
    txs                            // normalize before the only surviving JSR
    lda #$37                       // KERNAL/BASIC ROM, I/O, and ROM vectors
    sta $01
    lda #$0b                       // blank before any VIC-bank/mode change
    sta $d011
    lda #$03                       // bank 0 and released IEC lines
    sta $dd00
    lda #$14
    sta $d018
    lda #$08
    sta $d016
    lda #$00
    sta $d020
    sta $d021
    lda error_saved_msgflg
    sta $9d
    jsr $e544                      // erases the dead chain, not this caller
    lda #$0e
    sta $d020
    lda #$06
    sta $d021
    lda #$1b                       // enable only the cleared text screen
    sta $d011
    cld
    cli
    jmp ($a002)                    // BASIC warm start; no return
error_saved_msgflg:
    .byte 0
error_load_a:
    .byte 0
error_load_p:
    .byte 0
error_trampoline_end:
```

The instructions are exactly 74 bytes and the three labelled state bytes make
the copied object exactly 77 bytes. The embedded source is assembled under a
destination-PC scope for `$0340`, so every absolute operand that names one of
the three trailing bytes resolves into `$038A-$038C`, not back into the source
copy in `boot.prg`: saved `MSGFLG=$038A`, LOAD A=`$038B`, and LOAD P=`$038C`.
Immediately before the P4 chain copy, after the installer and BOOTART64
transaction have both finished, an 11-byte
`LDX #77 / LDA source-1,X / STA $0340-1,X / DEX / BNE` loop copies all 77 bytes.
A separate six-byte absolute `LDA saved_msgflg / STA error_saved_msgflg` patch
then places the P0 value in the destination. Thus the boot-image cost added by
this object and its copy/patch sequence is exactly 94 bytes: 77 source bytes and
17 copier/patch bytes. It is outside the 768-byte chain allocation. The
already-budgeted one-byte P0 `MSGFLG` save is not counted a second time.

The timing is mandatory. Krill install may overwrite `$0200-$03FF`, so neither
the trampoline nor its saved byte is placed at `$0340` before the installer
returns, or before the install path has been skipped after KINST64 LOAD failure.
Its embedded source remains in `boot.prg` until MORIA64 overwrites `$0801+`.
After the copy, `$0340-$038C` survives all MORIA64/`64.INIT` loads and `$E544`'s
`$0400-$07E7` clear. The existing production chain already executes KERNAL LOAD
from `$0340` and retains its code and filenames there across the transfer
(`boot.s:395-519`); Revision 5 nevertheless requires a destination canary
across each later KERNAL LOAD rather than relying only on that precedent.

Control and interrupt ownership are also closed. Before `$01=$37`, an NMI uses
the still-intact copied-chain RAM handler. After that store, KERNAL ROM owns the
hardware vectors before `$E544` erases the chain. The entry PHA/PHP pair is
balanced by the two PLAs before the clear, recording the exact LOAD A and full
P for the harness. Because this is a terminal tail-call, `LDX #$FF / TXS`
discards any chain frames before `$E544`; the clear then makes and returns
through its sole frame on normalized page-one stack RAM, which the clear does
not overwrite. IRQs are enabled only after that return. The trampoline
explicitly clears the screen while blank and does not assume BASIC warm start
will clear it.

Source/end labels assert: base exactly `$0340`; instruction size exactly 74;
total size exactly 77; end exactly `$038D` and at or below `$0400`; no overlap
with `$0334-$033B`, KRES64, or the `$0500` chain; source below `$2000`; and
source/destination disjoint. `$0340-$038C` is only a boot-phase overlay of the
later `$033C-$03FF` dungeon scratch owner. On normal entry the game may overwrite
it; on terminal error the game is never entered.

### 4.3 Clean resident and settled installer-message lifecycle

KRES64 is embedded as 238 data bytes in `boot.prg`, assembled for execution at
`$0400`, rather than loaded into live screen RAM before `jsr $2000`. The build
asserts embedded length 238 and embedded end `<$2000`. Sequence:

1. At P0, save KERNAL `MSGFLG` (`$9D`) in boot/chain-owned state and set it to
   zero before KERNAL boot loads. This suppresses hidden SEARCHING/LOADING text
   from being revealed when the installer temporarily enables `$0400`; the
   installer diagnostics call BSOUT directly (`install.s:800-815`) and remain
   visible. Restore the saved value only at final handoff or a clean error exit.
2. KERNAL-load KINST64 to `$2000-$3B53` through the A/P-preserving helper and
   clean channels on either result. On success, call install. On LOAD failure,
   leave magic clear and continue through the KERNAL BOOTART64 fallback without
   calling install.
3. The installer may select bank-0 screen `$0400`, enable 40-column text, set
   red border/background, select white text, route output to screen, and print
   either the complete 1541U warning or failed-mute-device error through BSOUT.
   This is the user's selected shipped behavior. The renderer performs its own
   delay and restores output device, text color, saved VIC registers, CIA2
   VIC-bank latch, background, and border. The error
   returns install failure; the warning may return success
   (`install.s:447-463,719-733,735-865,1351-1381`).
4. Immediately after every installer return, boot reasserts `$01=$37`, blanks
   with `$D011=$0B`, selects bank 0, and restores black colors. The vendor text
   remains in `$0400` RAM but is no longer visible.
5. Only on install success, copy the untouched embedded 238 bytes to
   `$0400-$04ED`, then set handoff magic. No installer or message executes
   afterward.

Thus installer output may write screen RAM, but can never modify executable
KRES64. On success, boot art later uses bank-3 matrix `$E000`, so the old
`$0400` characters remain hidden; fallback uses the same blanked art-load
sequence. If art is absent, P6 `$E544` clears `$0400-$07E7` before text is
enabled. Any later chain-stage terminal KERNAL error tail-jumps to the section
4.2 trampoline, which clears while blanked before enabling text and entering
the warm-start error presentation, so vendor text is never accidentally
redisplayed. The copy follows the vendor's explicit rule to place a below-`$0400`
resident only after install (`README:178-181`) and avoids an extra post-install
disk transaction.

## 5. NMI-safe banking mechanism

SEI does not mask RESTORE NMI. The project-supported processor-port states are
`$30` (all RAM), `$34` (no ROMs), `$35` (no KERNAL, I/O visible), `$36` (no
BASIC), and `$37` (all ROMs), from
`c64/hal/memory_bank_consts.s:4-11`. `$30` and `$34` hide I/O, so a handler that
reads `$DC0D/$DD0D/$D019` without changing `$01` cannot acknowledge hardware.
The current runtime handler does exactly that (`main.s:1096-1108`) and must be
replaced, not cited as already equivalent.

Both the chain and runtime handlers use this 26-byte sequence:

```assembly
    cld
    pha
    lda $01
    pha
    lda #$35
    sta $01
    lda $dc0d
    lda $dd0d
    lda $d019
    sta $d019
    pla
    sta $01
    pla
    rti
```

The handler preserves A and the interrupted `$01`; X/Y are untouched and RTI
restores P. It exposes I/O only inside the handler, acknowledges CIA1, CIA2
(including RESTORE), and VIC, then restores the exact interrupted mapping. It
therefore works for `$30`, `$34`, and `$35`. Under `$36/$37`, HIRAM selects the
KERNAL vectors and the ROM handler applies instead.

The runtime target remains `c64_irq_hidden_rom` at the current linked `$BAA8`,
not artificially below `$A000` (Revision 3 review lines 26-36; current source
`main.s:1096-1126`). Reachability follows from the C64 decode itself: a RAM NMI
vector at `$FFFA/$FFFB` is visible only when HIRAM is clear, and with HIRAM
clear BASIC ROM cannot cover `$A000-$BFFF`; therefore RAM at `$BAA8` is visible
whenever that RAM vector can select it. The handler and `program_end=$C000`
remain in the resident image and survive all runtime bank changes.

The current handler is 16 bytes; the replacement is exactly 26, a 10-byte
increase. The adjacent `c64_install_ram_irq_vectors` is currently 30 bytes
because it saves `$01`, selects `$35`, and restores `$01`. None of that banking
is needed to *write* underlying RAM at `$FFFA-$FFFF`: KERNAL ROM affects reads,
not writes, and this range is not I/O. Its required implementation is therefore
the 20-byte `PHP; SEI;` four-vector-write sequence followed by `PLP; RTS`, saving
exactly 10 bytes. The combined handler+installer span remains 46 bytes, so the
current full `program_end=$C000` does not move. Assertions pin the handler in
resident RAM below `MAP_BASE`, require the combined span not to grow, and check
the final program boundary; no player-visible text or boundary assert funds the
change.

The current generated symbols corroborate the source count:
`c64_irq_hidden_rom=$BAA8`, `c64_install_ram_irq_vectors=$BAB8`, and
`kernal_load_safe=$BAD6`. Revision 5 therefore retains the 26-byte handler at
`$BAA8-$BAC1` and the 20-byte installer `$BAC2-$BAD5`; `kernal_load_safe`
remains `$BAD6`, and all later linked addresses remain unchanged.

Vector ownership transitions without a gap:

1. Before P3 `$01=$30/$35` windows, boot points RAM NMI/IRQ vectors to its
   boot-image handler. Before MORIA64 overwrites that source, it copies the
   chain and repoints RAM vectors to the equivalent handler in `$0500-$07FF`.
2. The chain restores `$01=$37` before `jmp $080E`; `entry` selects `$36`
   (`main.s:122-125`). Both mappings use KERNAL ROM vectors, so an NMI between
   chain exit and runtime-vector installation cannot enter stale RAM code.
3. `entry_main` runs `save_zp`, `disk_reset_session_state`, then
   `c64_install_ram_irq_vectors` before `init_load_banked`
   (`main.s:678-687`). The simplified installer writes the runtime RAM vectors
   while KERNAL vectors remain selected.
4. Only after the runtime vectors point to resident `$BAA8` may
   `init_load_banked` call `$E544` and clear `$0500-$07E7`
   (`main.s:2605-2615`). The chain handler is dead before its bytes are erased.
5. A terminal chain error does not enter `entry_main`: section 4.2 switches to
   `$01=$37`, and therefore ROM vector ownership, before its surviving caller
   clears the chain. No stale RAM-vector target is visible during or after that
   clear.

Production-path verification injects RESTORE/NMI separately at `$01=$30`,
`$34`, and `$35`, checks return to the interrupted instruction with A/P/X/Y and
`$01` unchanged, confirms the CIA/VIC sources are acknowledged, and checks both
vector handoffs around the P6 screen clear. `$36/$37` cases verify the ROM-vector
route rather than the RAM handler.

## 6. Phase sequence

| Phase | Display | Disk and memory action |
| --- | --- | --- |
| P0 | blank text, bank 0 | capture device 8-30 into `$033B`; clear evidence/magic; save `MSGFLG` and suppress only KERNAL LOAD status text |
| P1 | normally blank; vendor installer messages may temporarily enable text | helper-load KINST64 and clean channels with A/P intact; on LOAD failure skip install and retain clear magic; otherwise install and reblank, then on install success copy embedded KRES64 to `$0400` and set magic |
| P2 | blank | Krill-load BOOTART64 after install or helper-load it through KERNAL fallback; a failed/missing art load retains clear evidence and continues without display |
| P3 | blank until complete | install boot RAM NMI vector; copy color, matrix, bitmap; compute baseline CRCs; select bank 3 and show art |
| P4 | bitmap live when art exists | copy/patch the 77-byte terminal trampoline at `$0340`, copy the chain to `$0500`, point RAM NMI vector into the chain, load MORIA64 and, on Krill only, `64.BANK`; validate destination CRCs |
| P5 | blank **before load** | load true-address `64.INIT` directly to `$C000-$C368`; switch to blank bank-0 text mode |
| P6 | remains blank through any fallback `64.BANK` load, then normal text/title | after `disk_reset_session_state`, `entry_main` adopts `$033B` into `program_device`, installs runtime vectors, and runs `init_load_banked`; fallback loads `64.BANK` from that device, then `$E544` clears the dead chain and text is enabled |

P3 copy order is color (`$C328-$C70F` -> `$D800-$DBE7`), matrix
(`$BF40-$C327` -> `$E000-$E3E7`), then bitmap (`$A000-$BF3F` ->
`$C000-$DF3F`). The destination bitmap overwrites the stage tail, so any other
order destroys a source.

CPU writes through BASIC/KERNAL ROM to underlying RAM, but writes to
`$D000-$DFFF` reach I/O when I/O is mapped. Therefore the bitmap's
`$D000-$D7FF` portion is copied and read only with I/O hidden; color RAM is
copied/read only with I/O visible. The design makes no broader "writes always
reach RAM" claim.

## 7. Load and recovery flows

### 7.1 Krill success

1. Install as P1 specifies; record drive family and magic only after the clean
   resident copy.
2. `loadraw(BOOTART64)`, display it if successful, and establish CRC baselines.
3. Copy/patch the terminal trampoline, copy/revector the chain, then
   `loadraw(MORIA64)`.
4. Wait the existing empirical 18 frames, then `loadraw(64.BANK)`.
5. Recompute CRC-16 for bitmap, matrix, and color. On equality, set `$033A`
   bit 7. Any mismatch takes the same safe blanked recovery as a load failure.
6. Perform the second existing empirical 18-frame wait while art is live.
7. Blank `$D011` first; `loadraw(64.INIT)` to its true `$C000` address.
8. Select blank bank-0 text mode, restore `$01=$37`, CLI, jump `$080E`.

Every `loadraw` uses a zero-terminated actual filename and checks carry. The
18-frame delays are repository-observed workarounds for current drive-family
behavior, not guarantees made by r194.

### 7.2 KERNAL fallback

P0 has already saved KERNAL `MSGFLG` (`$9D`) and set it to zero. Immediately
before copying the chain, copy the terminal trampoline and patch the saved value
into both its labelled state and the labelled chain success-handoff byte; keep
MSGFLG zero to suppress SEARCHING/LOADING output into `$0400-$07E7`, then restore
it at handoff/error. The art, if present, remains live through the MORIA64 LOAD.
Implementation verification must canary both copied objects across each later
KERNAL LOAD rather than treating message suppression as their survival proof.

For both MORIA64 and `64.INIT`, and for every other boot KERNAL LOAD, use this
result-preserving cleanup contract on both carry outcomes:

```text
LOAD returns A/P
PHP; PHA
LDA #LOGICAL_FILE; JSR CLOSE
JSR CLRCHN
PLA; PLP
branch on restored carry, with restored A available as the LOAD error/status
```

The same contract applies before the chain: KINST64 and KERNAL BOOTART64 call a
named boot helper that returns the exact LOAD A/P only after CLOSE/CLRCHN. A
KINST64 failure leaves magic clear, skips installer execution, and proceeds to
the KERNAL BOOTART64 attempt. A KERNAL BOOTART64 failure leaves `$033A.0` clear,
performs no display copy or CRC baseline, and proceeds to trampoline/chain copy
and MORIA64. Neither nonterminal transition treats eventual title entry as A/P
evidence; section 7.4 captures the helper result immediately at each call site.

After successful MORIA64 cleanup, sample/validate the display CRCs, set evidence,
then blank. Issue fresh SETNAM/SETLFS with device `$033B`, LOAD `64.INIT`, and
perform the same cleanup before testing carry. A failed chain LOAD reaches the
terminal trampoline only after cleanup, with restored A/P still current. In P6,
`program_device` has already adopted `$033B`, so the existing KERNAL `64.BANK`
load uses the boot device; its cleanup is updated to preserve A/P by the same
rule. Revision 5 retains moving `$E544` and `$D011=$1B` after successful magic
validation or KERNAL `64.BANK`: unlike current `main.s:2608-2668`, the fallback
load and its failure transition remain blank, and the successful chain is
cleared only after runtime vectors own NMI/IRQ.

### 7.3 Mid-boot Krill failure or CRC mismatch

For MORIA64, `64.BANK`, `64.INIT`, or CRC failure:

1. With I/O visible, write `$D011=$0B` **before uninstall or any `$DD00`/mode
   change**. The art is not shown again on this recovery path.
2. Call uninstall. Its outputs are undefined, so reinitialize `$01`, decimal
   mode, IRQ state, `$DD00`, VIC mode, colors, device, filenames, and all
   relied-on registers afterward.
3. Clear magic and Krill-active evidence; retain captured device `$033B`.
4. Wait the existing empirical 150 frames for stock-DOS recovery. This is a
   repository workaround, not an r194 timing guarantee.
5. KERNAL-reload MORIA64 and `64.INIT`, with result-preserving cleanup after
   each. Keep the display blank throughout. P6 KERNAL-loads `64.BANK` from the
   same device.

This intentionally differs from the ordinary KERNAL fallback: recovery does
not claim the art remains live after a failed fast-load transition.

### 7.4 Distinct KERNAL failure transitions

One result-preserving helper may implement LOAD/CLOSE/CLRCHN for boot calls and
one may implement it for chain calls, but every caller transition remains
statically identified and independently injected. A test hook returns a
distinct nonzero A and carry set from the real `$FFD5` call site; immediately
after the named helper, test-only evidence captures A and P before production
branches, then restores the exact captured A/P before that branch; the
instrumentation is semantically transparent. Each scenario asserts logical file
2 is absent from the KERNAL file table, default input/output channels are
restored, the injected A and full P survived, and the named production
continuation executed.

| Injected failure | Initial display/path | Required cleanup, status, and transition evidence |
| --- | --- | --- |
| KINST64 KERNAL LOAD | blank P1, before installer execution or resident copy | named boot helper closes/CLRCHN and preserves A/P; immediate call-site capture proves exact A/full P, absent logical file 2, and default channels; magic/family remain clear, installer is not called, and control reaches the KERNAL BOOTART64 attempt |
| KERNAL BOOTART64 LOAD | blank P2 after absent/failed install | named boot helper independently proves cleanup and exact A/full P at the real call site; `$033A.0` remains clear, display/copy/CRC setup is skipped, and control reaches trampoline/chain copy followed by MORIA64 |
| Ordinary fallback MORIA64 | art live when available; no Krill install | shared chain helper closes/CLRCHN and preserves A/P; `JMP $0340` records exact A/P, blanks, restores `MSGFLG`, clears `$0400-$07E7` from surviving code, enables clean text, and reaches BASIC warm start |
| Recovery MORIA64 | already blank after a failed Krill MORIA64 or `64.BANK`, uninstall, and empirical settle | the recovery call dispatches through the same production helper and independently proves cleanup/A/P; it tail-jumps to the same surviving clean warm-start transition without changing VIC bank while visible |
| Ordinary fallback `64.INIT` | blanked after successful MORIA64 CRC checkpoint | cleanup/A/P completes before `JMP $0340`; no `64.BANK` attempt occurs; trampoline evidence matches the injection and clean text warm start is reached |
| Recovery `64.INIT` | blank throughout after successful recovery MORIA64 | same shared helper and independent caller injection; cleanup/A/P completes before `JMP $0340`; P6 is not entered |
| P6 fallback `64.BANK` | blank text mode after successful MORIA64 + `64.INIT`; runtime vectors already point to resident handler | P6 helper closes/CLRCHN and preserves A/P before restoring serial/VIC state; test evidence is captured before the existing red-border terminal loop; `$E544` and display-enable are not executed on failure |

KINST64 and BOOTART64 may share a boot helper, and ordinary/recovery
MORIA64/`64.INIT` may share a chain helper, but static checks enumerate all six
call sites and every distinct continuation executes once. `64.BANK` is a
separate main/init-tail caller and always gets its own injected scenario.
Success scenarios also assert cleanup at KINST64, KERNAL BOOTART64, MORIA64,
`64.INIT`, and `64.BANK`, preventing a failure-only hook from being mistaken for
proof of normal operation.

## 8. Integrity checkpoints

`$033B=$3B` from Revision 2 proved only a register value and is removed.
Revision 5 retains CRC-16/CCITT-FALSE baselines (polynomial `$1021`, initial
`$FFFF`, no reflection, no final XOR) immediately after P3 copying and compares
them after the last art-live payload on each path:

- bitmap: all 8000 bytes at `$C000-$DF3F`, with I/O hidden;
- matrix: all 1000 bytes at `$E000-$E3E7`, with KERNAL hidden;
- color: 1000 low nibbles at `$D800-$DBE7`, with I/O visible.

P3 writes the six baseline bytes into labelled data in the source chain image;
the P4 16-bit copy carries them into the `$0500` chain. They never live in
display memory or loader ZP. The CRC routine reinitializes `$FB-$FE` only while
Krill is idle.
The Krill checkpoint occurs after MORIA64 and `64.BANK`, before blanking. The
KERNAL checkpoint occurs after MORIA64, its last art-live payload; fallback
`64.BANK` is intentionally post-art. Bit 7 of `$033A` is set only after all
three comparisons pass. Reaching the title proves `64.INIT` and, as applicable,
`64.BANK`; harness assertions on bit 7 prove actual display-memory survival.

## 9. Non-overlap and startup-tail proof

| Writer | Destination | Live-display result |
| --- | --- | --- |
| KINST64 | `$2000-$3B53` | display normally blank; vendor message is explicit P1 UI |
| installer | documented `$0200-$03FF`, `$0400` message output, drive | clean KRES64 not copied until afterward |
| BOOTART64 | `$A000-$C70F` | blank; source only |
| P3 copies | selected three display spans | blank until all copies and CRC baseline complete |
| MORIA64 | `$0801-$BFFF` | disjoint from all live display spans and chain |
| `64.BANK` | `$F000-$FFF7` | disjoint; `$FFF7 < $FFFA` |
| `64.INIT` | `$C000-$C368` | bitmap already dead because blank precedes LOAD |
| P6 overlay/tier staging | `$E000-$EFFF` | matrix dead |
| T64/title/map writes | `$C000+` | bitmap dead and init-tail callers completed |

Between the `64.INIT` LOAD and `init_load_banked`, writes do occur. The relevant
production order is `save_zp`, `disk_reset_session_state`, explicit `$033B` to
`program_device` adoption, and `c64_install_ram_irq_vectors` before
`init_load_banked` (`main.s:678-687`, with the adoption inserted after the
reset). Their destinations are the assembled ZP save/state/device locations,
`$FFFA/$FFFB`, and `$FFFE/$FFFF`; none intersects `$C000-$C368`. The
implementation adds symbol/range assertions for those disjoint owners. It must
not repeat Revision 2's false claim that there are no intervening writes.

The remaining init routines execute before `title_load_and_draw` writes T64 at
`$C000-$CEFF` (`main.s:687-766`). The split preserves every linked address;
only disk packaging and load order change.

## 10. Krill r194 host-environment contract

| Resource | Required host contract and evidence |
| --- | --- |
| Install registers/result | KERNAL enabled; input includes valid FA plus other KERNAL ZP prerequisites whose upstream list is explicitly incomplete. Output carry=status, A=status, X=drive type, Y=version-string ZP address on success; I is clear. `loader.inc:184-191`; `README:172-184`. |
| Install memory/UI | Install may overwrite `$0200-$03FF`; its message routine selects `$0400`, enables text display, and calls BSOUT. `README:178-181`; `install.s:447-463,719-865`. Revision 5 intentionally shows the complete messages, then copies KRES64 and later the `$0340` trampoline only after installer return. |
| `loadraw` | X/Y points to a zero-terminated name; first load uses the actual name; carry set and A=status on error. Other registers/flags are not promised. `loader.inc:196-212`; `README:192-214,230-234`. |
| Destination | `LOAD_TO_API=0`; the PRG header controls destination. `loaderconfig.inc:23-29`. This is why `64.INIT` carries `$C000`. |
| Interrupts | Transfer tolerates IRQ/NMI/DMA/sprites/badlines, but that does not make host RAM vectors safe. `README:51`. Revision 5 supplies context-preserving boot, chain, terminal-error, and runtime vector ownership for all supported `$01` mappings. |
| Resident/idle | Boot resident is `$0400-$04ED`, `loadraw=$0400`, `uninstall=$04E1`; idle code and loader ZP may be buffered/reused. Generated `loadersymbols-c64.inc:33-44`; `README:236-240,279-284`. |
| ZP | `$E0-$E4` is exclusive during a load. `$FB-$FE` copy/CRC state is used only while idle. No claim is made that the install prerequisite list is complete. |
| CIA2/VIC | While installed, `$DD00` writes are literal 0-3, never unmasked RMW; CIA2 DDRA is loader-owned until uninstall. `README:249-275`; `hal-c64-c128.inc:236-281`. |
| Uninstall | No inputs; all outputs undefined. `loader.inc:398-405`. Recovery reinitializes all depended-on state. |
| Timing | r194 specifies no post-install, inter-load, or post-uninstall delay. The watchdog text concerns starvation during an active load. `README:526-533`. All 18/150-frame waits require repository runtime evidence. |

## 11. Required implementation assertions

1. `InitTail` starts exactly at `MAP_BASE`, has PRG header `$00,$C0`, and its
   generated content length equals `init_tail_end-init_tail_start` (currently
   873). No header mutation rule exists.
2. MORIA64 ends at or below `$C000`; current selected split ends at `$BFFF`.
3. Embedded KRES64 content is exactly 238 bytes and ends below `$2000`;
   generated entry offsets remain `$0400/$04E1`.
4. KINST64 header is `$00,$20`, content length is 6996, and destination end is
   `$3B53`; derive the end from the artifact rather than hard-coding `$2C98`.
5. Terminal-trampoline destination is exactly `$0340-$038C`: assert 74
   instruction bytes, three state bytes, 77 total bytes, exclusive end `$038D`,
   and end at or below `$0400`. Assert disjointness from `$0334-$033B`, KRES64,
   and the `$0500` chain; source and destination are disjoint; embedded source
   ends below `$2000`. Assert the copier's immediate count is 77 and patch
   target is the destination `error_saved_msgflg` byte.
6. Chain base is `$0500`; each sub-budget in section 4.1 and total end at or
   below `$0800` are asserted. The copier uses a 16-bit length.
7. Chain, embedded resident source, and terminal-trampoline source do not
   intersect KINST64, KRES64, MORIA64, display staging, or destination spans.
8. Bitmap/matrix/color sizes and destinations are asserted; `$D018=$80` is
   derived from matrix `$E000` and bitmap `$C000`.
9. Boot and chain RAM NMI targets survive their protected windows. Runtime
   `c64_irq_hidden_rom` remains resident below `MAP_BASE`; whenever its RAM
   vector is visible, `$A000-$BFFF` RAM containing the target is also visible.
   Assert the 26-byte handler, 20-byte vector installer, unchanged 46-byte
   combined span, and CPU vectors outside `64.BANK`.
10. `$033A/$033B < $033C`; captured device validation is 8-30; P6 copies
    `$033B` into `program_device` before any fallback LOAD.
11. `64.INIT` is a `C64_BUILD_ARTIFACTS` dependency and is independently
     enumerated by both shipping owners: copied to `c64-dist/64.init` for the ZIP
     (`Makefile:484-521`) and written as `64.init` to the D64
     (`Makefile:523-562`). The filename remains `64.INIT` unless review
     explicitly changes it.
12. Every KERNAL LOAD wrapper implements the A/P-preserving cleanup contract.
    Static call-site checks enumerate KINST64 and fallback BOOTART64 through the
    named boot helper, ordinary/recovery MORIA64 and `64.INIT` through the named
    chain helper, and P6 `64.BANK` through its named main helper. Failure branches
    may inspect carry but do not modify A/P before immediate harness capture or,
    for terminal chain failures, `JMP $0340`.
13. `tools/check_krill_filenames.py:C64_DISK_NAMES` includes uppercase
     `64.INIT` alongside `MORIA64` and `64.BANK` (`check_krill_filenames.py:29-44`).
     The current hash function yields `$1D,$D7` and no collision against the
     existing shipping set; the checker remains the executable authority after
    the name is added.

## 12. Verification plan

Static checks, without VICE:

- `make build`, including all assertions in section 11 and artifact header/span
  checks.
- `python3 tools/check_krill_filenames.py`.
- Inspect final assembler symbols for the exact chain size, 74/77-byte
  trampoline instruction/total sizes and `$0340-$038C` destination, embedded
  sources' end, MORIA64 end, init-tail span, banked-runtime end, NMI targets,
  and all disjointness assertions.
- Static call-site inspection enumerates the seven KERNAL LOAD continuations in
  section 7.4 and proves each routes through its named preserving helper.
- `make disk64` to exercise both independently enumerated shipping recipes.
- Inspect `build/moria8-c64.d64` with `c1541 -attach ... -list`; require exactly
  one PRG named `64.init`, extract it to a temporary directory, and compare it
  byte-for-byte with `build/c64/64.init`.
- Require `build/c64-dist/64.init` and ZIP entry `64.init`; compare both
  byte-for-byte with `build/c64/64.init`. For the build artifact, D64 extraction,
  dist copy, and ZIP stream, assert total PRG size 875 bytes, header `$00,$C0`,
  and 873 content bytes. Inventory checks also retain `license` and
  `source-offer`; temporary extraction files stay outside source directories.

Production-path emulator scenarios, each with its own bounded timeout:

| Scenario | Required evidence |
| --- | --- |
| Krill success | CRC bit `$033A.7=1`, Krill-art bit set, magic active, `krill_boot_used=1`, title reached |
| KERNAL fallback success | CRC bit set, Krill-art bit clear, magic inactive; KINST64, KERNAL BOOTART64, MORIA64, `64.INIT`, and P6 `64.BANK` success cleanup observed as applicable; title reached |
| Device 9 boot, Krill and fallback | `$033B=9`, `program_device=9`, title reached with all P4/P6 files read from unit 9 |
| Injected KINST64 KERNAL failure | real `$FFD5` call returns distinct A/full P; helper cleanup, absent file 2, default channels, clear magic/family, skipped installer, and entry to KERNAL BOOTART64 are observed |
| Injected KERNAL BOOTART64 failure | real `$FFD5` call returns a different A/full P; helper cleanup, absent file 2, default channels, clear `$033A.0`, no display/CRC attempt, and continuation to trampoline/chain copy and MORIA64 are observed |
| Missing BOOTART64 on Krill path | no CRC bit, no display attempt, title reached; KERNAL failure behavior is covered by its explicit injected row |
| Injected `loadraw(MORIA64)` failure | blank before bank switch; uninstall/reinit; KERNAL recovery from captured device |
| Injected `loadraw(64.BANK)` failure | same transition; no bank-0 bitmap flash; KERNAL full recovery |
| Injected `loadraw(64.INIT)` failure | already blank; KERNAL full recovery; title reached |
| Ordinary KERNAL MORIA64 failure | section 7.4 cleanup/A/P; `$0340` evidence matches; clear runs and returns in surviving trampoline; clean warm-start transition |
| Recovery KERNAL MORIA64 failure | section 7.4 blank recovery-state cleanup/A/P; `$0340` evidence and clean warm-start transition |
| Ordinary and recovery KERNAL `64.INIT` failures | two distinct section 7.4 caller injections; cleanup/A/P and `$0340` evidence; no P6 entry |
| P6 KERNAL `64.BANK` failure | cleanup/A/P captured before red-border terminal path; display remains blank |
| 1541U warning path | complete warning is visible before art; boot reblanks; post-message resident bytes match the clean embedded image; Krill boot succeeds |
| Failed-mute-device message | complete error is visible before art; boot reblanks; fallback begins with no resident execution |
| RESTORE/NMI at `$01=$30/$34/$35` | production runtime handler acknowledges sources and returns with A/P/X/Y and exact `$01` unchanged |
| NMI handoff and `$01=$36/$37` | chain-to-ROM-to-runtime success sequence survives P6 clear; terminal route switches to ROM vectors before its clear; ROM vector handles NMI while HIRAM is set |

Failure injection must occur in the real boot/chain path, not a test-local copy.
Checkpoints inspect blanking and bank order at the transition, not only the final
title. The exact authoritative gate remains `make test64`; it must pass before
implementation completion. Whole-suite timeout policy follows AGENTS.md, while
each scenario remains bounded for hang detection.

## 13. Review correction matrices

| Final `moria8-x6t.1.2` finding | Revision 5 retained resolution |
| --- | --- |
| 1. `$0340` does not fit | `$0500-$07FF`, exact 768-byte budget, component ceilings, 16-bit copier, hard assertions (4.1) |
| 2. KERNAL cleanup/carry | universal CLOSE/CLRCHN wrapper preserves A and full P on every outcome (7.2) |
| 3. installer messages corrupt KRES64 | clean resident embedded and copied only after all messages; visible warning/error behavior explicit (4.3) |
| 4. recovery bank flash | `$D011=$0B` is first recovery hardware action, before uninstall/bank changes (7.3) |
| 5. RESTORE/NMI | boot and copied-chain RAM-vector handlers derived from current runtime mechanism (5) |
| 6. KINST span | corrected to `$2000-$3B53`, 6996 content bytes (4, 11) |
| 7. non-device-8 ownership | `$033B` handoff adopted by `program_device`; device-9 scenarios required (6, 7.2, 12) |
| 8. integrity/failures | three full-span CRCs plus all requested injected transitions and 1541U path (8, 12) |
| 9. overclaims | intervening writes proved disjoint; incomplete ZP caveat retained; waits labelled empirical; D000 write rule and timing wording corrected (6, 9, 10) |

| Independent Revision 3 blocker | Revision 4 resolution |
| --- | --- |
| 1. runtime NMI semantics/location | 26-byte handler saves/restores `$01`, exposes I/O with `$35`, works at `$30/$34/$35`, and remains reachable at actual `$BAA8`; a 10-byte vector-installer reduction makes resident growth net zero; chain-to-runtime handoff precedes `$E544` (5) |
| 2. incomplete KERNAL failure tests | ordinary and recovery MORIA64, ordinary and recovery postblank `64.INIT`, and P6 postblank `64.BANK` are distinct injected production transitions with cleanup/A/P assertions (7.4, 12) |
| 3. no shipping proof for `64.INIT` | `make disk64`, D64 extraction, dist/ZIP inventory, byte comparison, `$00,$C0` header/875-byte PRG checks, and filename-hash membership are required (11-12) |
| 4. installer messages unresolved | user selected complete visible vendor diagnostics before art; exact show, restore, reblank, art/fallback, and eventual clear lifecycle is settled (1, 4.3, 12) |

| Independent Revision 4 blocker | Revision 5 resolution |
| --- | --- |
| 1. chain error clear erases its caller | exact 77-byte `$0340-$038C` trampoline is copied only after install; terminal chain failures tail-jump to it; it records A/P, establishes ROM-vector ownership, blanks, restores `MSGFLG`, calls `$E544` from surviving RAM, normalizes the surviving stack, and enters BASIC without returning to `$0500` (4.2, 5, 7.4, 11-12) |
| 2. KINST64/BOOTART64 failure injections absent | both real KERNAL call sites use the A/P-preserving boot helper and have distinct injections proving exact A/full P, file-table/channel cleanup, and their named nonterminal continuations; success cleanup and static call-site enumeration are also required (7.2, 7.4, 11-12) |

## 14. Remaining measurements and risks

No unresolved safety or observable-behavior decision remains in this design.
The user explicitly selected complete visible vendor warning/error output before
boot art. Memory owner, NMI semantics/location, KERNAL error transitions,
device owner, shipping inventory, and `64.INIT` representation are specified.

The exact assembled chain usage within its fixed 768-byte allocation is a
required implementation measurement, not permission to move a boundary or
weaken an assertion. The terminal trampoline is not such a measurement: its
destination, instruction/data split, total 77-byte size, copy timing, and
control flow are fixed decisions. The runtime handler/vector-installer pair
must remain the specified net-zero 46 bytes; any assembler disagreement blocks
implementation rather than borrowing from text or weakening `program_end`.
The empirical 18/150-frame waits may prove insufficient for a supported drive
family; if a scenario demonstrates that, timing must be re-derived from
evidence without treating r194 as specifying those delays.
