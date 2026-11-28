# Backlog

Durable future work that is too concrete for design philosophy and too
unreleased for release notes.

## Commodore Ports

### Optional: physically plausible chest contents

VMS Moria has no size filter on chest contents, and Moria8 deliberately follows
it (`docs/CHEST_DESIGN.md`): any chest type can contain any object, including
another, larger chest. Umoria added `itemBiggerThanChest`, but only for
`CM_SMALL_OBJ` monster droppers, not chest drops — so even Umoria allows a
large chest inside a small one here.

This is a realism/polish item, not gameplay-value work: nested chests are
amusing and harmless. It would be a deliberate deviation from the pinned VMS
oracle, not a bug fix, so it needs a design call before implementation.

Required work:

- Decide the rule: e.g. contents must not outweigh/exceed the container chest,
  or simply forbid nested chests, or adopt Umoria's `itemBiggerThanChest`
  category/weight filter for chest loot only.
- Record the deviation in `docs/CHEST_DESIGN.md` with VMS `summon_object`
  (moria.inc:2259-2290) as the behavior being superseded.
- Filter or re-roll in `chest_loot_place_one` without changing drop counts,
  odds, or RNG order beyond the filtered retries.
- Add focused coverage proving an ineligible item is never produced while
  eligible drops are unaffected.

Acceptance target:

- Chest contents respect a documented physical-plausibility rule, with the
  deviation from VMS recorded and tested, and no change to drop rates for
   legal contents.

### Give the C128 unit-test batch a per-test timeout

`make test128` runs its unit tests in parallel ("running unit tests in
parallel..." in `platforms/commodore/c128/run_tests128.sh`) with no timeout
per test. On 2026-10-26 one `x128` instance running `test128_detect_evil128`
spun at 100% CPU for 25 minutes and held up the whole gate until it was
killed by hand; the same test passed in seconds when run alone
(`TEST_FILTER='^detect_evil128$' make test128`), so it looked like a VICE
hang rather than a code fault.

Required work:

- Kill a unit test's emulator after a fixed limit (the 30-second runtime cap
  in `AGENTS.md`, or a measured ceiling with margin) and report it as a
  timeout failure naming the test, so the batch finishes.
- Optionally retry a timed-out test once and report a hang that recurs.
- Check the C64 and Plus/4 runners for the same gap.

### Synchronise the C64 disk-swap smoke's image swaps

`load_then_save_new_empty_product_smoke` (`platforms/commodore/c64/run_tests.sh`)
now synchronizes all three drive-8 swaps on monitor breakpoints in
`platforms/commodore/plus4/tests/product_scripted_smoke.py` (`--start-symbol`,
`--swap-symbol`, `--swap2-symbol`). However, `run_tests.sh` still copies images
to short workaround names (`lts_load.d64`, `lts_new.d64`, `lts_prog.d64`) in
`build/test/c64`, `--swap-symbol` still fires before `save_game` rather than at
the insert-save-disk prompt itself, and `attach_drive8` still sleeps 0.5 s.

Required work:

- Move `--swap-symbol` to the insert-save-disk prompt checkpoint if needed and
  drop the short `lts_*.d64` name workaround in favor of a long-path regression.

### Add the VMS `x` weapon swap (secondary weapon slot)

Product support shipped 2026-10-31 (`docs/X_WEAPON_SWAP_DESIGN.md`): `SHIFT+X`
(`CMD_EXCHANGE`, `core/item_exchange.s`) swaps `EQUIP_WEAPON` and
`EQUIP_SECONDARY` (`TOTAL_INV_SLOTS = 34`, `core/item_defs.s`) across all seven
ports, displays on the equipment screen (`core/ui_equipment.s`), refuses a
cursed primary or empty pair without consuming a turn, and is covered by
`test_item_exchange.s` and per-port save round-trips.

Remaining follow-up (`docs/X_WEAPON_SWAP_DESIGN.md` §0 decision 8, §15): a Rogue
or Ranger in `playtest/moria_playtest/brain.py` (`wielding_launcher`) still
keeps its melee weapon in the pack and swaps via `w` (`KEY_WEAR`) instead of
keeping it (or its launcher) in `EQUIP_SECONDARY` and swapping via `SHIFT+X`.

Required work:

- Teach the playtest bot (`playtest/moria_playtest/brain.py`) to keep its melee
  weapon (or launcher) in `EQUIP_SECONDARY` and swap with `SHIFT+X` (`$D8`).
- Optionally add `$D8` to `playtest/moria_playtest/fuzz.py`'s key list.

Acceptance target:

- A playtest Rogue or Ranger with a launcher keeps its alternate weapon in
  `EQUIP_SECONDARY`, swaps via `SHIFT+X` without spending pack slots, and keeps
  frozen suites green.

### Sweep platform-specific inlines in core/ behind HAL macros

