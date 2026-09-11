# Backlog

Durable future work that is too concrete for design philosophy and too
unreleased for release notes.

## Gameplay & Core Engine

### Stack identical inventory items (spikes first)

Upstream Moria/Umoria merge identical items on pickup (`inven_carry` merges
matching TV/subval entries, adding quantity), so iron spikes, food, oil, and
similar consumables occupy one slot with a count. Moria8's `inv_add_item`
(`core/item.s`) has no merge machinery at all: every item, including each
individual Iron Spike (item 135), consumes a whole carried slot. The
`item_defs.s` "stacks" claim was a comment bug (fixed 2026-09-10); this entry
tracks the missing behavior.

Player-visible cost is concentrated on spikes: jamming doors is a
spike-per-attempt mechanic, and the general store restocks spikes at
`si_qty = 1` per shelf slot (`store_restock_overlay.s`), so stocking up means
buying many single-spike entries that each eat a pack slot, and spike shelf
slots can crowd out food/oil in a small inventory.

This is a design call, not a bug fix: one-slot-per-item is internally
consistent (nothing in the port stacks), and adding merge machinery touches
pickup, store buy/sell, drop, inventory display, and save format.

Required work:

- Decide the stacking rule: merge identical items generally (upstream parity),
  or merge only a whitelist (spikes/food/oil), or keep one-per-slot and
  instead sell spikes in bundles (qty 5/10 per entry) to fix only the
  store/pack pressure.
- If merging: define identity (which of p1/to_hit/to_dam/flags/ego must
  match), cap quantities at 255, and decide how partial pickups from a full
  stack behave.
- If bundling only: pick the bundle size and update `store_restock_overlay.s`
  plus spike pricing/weight so a bundle is coherent.
- Regression coverage for pickup/buy/sell/drop of stackables, including the
  full-pack and stack-overflow edges, and save/load round-trip of stacked
  quantities.

Acceptance target:

- Spikes no longer consume one pack slot each (and, if general merging is
  chosen, identical consumables merge per the documented rule), with store
  stock not starving food/oil, and no change to non-stackable item handling.

### Add upstream monster sleep immunity

VMS Moria and Umoria represent magical sleep immunity independently from a
creature's ordinary starting sleep value. Their `CD_NO_SLEEP` defense prevents
Sleep I, Sleep II, Sleep III, Sanctuary, and other monster-sleep effects from
changing the monster's sleep state. Moria8 now implements shared level
resistance for its sleep spell family, but its one-byte `cr_mflags` table has no
remaining bit for `CD_NO_SLEEP`. Treating `cr_sleep = 0` as immunity would be
incorrect because natural alertness and magical sleep immunity are separate
upstream properties.

Required work:

- Add a compact independent sleep-immunity representation without overloading
  `cr_sleep` or changing existing `cr_mflags` meanings.
- Update `tools/parse_creatures.py` and every generated creature tier payload
  to preserve upstream `cdefense & $1000` / `CD_NO_SLEEP` data.
- Update tier loading, embedded test rosters, table-size assertions, C128 cache
  ownership, and disk payload accounting for the selected representation.
- Route every monster-sleep producer through one shared resistance check that
  handles both monster level and categorical sleep immunity.
- Leave immune monsters' `MF_AWAKE` and `MX_SLEEP_CUR` unchanged and report the
  effect as ineffective through the existing sleep feedback path.
- Decide whether and how observing immunity updates Moria8 monster recall;
  Umoria records observed `CD_NO_SLEEP` for visible monsters.
- Add production-path C64, C128, and Plus/4 tests for susceptible, level-
  resistant, and immune monsters across directional, adjacent, and visible-all
  sleep effects, including an immune monster with a nonzero natural sleep
  value.
- Preserve all resident, overlay, tier-cache, and banked-payload memory
  assertions.

Acceptance target:

- Every shipped creature carrying upstream `CD_NO_SLEEP` is immune to magical
  sleep on all three platforms, ordinary sleep values retain their original
  meaning, and susceptible creatures continue to use the shared level-
  resistance behavior.

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
- Preserve the C64/C128 resident layout boundaries; both currently have only a
  five-byte margin at their primary resident boundary.

Acceptance target:

- Monster wake eligibility and spell range use the upstream distance metric
  with explicit tests for diagonal boundaries and no regressions in visibility,
  targeting, or platform memory layout.

### Implement invisible monster visibility

The catalog includes the upstream invisible-movement roster, including Clear
Icky-Thing, Poltergeist, ghosts, spirits, quasits, oozes, Quylthulgs, the
Invisible Stalker, Evil Iggy, and the Balrog. The Ring of See Invisible plus
Sense Invisible already expose player-side see-invisible state, but monster
invisibility is not currently preserved or consumed: the generated monster
flags do not carry the upstream invisible-movement bit, and `PFLAG_SEE_INVIS`
does not affect monster visibility, rendering, detection, or targeting.

