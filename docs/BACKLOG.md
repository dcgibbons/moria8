# Backlog

Durable future work that is too concrete for design philosophy and too
unreleased for release notes.

## Commodore Ports

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

### Add classic Moria chests

Moria8 currently has floor objects, traps, doors, searching, opening, bashing,
and direct floor-trap disarm, but it does not yet implement gameplay chests.
This is a real gap against both local upstream references: Umoria and VMS-Moria
have chest object types, locked/trapped chest state, chest trap effects, open
and bash handling, and `D <Dir>` disarm support for found trapped chests.

Required work:

- Add chest object definitions and generation/drop rules matching classic Moria
  scale: small/large wooden, iron, and steel chests.
- Represent chest state compactly: locked, trapped, found trap, opened/ruined,
  trap payload flags, and any contents/depth data needed for rewards.
- Extend Search/Find Traps so trapped chests can reveal their trap state.
- Extend Open so locked chests use disarm/pick-lock ability and trapped chests
  can trigger their trap when opened.
- Extend Bash so chests can be forced open, with the classic risk of ruining
  contents and without implicitly disarming traps.
- Extend Disarm so `D <Dir>` handles visible/found trapped chests separately
  from floor traps.
- Implement chest trap effects from the classic set where feasible: lose STR,
  poison, paralysis, summon, explosion, and multi-trap combinations.
- Decide and document how chest contents are stored within current floor-item
  constraints before adding broad generation.
- Add C64/C128 focused coverage for search reveal, open locked chest, open
  trapped chest trigger, successful disarm, failed disarm, bad-failure trigger,
  bash open/ruin behavior, and save/load persistence.

Acceptance target:

- A generated or placed chest can be found, searched, opened, bashed, disarmed,
  trapped, looted, ruined, and saved/loaded with behavior consistent with
  Umoria/VMS-Moria within Moria8 memory limits.

### Split Home/store screen ownership

The Home screen currently reuses the store renderer, then overrides the store
footer. That produced stale footer text such as `Q)uituit` because the store
renderer drew row 18 first and Home replaced it with shorter text afterward.
The immediate fix clears row 18 before drawing the Home footer, but the cleaner
design is to stop making Home call a renderer that draws the wrong footer in the
first place.

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

### Promote `V` to an in-game Version/System Info command

The C64 product currently has a hidden `V` diagnostic command for proving C64
Ultimate turbo behavior. That key was previously unused in gameplay and maps to
the dormant `CMD_VERSION` command slot. This should eventually become a real
cross-platform Version/System Info command instead of a one-off C64U probe.

The command is likely text-heavy enough to justify a platform-owned overlay or
paged modal rather than forcing all details into resident message-line code.

Required work:

- Define the shared `V` command behavior across C64, C128, and Plus/4.
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

- Pressing `V` in gameplay opens a clear Version/System Info view on every
  supported Commodore platform, with enough diagnostic detail for user support
  and hardware-feature verification.

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