`core/` currently contains a few direct platform-coupled blocks instead of HAL
macros: `jsr mmu_safe_map_write_ptr1` (and `jsr mmu_safe_map_read_ptr1`) under
`#if MSG_HISTORY_IN_AUX` in `core/ui_messages.s` and `#if
HAL_PLATFORM_AUX_PERSISTENT_DATA` in `core/recall.s`, plus
`jsr mmu_common_copy_map_row` / `jsr mmu_common_store_map_row` and `SCREEN_RAM,y`
row scratch under `#if HAL_LAYOUT_DUNGEON_GEN_ROW_BATCHED_MAP` in
`core/dungeon_gen.s` and `core/place_secrets_cold.s`. All are assert-guarded,
but they call platform helpers directly from `core/`
(`docs/CROSS_PLATFORM_STRATEGY.md`).

Required work:

- Introduce HAL read/write macros (e.g. `:HalAuxWritePtr1()`) defaulting to
  `sta (zp_ptr1),y` and overridden by Aux/Bank-1 ports to their thunks; same
  pattern for row-copy/scan macros covering the C128 bank-copy path.
- Sweep all four `core/` modules (`core/ui_messages.s`, `core/recall.s`,
  `core/dungeon_gen.s`, and `core/place_secrets_cold.s`); no behavior change, so
  existing gates (`make -j7 -O test`) suffice.

Acceptance target:

- No direct platform helper/address calls remain in the touched core modules;
  all seven platform builds and test gates stay green.

### Implement Plus/4 TED sound effects

The Plus/4 has TED sound hardware, but Moria8's Plus/4 backend currently
silences every sound request. `platforms/commodore/plus4/sound.s` initializes
and clears TED sound registers, and `sound_play` immediately clears them again
instead of using the existing frequency/control tables.

Required work:

- Implement `sound_play` for TED using the existing `SFX_*` IDs shared by C64,
  C128, and Plus/4.
- Implement `hal_sound_update` so effects stop cleanly and cannot leave stuck
  tones.
- Preserve TED display state: sound writes must not corrupt bitmap/character
  mode bits that `plus4_display_resync` protects.
- Tune TED approximations for bump, hit, miss, pickup, death, level-up, spell,
  spell-fail, hunger warning, and fainting.
- Add Plus/4 coverage proving sound init/play/update touch the expected TED
  registers and return to silence.
- Document any intentional TED approximation versus SID behavior if the audible
  effect set cannot match C64/C128 closely.

Acceptance target:

- Plus/4 gameplay produces audible, bounded sound effects for the existing
  shared `SFX_*` events without stuck tones or display-mode regressions.

### Optional: exact Umoria per-blow melee messages

Moria8 now calculates melee blow counts from the Umoria-style STR/DEX/weapon
weight buckets, including exceptional stats, too-heavy weapons, bare hands, and
launcher/ammo-as-melee handling. Focused combat tests cover the reported C128
gnome rogue/dagger case, top exceptional DEX, too-heavy weapon handling, and
ranged launcher melee forcing one blow.

The remaining difference is player-facing feedback. Umoria prints one message
per blow; Moria8 prints one round summary and appends `(hits/blows)` when the
attack had multiple blows, for example `You hit the skeleton kobold (2/3).`.
This prevents multi-blow attacks from looking like single-hit attacks, but it is
not byte-faithful Umoria message timing.

Upstream behavior:

- Umoria calculates blows from weapon weight, STR, and DEX before the attack.
- Umoria loops once per blow during a single attack command.
- Each blow rolls to hit independently.
- Each miss prints `You miss the <monster>.`
- Each hit prints `You hit the <monster>.`
- If a blow kills the monster, Umoria prints `You have slain the <monster>.`
  and stops the remaining blow loop.
- Bare hands get 2 blows with a to-hit penalty; missile/ammo melee attacks are
  forced to 1 blow.

Required work:

- Decide whether exact per-blow message parity is worth the extra message
  traffic on 40-column targets.
- If yes, change melee feedback so each miss/hit/slay blow is visible as its own
  message and killing blows stop the loop immediately.
- Add focused coverage for per-blow message order and kill-loop stopping.

Acceptance target:

- If this item is implemented, melee feedback matches Umoria per-blow message
  timing. Otherwise the current `(hits/blows)` summary is the documented Moria8
  approximation.

### Implement numeric repeat prefixes

The C64 and Plus/4 input parsers explicitly leave numeric repeat prefixes
deferred, and `zp_input_count` is currently always 1. Classic Moria supports
repeat counts for commands where repeating is safe and meaningful.

Required work:

- Define which commands accept numeric repeat prefixes on each Commodore
  keyboard layout.
- Parse multi-digit prefixes without conflicting with movement, inventory
  letters, `SHIFT` commands, or C128 keypad input.
- Route accepted counts through one shared repeat path and reject or ignore
  unsafe repeats consistently.
- Add tests for one-turn commands, movement/run interactions, prompt
  cancellation, and non-repeatable commands.

Acceptance target:

- Numeric prefixes work for supported repeatable commands without changing
  single-key command behavior or prompt input semantics.

### Armour reduction above AC 200

`mon_atk_ac_reduce` (`core/monster_attack.s` ~281-304) computes damage −
AC × damage / 200 but keeps only the low byte of the quotient, so with AC
over 200 the reduction can come out wrong (found 2026-11-01). Normal play may
never reach AC 200; check how high Moria8's AC can go, then either clamp AC to
200 there (VMS reduces at most all of the damage) or keep the full quotient,
with a test at the boundary. Moria8 truncates like Umoria; VMS rounds to
nearest (maintainer, 2026-11-01: leave the rounding as it is).