Required work:

- Add an explicit invisible-monster flag or generated sidecar without
  overloading `CF_INFRA` or changing the existing one-byte monster-flag budget
  unsafely.
- Preserve the upstream invisible-movement bit for every affected creature in
  the source data and generated tier data.
- Update the authoritative monster visibility producer so ordinary LOS hides
  invisible monsters unless the player has Ring of See Invisible or an active
  Sense Invisible effect.
- Define and preserve the distinction between ordinary visibility, infravision,
  detection, inspection, and targeting; revealing a monster must not silently
  reveal terrain or imply Detect Monsters.
- Ensure renderers, target selection, melee/ranged attacks, and monster
  inspection consume the same authoritative visibility state.
- Add production-path C64, C128, Plus/4, and Apple IIe coverage for hidden and
  revealed Invisible Stalkers, including ring equip/remove and temporary Sense
  Invisible expiry.
- Preserve resident, overlay, tier-cache, save/load, and platform memory
  assertions.

Acceptance target:

- Every upstream invisible creature remains hidden and unavailable to ordinary
  targeting without See Invisible, becomes visible and targetable with the
  ring or active spell, retains normal LOS/terrain rules, and behaves
  consistently on every platform.

### Expand unsupported monster special attacks

Moria8 maps several Umoria monster attack effects into compact substitutes.
For example, fire/cold/lightning, blindness, stealing, disenchant, eating food,
eating light, eating charges, stat drains, and experience drain are not all
implemented as distinct effects.

Required work:

- Prioritize high-impact special attacks from the shipped monster roster before
  expanding the full monster catalog.
- Add compact effect handlers for each accepted attack type.
- Update `tools/parse_creatures.py` so imported data maps to real handlers
  instead of normal/poison approximations when support exists.
- Add per-effect tests for damage/status, messages, inventory/light/resource
  mutation, and save/load impact where relevant.

Acceptance target:

- Shipped monsters no longer silently collapse high-impact upstream attacks
  into misleading normal attacks.

### Complete auto-rest disturbance model

Moria8 now has a first-pass `CTRL+R` rest-until-recovered command. It keeps `.`
as one-turn rest, `R` as Read Scroll, and `SHIFT+R` as Refuel. The current
implementation advances ordinary rest turns until HP and mana are full, clears
search mode when started, stops on cancel input, and stops when a message asks
for player attention. Existing C64/C128 tests cover full-recovery no-turn
behavior, HP/mana recovery, attention-message interruption, held-key
interruption, and search-mode clearing.

Remaining polish:

- Add an explicit disturbance flag so auto-rest can stop on silent-but-dangerous
  state changes without relying on `zp_msg_flags`.
- Stop on visible hostile monster activity even when the monster only moves and
  no attack/spell message is generated.
- Stop on player displacement, newly discovered objects/features, hunger
  warnings, and other attention-worthy events through one shared disturbance
  path.
- Add compact status text such as `Rest *` or `Resting` if resident memory or an
  overlay-owned display path can afford it.
- Keep C128 resident play below `$D000`.

### Disturb the player mid-turn when a monster bursts a door

Upstream Umoria calls `playerDisturb(1,0)` when a monster bursts a door
(`monster.cpp::monsterOpenDoor`), interrupting rest/run immediately.
Moria8 prints the same unconditional message, and `huff_print_msg` sets
`zp_msg_flags`, which already breaks auto-rest and running at the
post-turn check (`core/game_loop.s` rest loop and `run_post`). The only
residual delta is timing: upstream's disturb fires mid-step, so a
multi-tile run could in principle continue one step further here before
stopping. Minor gameplay parity; no correctness issue.

Required work:

- If pursued, add an explicit disturb hook at the two burst-print sites
  in `core/monster_ai.s` and verify rest/run interruption against the
  upstream mid-step timing.

### Expand monster catalog toward full Umoria roster

Moria8 currently ships with 120 selected creatures from Umoria's 279-creature
catalog. Expanding toward the full roster requires more than adding data files.

Required work:

- Redesign creature tier partitioning beyond the current four dungeon tiers.
- Add stable global creature IDs instead of relying only on active-tier-local
  creature indices.
- Rework monster recall persistence around global creature identity.
- Adjust C128 tier cache/preload ownership or switch to selective tier loading.
- Review C64 disk/REU tier loading for larger or more numerous tier files.
- Expand imported monster attack/spell behavior where current mappings collapse
  Umoria effects into simplified Commodore behavior.

Acceptance target:

- Full or substantially expanded Umoria creature roster can appear at the
  appropriate dungeon depths without breaking C64/C128 memory, loading, save,
  recall, or monster behavior contracts.

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

## User Interface & Presentation

### Split Home/store screen ownership

The Home screen currently reuses the store renderer, then overrides the store
footer. That previously produced stale footer text such as `Q)uituit` because
the store renderer drew row 18 first and Home replaced it with shorter text
afterward. That visible bug is fixed: Home clears row 18 before drawing the Home
footer. The remaining issue is architectural ownership. Home should not call a
renderer that draws the wrong footer in the first place.

The broader screen-clear audit was handled during the v1.1.0 release-candidate
work. Title entry now has an explicit full-screen clear and below-menu clear
contract, C128 title-cache redraws use the same contract, and modal gameplay
restore uses the platform-safe full-screen clear path. The remaining cleanup is
the older Home/store renderer ownership problem.

Required work:

- Split shared store/Home drawing so the item/body layout and footer/menu
  drawing have separate ownership.
- Remove the Home-specific row-clear patch once Home no longer calls a renderer
  that draws the wrong footer.
- Add focused regression coverage proving Home cannot inherit stale Store footer
  text or color residue.

Acceptance target:

- Store and Home draw their shared body without either view writing the other's
  footer, and no Home path depends on clearing over stale Store text.

### Promote `F8` to an in-game Version/System Info command

The C64 product currently has a hidden diagnostic command for proving C64
Ultimate turbo behavior. The polished player-facing command should use `F8` and
map to the dormant `CMD_VERSION` command slot. This should eventually become a
real cross-platform Version/System Info command instead of a one-off C64U probe.

The command is likely text-heavy enough to justify a platform-owned overlay or
paged modal rather than forcing all details into resident message-line code.

Required work:

- Define the shared `F8` command behavior across C64, C128, and Plus/4.
- Show game version/build identity, platform, save-format version, and relevant
  runtime hardware details.
- On C64, include machine identity, KERNAL revision, REU size, C64 Ultimate
  detection, turbo-register availability, and optionally the measured turbo
  probe result.
- On C128 and Plus/4, show platform-appropriate equivalents without implying
  unsupported C64U/REU capabilities.
- Decide whether the implementation lives in an existing UI overlay or a new
  dedicated diagnostics/version overlay.
- Preserve the current hidden C64U timing probe until it is replaced by the
  polished command.
- Add focused tests for command routing and platform-specific displayed fields.

Acceptance target:

- Pressing `F8` in gameplay opens a clear Version/System Info view on every
  supported Commodore platform, with enough diagnostic detail for user support
  and hardware-feature verification.

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

### Friendlier Commodore I/O error messages

The current storage HAL diagnostics preserve useful raw data, but the in-game
error text is still too developer-oriented on space-constrained targets. For
example, `Disk error! 74` correctly reports the drive status code, but it should
also tell a player that the drive is not ready and what to check.

The C64 bootloader has an even earlier version of this problem: it hardcodes
the program disk to device 8, so booting with the disk attached as drive 9 can
fall back to BASIC with no useful explanation before the main game's disk setup
or storage diagnostics exist.

Required work:

- Add a compact C64 bootloader error path for main-program load failure that
  tells the player to attach the boot disk as drive 8, or otherwise reports a
  clear load failure before returning to BASIC.
- Keep raw diagnostic bytes available: DOS status, KERNAL `$ST`, phase, and
  device number.
- Add a compact platform-owned classifier that maps common storage failures to
  player-facing text.
- Preserve the raw fallback for unmapped failures so debugging does not regress.
- Avoid bloating resident code or destabilizing C64/C128 storage behavior.
- Cover C64, C128, and Plus/4 with storage-error tests or smoke cases.

Acceptance target:

- Common failures such as no disk/drive not ready, write protect, disk full,
  missing file, and wrong save disk show clear end-user messages while retaining
  enough diagnostic detail for debugging.

## Platform & Architecture

### Sweep platform-specific inlines in core/ behind HAL macros

`core/` currently contains a few direct platform conditionals instead of HAL
macros: `#if APPLE2 jsr mmu_safe_map_write_ptr1` in `core/ui_messages.s`
(message-history writes) and `#if C128_PRODUCT_OVERLAY_RUNTIME jsr
mmu_common_copy_map_row` plus `SCREEN_RAM,y` reads in
`core/dungeon_features.s` (`place_secrets` row scan). Both work and are
assert-guarded, but they break the convention that core stays
platform-agnostic (`docs/CROSS_PLATFORM_STRATEGY.md`).

Required work:

- Introduce a HAL write macro (e.g. `:HalAuxWritePtr1()`) defaulting to
  `sta (zp_ptr1),y` and overridden by Apple II to the aux thunk; same
  pattern for a row-read/scan macro covering the C128 bank-copy path.