### Make 0d0 monster attacks explicit

Follow-up from the no-HP attack fix (2026-11-01):

- `mon_atk_hit` (`core/monster_attack.s`) passes the attack's dice count to
  `math_dice`, documented for 1-255 dice. A 0d0 attack (fear wails, thieves,
  and since 2026-11-01 the Banshee, Ghost and Liches' drain touches) deals no
  damage only because 0 loops 256 times, each `rng_range(0)` returning 0, and
  only the low byte of the `$0100` sum is used. Add an explicit `cpy #0` skip
  so that no longer rests on the wrap (a few bytes on every port;
  `test_monster_attack` t29-t30 cover the behavior today).

### Raise `MAX_MONSTERS` on the large-map ports, up to VMS's limit

**Maintainer, 2026-11-05.** Every port holds 32 live monsters
(`core/monster.s` `MAX_MONSTERS`). With the monster catalog a level can hold
no more species than live monsters, so the creature rows are 32 dungeon
species plus the 8 town creatures (40) on every catalog port. The 198x66
ports (C128, CX16, Apple IIe, and BBC Master) have the room for more, and
VMS's population on that map size reaches the 32-slot cap from about DL25
(`docs/MONSTER_CATALOG_DESIGN.md`, "Population on Moria8's maps").

Raise `MAX_MONSTERS` on those ports, never above VMS's limit: `max_malloc =
100 + 1` (VMS `constants.inc:107`; slot 0 unused, so 100 live monsters).
Umoria's `MON_TOTAL_ALLOCATIONS` is 125 (`monster.h:57`); stay at VMS's 100.
The species rows grow with it (`CAT_SLOTS = MAX_MONSTERS`), the 12-byte
monster records, the save blocks and every table scan (`cat_slot_in_use`,
the AI loop) grow too, and the generation cap of 26 (6 slots kept for
summons, breeders, new arrivals and pits) is revisited with it. About 200
resident bytes for 48 monsters, per the design doc's estimate.

### Split player haste and slow into separate saved counters

Moria8 now includes upstream player-slowing sources (`Potion of Slowness`
`#275`, `Staff of Slowness` `#361`, `of Slowness` ego boots, and the monster
`Slow Person` spell `MSF2_SLOW`), while `zp_eff_speed` (`$54`) still nets haste
(`> 0`) and slow (`< 0`) into a single signed timer so haste while slowed
cancels slow turn for turn (`docs/FEATURE_MAP.md` §3.1, §6.5). VMS Moria keeps
separate `fast` and `slow` counters that run concurrently and net each turn
(`potions.inc`).

Required work:

- Split haste and slow into separate saved counters as VMS does: a byte in the
  saved effect block (`$50-$5F` has none free, so a zero-page or main-RAM
  allocation the maintainer approves) and a save-format bump.
- Tests: stacking, haste while slowed, expiry messages, save/load.

### Faithful breath: what the limited version leaves out

Differences from pinned VMS Moria (and Umoria) left by the 2026-11-08 breath
work. The maintainer chose the limited version after the full one measured
about 900 B a port. Each is also a row in `docs/FEATURE_MAP.md`.

- **The ball.** VMS `spells.inc` `breath` is a radius-2 ball centred on the
  player (the 5x5 square without its corners). Moria8 hits the player only.
  - Monsters in the ball take the damage / (distance + 1), x2 if the element
    hurts them (cdefense frost 0x10, fire 0x20, poison 0x40, acid 0x80,
    light 0x100; about 200 of 279 creatures), / 4 if they breathe it. They
    wake, and one killed drops its treasure. The Balrog's death still wins,
    and the drop is placed at once, not after the player's next command.
  - Floor items of the element's set are destroyed (lightning: rings and
    wands; acid and fire: wooden and leather gear, staffs, scrolls, food,
    and potions for fire; frost: potions). Fire and acid also destroy open
    and closed doors.
  - VMS flashes `*` on the ball's squares.
  - The 2026-11-08 attempt cost about 761 B for this alone (review: about
    350 B in one 5x5 pass).
- **Pack damage** (`misc.inc` `inven_damage`). Each matching pack slot
  loses one item 2% of the time (VMS `randint(100) < 3`) for fire and acid,
  4% for frost (potions). Umoria adds lightning (rings, wands, staffs, 3%:
  "There are sparks coming from your pack!"). VMS's messages: "There is
  smoke coming from your pack!", "Something shatters inside your pack!",
  "There is an acrid smell coming from your pack!". Umoria also runs it from
  fire, acid, frost and lightning touches and the fire and acid traps, which
  Moria8 maps to plain damage. One shared routine: about 80 B, plus the
  item classification and the messages.
- **Hold Person texts.** VMS is silent when it paralyses, and says "You are
  unaffected..." to Free Action. Moria8 prints "The <name> paralyzes you."
  (as its other effect spells print their effect, MON-011) and reuses the
  chest trap's "You are unaffected.".
- **Recall.** A Hold Person cast marks recall's spell bit 0 (Cause Light
  Wounds). Recall shows only SPELLS: YES / NONE.

Acceptance target: each item decided as faithful (then implemented with tests
and a measured byte cost) or recorded as an intentional 8-bit difference.

### Align shared monster distance with upstream

Moria8's shared `monster_distance_to_player` currently returns Chebyshev
distance. VMS Moria and Umoria use `max(dx,dy) + floor(min(dx,dy)/2)`. The
shared helper currently controls both ordinary monster wake eligibility and
monster spell range, so changing it as part of a wake-pressure repair would
silently alter casting behavior without dedicated diagonal-range coverage.

Required work:

- Replace the shared distance helper with the upstream metric, including a
  defined saturation policy for C128's larger map dimensions.
- Audit every caller, especially `monster_wake_check` and
  `monster_can_cast`, before changing the helper.
- Add deterministic horizontal, vertical, and diagonal fixtures at every
  awareness and casting boundary.
- Decide separately whether visibility, infravision, projectile range, and
  group-wake radius should retain their current Chebyshev metrics or converge
  on the same upstream distance function.
- Preserve the C64/C128 resident layout boundaries.

Acceptance target:

- Monster wake eligibility and spell range use the upstream distance metric
  with explicit tests for diagonal boundaries and no regressions in visibility,
  targeting, or platform memory layout.

### Add Balrog victory and retirement flow

Product support and cross-port victory coverage are shipped: killing the Balrog
(`catalog_slot_is_balrog` / `CATALOG_BALROG_ID`, `core/monster_catalog.s`,
`core/combat.s` `combat_note_kill`, and `catalog_place_win_creature`) sets
`GAME_FLAG_WINNER`, prints the victory notice, blocks ordinary save-and-exit,
and routes `SHIFT+Q` through retirement, the royal overlay
(`score_death_screen`, `core/score.s`), and the winner high-score marker across
all seven ports (`test_balrog_victory.s`, `test_combat` `t41`, `test_bash` `t9`,
`test_score` `t12`, `test_main_loop` `t43-t44`, C128 `test_main_loop128`
`t33-t34`, Plus/4 `balrog_product_plus4`, and the Apple IIe, CX16, Atari 8-bit,
and BBC Master `balrog_victory` smoke scenarios).

Remaining work:

- Add focused C64/C128/Plus/4 coverage for the royal-retirement winner display
  (`score_death_screen` with `GAME_FLAG_WINNER`) and `GAME_FLAG_WIZARD +
  GAME_FLAG_WINNER` suppressing high-score insertion.

Acceptance target:

- Royal-retirement presentation and wizard-mode score suppression for a
  `GAME_FLAG_WINNER` character have automated Commodore coverage alongside the
  existing kill, save-block, and high-score tests.

### Split Home/store screen ownership

Phase 2 enabled `HOME_OVERLAY_SEPARATE` (`ovl.home`) across all seven shipping
ports: `home_draw_screen` (`core/ui_home.s`) and `store_draw_screen`
(`core/ui_store.s`) now share body macros (`core/ui_home_text.s`
`:StoreDrawSlotListBody`, `:StorePutGoldValueBody`) and draw their own titles
and footers independently in product builds.

Remaining cleanup:

- Retire the legacy `#if !HOME_OVERLAY_SEPARATE` fallback (`core/ui_home.s`,
  `core/ui_store.s`, `core/ui_home_text.s`) where `home_enter` still calls
  `store_draw_screen` and overwrites `STORE_MENU_ROW`.
- Drop the 3-space overwrite padding on `hm_menu_str`
  (`core/ui_home_text.s:178-180`) once nothing writes it over the Store menu.
- Switch `test_home_view` (`platforms/commodore/c64/tests/test_ui_views.s`) onto
  the `HOME_OVERLAY_SEPARATE` `home_draw_screen` path and assert that Home
  cannot inherit stale Store footer text or color residue.

Acceptance target:

- Store and Home draw their shared body without either view writing the other's
  footer in product or unit-test builds, and `!HOME_OVERLAY_SEPARATE` is
  retired.

### Optional: drop the SHIFT+Q quit confirmation to recover memory

`SHIFT+Q` asks "Do you really want to quit? Y/N" (added 2026-10-30 so the
game matches `docs/FEATURE_MAP.md`; any key but Y clears the question, no
turn passes). It costs about 43 bytes on every port: 22 in the Huffman table
(20 data, 2 index) and 21 of code in `core/game_loop.s`. If a port needs the room, it
can go.

Removing it:

- `core/game_loop.s`: the quit path back to a single `jmp !quit+`.
- `data/huffman_strings.txt`: drop `@QUIT_CONFIRM`; regenerate
  `core/huffman_data.s` and the C64 `test_subsystems.s` recall-bank
  fixture (its comment says how).
- Test harnesses: the quit answer (`test_quit_answer` in C64
  `test_main_loop.s`) and the type-ahead flush in both `test_input_wait_release`
  stubs, C64 `test_main_loop.s` and C128 `test_main_loop128.s` (and its
  `HSTR_QUIT_CONFIRM` stub), C64 test 50.