- Sweep both call sites; no behavior change, so existing gates
  (`make test`, `make test128`) suffice.

Acceptance target:

- No `#if <PLATFORM>` platform calls remain in the touched core modules;
  all four platform builds and test gates stay green.

### Overlay callers of the gameplay-view restore can be evicted mid-flow

The C64/Plus4/A2 gameplay-view restore (`ui_view_redraw_gameplay_view`,
resident) calls `tier_restore_after_overlay`, which can load tier data
into the shared `$E000` window. Modal overlays whose code lives in that
window (wizard restore helpers, spell/item modal exit paths) continue
executing there after the load — the window then holds tier data, not
code, so the continuation is wild. Today this only fires when the tier
is stale (after a tier-load failure, `current_tier=0`); the normal
in-range path skips the load. Hardening options: move the small restore
helpers resident, or have the restore reload the caller's overlay
before returning. Exposed by the wizard-teleport freeze; not triggered
in normal play once the tier always matches dlvl.

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

### Apple IIe: Investigate AppleSqueezer accelerator incompatibility

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

## Rendering Performance

Tracked candidates from the cross-platform render performance audit
(cycle estimates; detailed analysis in `docs/APPLE2_PORT.md` and
`docs/C128_PERFORMANCE.md`):

### P7 — VDC block-fill for `screen_clear` / `screen_clear_row` (C128)

Revisit the reverted "Opt 5"; requires root-causing the past
character-creation crash first.

### P9 — Burst variant of `render_single_tile` for C128 local-area updates

Batch consecutive cells under one VDC address setup. ~400 -> ~45 cy/cell on
the per-step hot path.

### P10 — Mirror Huffman decode tree into resident Bank 0 RAM (C128)

Mirror the Huffman decode tree (`huff_tree_left` + `huff_tree_right`, 112 B)
into resident Bank 0 RAM. Today every tree-node read crosses into Bank 1
through the MMU (~82 cy/read, ~16 ms per 30-char message); a resident mirror
eliminates ~84% of those switches during text rendering. Costs 112 resident
bytes on the tightest-resident platform and duplicates shared data, so it
needs a C128 memory-contract budget check first.

## Data Width & Math

### Audit byte-clamped rolls that could use the 16-bit helpers

The monster door bash roll showed `math_multiply` + `rng_range_word` make
16-bit probability math cheap (~25 bytes). Some existing rolls/thresholds
may have been byte-clamped or table-approximated for lack of that pattern;
audit call sites of `rng_range` where the upstream oracle uses
`randint(n)` with n > 255 (or products like `(hp+1)*80`) and convert the
ones where fidelity matters. Started from the door-bash design discussion
(2026-09-02).

## Testing Infrastructure

### Normalize cross-platform save schema and versioning

The shared serializer currently interprets a platform-local version byte:
C64 and Apple IIe use the `$0f` lineage, C128 uses the `$10` lineage with
platform-specific migrations, and Plus/4 uses the `$01` lineage. This preserves
existing saves but makes one shared format harder to audit because the same
schema milestone has a different numeric version on each platform.

Required work:

- Define one global save-schema version sequence and an explicit platform/layout
  identifier for data that cannot be shared across map sizes or memory models.
- Inventory every existing platform-local version and map it to the equivalent
  global schema and platform-specific migration steps.
- Preserve loading of every still-supported legacy version; do not renumber
  persisted versions in place or infer platform solely from record length.
- Centralize format milestones so shared serialization code does not depend on
  independently numbered platform constants.
- Add cross-platform schema fixtures and negative tests for wrong-platform,
  unknown-version, truncated, and malformed-but-checksummed saves.

Acceptance target:

- Every new save carries an unambiguous global schema version and platform/layout
  identity, all supported legacy saves migrate correctly, and one manifest
  documents and tests the complete format history.

### Archive legacy-version save fixtures for migration testing

Save-version bumps (e.g. `SAVE_DOOR_STATE_VERSION`, 2026-09 doors phase) are
covered by unit tests (`test_save.s` legacy-stream alignment, zeroed door
table on old versions), but no test loads a genuine binary save produced by a
historical release. A stream-alignment slip between versions would only
surface as garbled inventory/state when a player upgrades with an old save.

Required work:

- Capture real save files from the last release of each platform (C64/C128/
  Plus/4 disk images, Apple IIe ProDOS save) at each still-supported legacy
  version and commit them as test fixtures.
- Add a per-platform harness step that loads each legacy fixture, migrates,
  saves, and verifies key invariants (player stats, inventory ids/quantities,
  dlvl, gold) against recorded expectations.
- Wire the fixtures into the existing save tests rather than a parallel
  runner.

Acceptance target:

- Every supported save-version upgrade path has at least one archived
  binary fixture that loads cleanly on the current build on all four
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