- `playtest/moria_playtest/disk.py`: the `quit_confirm` scenario;
  `docs/AI_PLAYTEST_DESIGN.md` §22.
- `docs/FEATURE_MAP.md`: say SHIFT+Q quits without confirmation.

### Loads the program-disk prompt does not cover yet

Since 2026-10-30 a required load that keeps failing asks for the program
disk by name and tries again (`asset_load_required`, resident
`asset_load_ask_for_disk`; `playtest-disk` `load_fail_town`). Still outside it:

- The Atari's boot load of `ATARI.BNK` halts with a flashing border: the
  prompt itself lives in the `RuntimeBanked` code that file brings.
- The C128's runtime payloads (`c128_load_runtime_prg`, with its own inline
  retry) have not been checked against a load that never succeeds.
- Only the Commodore ports run the prompt in a test (`load_fail_town`). The
  Apple IIe, Atari, BBC Master and X16 reach it too (the shared overlay,
  tier and string loads); on the X16 a file missing from the bundle asks
  for a disk there is none of.
- Room: the C64's fullest scripted test builds (dungeon-spell, detect-evil)
  end at `$BFF9`/`$BFFA`, six or seven bytes under `MAP_BASE`, and the
  Plus/4's (wand-selector, chest-open) at `$C7F7`/`$C7F3` (2026-10-31).

### Plus/4: why did the 1541 miss a LOAD handshake?

M6's Plus/4 round restarted two games: a KERNAL LOAD of `4.GEN` returned
FILE NOT FOUND with ST `$43` while the drive's status was `00, OK`, and the
same LOAD repeated succeeded (VICE true drive, JiffyDOS ROMs, deterministic
for Priest seed 1011 at step 2417). `asset_load_retry` now absorbs it.

The same family hit a command-channel read on 2026-10-30
(`playtest-disk` `save_overwrite`): the first byte came back `$58` with ST
`$42` while drive 8 held "00, OK", and drive 8's CPU was in its
disk-controller IRQ (`$F9D9`) as the transfer began. The stock ROMs passed;
where it lands moves with code layout. Rereading the command channel
cannot recover the byte: the drive goes on mid-message ("6," for "26,WRITE
PROTECT ON", and "1," for "21" would read as OK). So the status readers only
flag a read that timed out before any digit came (C64, C128, Plus/4;
2026-10-31), and only the probes that can OPEN their file again ask again,
up to three times: the save-slot list, `save_file_exists`, and the Plus/4
and C128 program-disk checks (`status_retry_resume`, `status_retry_slot`,
`status_lost_save`). A lost status after a save reads as a disk error
(`status_lost_save`, `status_lost_protected`). The C128 CLOSE wrapper and
the Plus/4 KERNAL call wrapper now clear carry: with it set, CLOSE leaves a
command channel open in the drive. Still open: whether JiffyDOS on real
hardware loses these bytes too. `C128ResidentDiskIo` has 60 bytes free after
`combat_append_blow_summary` moved to Default (2026-10-30).

### Byte recovery held back for speed or disk loads (2026-11-07)

The 2026-11-07 memory pass (for the potions of gain stat) applied every
candidate that kept the game as fast and loaded no more from disk. The
maintainer held these remaining two until they are needed ("hold off on any
that are not and backlog them"). Estimates are the memory analysis's, not
measured.

- **Phase-3 potion handlers into an overlay (~190 B resident on C64, Plus/4,
  Atari).** The eight special potions' handlers
  (`core/player_item_commands.s`, `!piq_*`, ~210 B) would run from
  `ItemActionsOverlay` or `ChestOverlay`, as on BBC, Apple and CX16. On ports
  without a cache, drinking one of them would then load an overlay from disk.
  A load-once home (Atari's `RuntimeBanked`, where the gain-stat effect went)
  costs no disk load, but C64's `RuntimeBanked` has 65 B free and Plus/4's needs a
  ROM-banking trampoline.
- **C128 save/load per-byte step (~68 B in `platforms/shared/save.s`).** The
  checksum, pointer and counter tail shared by `save_stage_from_ptr0_c128`,
  `load_unstage_to_ptr0_c128`, `save_stage_map_c128` and
  `load_unstage_map_c128` (`platforms/shared/save.s`) becomes one
  subroutine: 12 cycles more for every byte saved or loaded (~0.1-0.2 s a
  save, beside the disk time).

Acceptance target:

- Each is applied only when a feature needs the room, with its cost measured
  (cycles on the hot path, or the disk loads added) and accepted.

### Optional: C128 64 KB VDC auto-detection and full disk-asset caching

C128DCR (`8568`) and upgraded flat C128 (`8563`) machines provide `64 KB` of
physical VDC RAM (`$0000-$FFFF`, adding `+48 KB` at `$4000-$FFFF`), whereas
stock flat C128s provide `16 KB` (`$0000-$3FFF`). C128 never uses REU
(`reu_present = 0`). On `16 KB` VDC disk builds (`docs/C128_MEMORY_CONTRACT.md`
`C128M-015`, `platforms/commodore/c128/item_cat_vdc128.s`), Bank 1 RAM plus
`16 KB` VDC RAM (`$1100-$1FFF` and unused cell scanlines `8..15` at
`$2008-$3D2C`) already cache `128.CAT`/`128.CNM`/`128.CEX`, `ITEM.CAT`,
`128.HUFF`, and 8 of 12 `$E000` overlays, leaving only `ovl.storage`,
`ovl.chest`, `ovl.home`, `ovl.start`, `legalui` (plus `license,s` /
`source-offer,s`), and the `$AF00-$CFFF` `128.play`/`128.persist` modal-slot
pair (`~36 KB` total) on disk.

Hardware guardrail: toggling VDC Register 28 (`$1C`) bit 4 (`4416` 16K vs
`4164`/`4464` 64K DRAM row/column mux) alters row/column addressing across
`$0000-$3FFF` as well. The `64 KB` vs `16 KB` probe (`$1100` vs `$5100`
non-aliasing pattern + bit-flip test) must therefore run once at early cold
boot in `entry_main` *before* `JDLCHR` (`$FF62`) copies the `$2000-$3FFF`
charsets, screen/attribute init, and `ITEM.CAT` preload — restoring Reg 28
bit 4 = `0` immediately when `16 KB` aliases, and preserving Reg 28 bit 4 = `1`
across any subsequent `JDLCHR` call when `64 KB` is present.

Required work:

- Add an early-boot `64 KB` vs `16 KB` VDC probe (`vdc_64k_present` in
  `entry_main`); keep `16 KB` behavior (`C128M-015`) identical when
  `vdc_64k_present = 0` (and keep `C128_CARTRIDGE` asset reads on MD128 ROM).
- When `vdc_64k_present = 1` on disk builds: store `ITEM.CAT` contiguously at
  VDC `$4000+` (for a linear byte reader) and preload the remaining uncached
  `$E000` overlays (`OVL_STORAGE`, `OVL_CHEST`, `OVL_HOME`, `OVL_STARTUP`,
  `legalui`, and legal text streams if Help `L` / Title `A` also stay
  disk-free) plus `128.play` and `128.persist` into `$6000-$FFFF`, bypassing
  `disk_prompt_game` / `"INSERT PROGRAM DISK"` swaps so single-drive C128
  players can leave their Save Disk in Drive 8 after boot.
- Display `64KB VDC` vs `16KB VDC` on the C128 title/system-info readout
  (`title_show_sysinfo_banked`).
- Update `docs/C128_MEMORY_CONTRACT.md` (CPU + Physical VDC records and
  overlap `.assert`s in `memory128.s`) and add headless `x128` runtime smokes
  covering both `-vdc16k` and `-vdc64k`, including single-drive save/resume
  without program-disk reinsert on `-vdc64k`.

Acceptance target:

- Stock `-vdc16k` C128 disk builds behave identically to `C128M-015`, while
  `-vdc64k` disk builds report `64KB VDC`, perform zero post-boot program-disk
  reads across all overlays and `128.play`/`128.persist` transitions, and
  complete single-drive Drive 8 save/load/resume cycles without program-disk
  swaps.

## Apple IIe

### Investigate AppleSqueezer accelerator incompatibility

Low priority. The Apple IIe build boots and completes character creation on an
Apple IIgs (IIe mode) but crashes on town entry when the machine has an
AppleSqueezer accelerator installed. The same build works on the same machine
with the original CPU, and passes the full MAME `apple2ee` harness.

The crash screen shows the town map left mostly solid wall with a few carved
building rectangles plus garbage status rows, consistent with generation dying
partway rather than a video-mode fault. The game's hardware surface is standard
IIe only (80STORE, RAMRD/RAMWRT, 80COL, PAGE2, INTC3ROM, kbd strobe, speaker,
`$C01F` read, and firmware AUXMOVE at `$C311`), so the likely cause is an
accelerator timing or softswitch/aux-bank sequencing difference affecting the
ZP aux thunks or AUXMOVE switch-preservation assumptions
(`platforms/apple2/memory_aux.s`).

Possible investigation path:

- Reproduce under MAME `apple2gs` or with accelerator-emulating config to get
  harness visibility instead of hardware round-trips.
- On hardware, Ctrl+OA+Reset at the freeze and record PC to distinguish wild
  jump from hang.

Acceptance target:

- Apple IIe build reaches town and plays on an AppleSqueezer-equipped machine,
  or the incompatibility is root-caused and documented as wontfix.

## Commander X16

### Check the key-release waits on real Atari and X16 hardware

The 2026-10-30 key-release waits (a prompt listens only once every key is up,
and keys typed ahead or rolled over are dropped) were checked only in
emulators. Two hardware details need a real machine:

- Atari 8-bit: `input_wait_release` (`platforms/atari8/input.s`) settles
  about 20 ms after the keys look up, because POKEY reported a key held under
  a released one about 8 ms later in MAME. Check a real POKEY's delay fits.
- Commander X16: `cx16_key_event` (`platforms/cx16/input.s`) tracks keys from
  the KERNAL's `keyhdl` key-down and key-up events. A PS/2 Pause key (the
  X16's RUN/STOP) sends no separate key-up; if the SMC firmware reports none
  either, each STOP leaves its key marked down and the next prompt waits the
  full 0.25 s. x16emu sends both events.

Acceptance target:

- On real hardware: SHIFT+Q, then Y pressed while Q is still down and Q let
  go first, leaves "Do you really want to quit? Y/N" waiting (Atari and X16);
  pressing STOP and then opening help shows no 0.25 s pause (X16).

## Testing Infrastructure

### Document build dependencies and test a fresh-machine build

`README.md` now lists the required build tools, auto-downloaded toolchains, and
ROM/emulator environment variables (`A2ROMS`, `X16EMU`, `X16ROM`, `ATARI8ROMS`,
`BBCMROMS`). However, it still lacks per-host package names/minimum versions,
fresh-machine `make test` verification, and lists `Pillow` under "Optional tools"
even though `tools/png_to_ppm.py` requires Pillow on Linux for C64/C128 boot art.
No `docs/BUILDING.md` or `make check-deps` target exists yet.

Required work:

- Build and run `make -j8 -O test` on an empty install of each supported host
  (at least Arch, Debian/Ubuntu and macOS), recording every package and minimum
  version each one needs (including moving Pillow out of optional on Linux).
- Put per-host package names and minimum versions into `README.md` or a linked
  `docs/BUILDING.md`.
- Consider a `make check-deps` target that names each missing tool and its
  package up front, instead of failing midway through a gate.

Acceptance target:

- A fresh machine with only the documented packages installed and the ROM
  variables set builds every port and passes `make -j8 -O test` with no
  undocumented step.

### Playtester: learn creature speed and stationarity by observation

The AI playtester's `playtest/moria_playtest/knowledge.py` reads the shipped
creature tier data as player knowledge: names and native levels (look
identification, attacker names), glyphs, speed (`fast_creatures`, round 14)
and the "moves only to attack" flag (`stationary_glyphs`, round 9). The
original M3 plan (`docs/AI_PLAYTEST_DESIGN.md` §14.3 item 4) was to learn
stationary monsters by watching their position over turns. The maintainer
kept the data-driven version for M3 and asked for it to be reworked later
(§14.6 item 7, 2026-10-22).

Required work:

- Learn "never moves" per creature name (or glyph) from observation: a
  creature seen at the same tile across N turns while the player is in view.
- Learn "faster than the player" from observation: more than one move or
  attack per player turn.
- Keep names and levels from the shipped data (or decide separately), and
  keep the brain's uses unchanged (`stationary`, `chased`, hazards).
- Re-qualify `reach_dl5` and `clvl5`; both must stay at or above the 16/20
  bar (their frozen suites).

Acceptance target:

- `knowledge.py` no longer reads speed or movement flags, and M3's frozen
  suites still pass.

### Playtester: block reads in the `x16emu` testbench

The Commander X16 playtest backend (`playtest/moria_playtest/x16.py`) drives
`x16emu -testbench`, whose only read is `RQM`: one byte per command and
reply line. Reading the 198x66 map every step cost each X16 driver a full
core (M6, 2026-10-28). `X16Game.read_map` now keeps a copy and rereads the
view and the character's room, which cut map reads about sixfold, but the
screen (VERA text, through the data port, several commands a cell) and every
other read still go a byte at a time. The emulator is open source; a block
read in the testbench would make all of them one request. Maintainer,
2026-10-28: prepare a patch.

Done 2026-10-28: a local `x16emu` commit (base `77f2bab`) adds `RQB <addr>
<len>` (CPU space, `RQM`'s read path, one hex line), `RQV <vaddr> <len>`
(VRAM, VERA registers untouched) and `STB <addr> <hex>`, with selftests.
With `PLAYTEST_X16_BLOCK=1`, `x16.py` checks for them (`RQB 0000 1`; a stock
build answers `ERR`, an error then) and uses them: about 1.9 times the steps
a second, half the driver CPU. By default it reads a byte at a time, as a
stock x16emu needs.

Required work:

- Offer the patch upstream (`X16Community/x16-emulator`); the maintainer
  decides on submission.
- Until it ships in a release, block reads need the patched build in
  `X16EMU` and `PLAYTEST_X16_BLOCK=1`; the default stays byte at a time.

Acceptance target:

- The block reads are in a released `x16emu`.

### Normalize cross-platform save schema and versioning

Save Format V2 (`$21` across all seven `hal/storage_policy.s` files) unified the
numeric save-version sequence and retired pre-V2 migration branches, but six of
the seven ports (`80x48` C64 and Atari 8-bit alongside `198x66` C128, Apple IIe,
CX16, and BBC Master) still share the identical `"MORIA01"` magic prefix with no
explicit platform/map-layout identifier in the header (only Plus/4 uses
`"MORIA+4"`).

Required work:

- Add an explicit platform/map-layout identifier in the save header so a save
  written for a different map geometry (`80x48` vs `198x66`) is rejected by
  header rather than failing only at EOF/checksum.
- Centralize format milestones in one shared manifest once post-release
  migrations return.
- Add cross-platform schema fixtures and negative tests for wrong-platform,
  unknown-version, truncated, and malformed-but-checksummed saves.

Acceptance target:

- Every new save carries an unambiguous global schema version and platform/layout
  identity, and one manifest documents and tests the format and negative cases.

### Archive legacy-version save fixtures for migration testing

Save-version validation is covered by unit tests (`test_save.s`), and
pre-release Save Format V2 (`$21`) currently accepts only `SAVE_VERSION`
(`save_version_supported`), but once shipping releases introduce
backward-compatible save upgrades, no test loads a genuine binary save produced
by a historical release. A stream-alignment slip between versions would only
surface as garbled inventory/state when a player upgrades with an old save.

Required work:

- Capture real save files from shipping releases of each platform at each
  supported legacy version and commit them as test fixtures.
- Add a per-platform harness step that loads each legacy fixture, migrates,
  saves, and verifies key invariants (player stats, inventory ids/quantities,
  dlvl, gold) against recorded expectations.
- Wire the fixtures into the existing save tests rather than a parallel
  runner.

Acceptance target:

- Every supported save-version upgrade path has at least one archived
  binary fixture that loads cleanly on the current build across all supported
  platforms.

### Collapse disk matrix execution into one shared runner

The disk test catalog now defines strict C64, C128, and Plus/4 coverage for the
named disk scenarios, but the execution layer is still platform-specific. The
matrix blocks on the same scenario IDs across all three platforms, while the
underlying shell functions, monitor labels, scripted input, and media-swap
adapters remain separate enough to drift.

This is architecture debt, not currently missing release-gate coverage.

Required work:

- Replace the three product-disk shell/harness paths with one Python scenario
  executor.
- Keep platform differences behind small adapters: emulator command/options,
  product image path, symbol names, scripted input encoding, and drive attach
  behavior.
- Move prompt/event recording into one common contract so event order, exact
  counts, no-repeat assertions, screen text, and disk-image proof are checked
  uniformly.
- Remove scenario-name translation where practical so the catalog scenario ID
  is the runnable test identity instead of mapping to three differently named
  platform smokes.
- Reduce C128-specific test-only hooks once the common executor can drive the
  same product flow deterministically.
- Keep `make test-disk` behavior and scenario coverage unchanged during the
  refactor; this should be a harness cleanup, not a product-behavior change.

Acceptance target:

- `make test-disk` runs the same scenario executor for C64, C128, and Plus/4,
  with only adapter data varying by platform, and no platform can silently
  satisfy a scenario through a materially different test flow.

### Playtester: disk scenarios on the MAME ports and the X16

`make playtest-disk` (`playtest/moria_playtest/disk.py`,
`docs/AI_PLAYTEST_DESIGN.md` §22) covers C64, Plus/4 and C128 through
VICE's monitor. The Apple IIe, Atari 8-bit and BBC Master (MAME) and the X16
need their own media swapping (MAME Lua image load/unload; the X16 host
filesystem) and fault injection at their `hal_asset_load_prg_header`, with
each port's save-disk flow. Also missing on every port: the hall of fame
written on death or retirement.

## Rendering Performance (Px)

Tracked candidates from the 2026-07-25 cross-platform render performance
audit (hand-counted cycle estimates; full analysis in
`docs/APPLE2_PORT.md` and `docs/C128_PERFORMANCE.md`):

- **P7** — VDC block-fill for `screen_clear` / `screen_clear_row` (C128).
  **BACKLOGGED** (maintainer, 2026-07-28). Revisit the reverted "Opt 5";
  requires root-causing the past character-creation crash first.
- **P9** — Burst variant of `render_single_tile` for C128 local-area
  updates (batch consecutive cells under one VDC address setup).
  **BACKLOGGED** (maintainer, 2026-07-28). ~400 -> ~45 cy/cell on the
  per-step hot path.
- **P10** — Mirror the Huffman decode tree (`huff_tree_left` +
  `huff_tree_right`, 112 B) into resident Bank 0 RAM (C128). Today every
  tree-node read crosses into Bank 1 through the MMU (~82 cy/read, ~16 ms
  per 30-char message); a resident mirror eliminates ~84% of those
  switches during text rendering. Costs 112 resident bytes on the
  tightest-resident platform and duplicates shared data, so it needs a
  C128 memory-contract budget check first. (Perf review, 2026-08-20.)

Completed: P1 (glyph/item scan early-outs), P2 (A2 AUX row block read),
P3 (C128 leftward block-copy + V-strip burst), P4 (A2 scroll-delta
renderer + V half-row overflow fix), P5 (immediate tile render at mark
time + cheap-path scene dispatch), P6 (A2 128-byte staged `a2_map_char`
table), P8 (A2 parity branch before `a2_map_char`).

## Data Width

### Audit byte-clamped rolls that could use the 16-bit helpers

The monster door bash roll showed `math_multiply` + `rng_range_word` make
16-bit probability math cheap (~25 bytes). Some existing rolls/thresholds
may have been byte-clamped or table-approximated for lack of that pattern;
audit call sites of `rng_range` where the upstream oracle uses
`randint(n)` with n > 255 (or products like `(hp+1)*80`) and convert the
ones where fidelity matters. Started from the door-bash design discussion
(2026-09-02).

