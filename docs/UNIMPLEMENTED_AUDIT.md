# Unimplemented Feature Audit

> [!NOTE]
> **Updated for the 7-Platform / 5-Cartridge Codebase & Superseded by [`docs/FEATURE_MAP.md`](FEATURE_MAP.md):**
> This document originated as a pre-`v1.5.0` Commodore parity tracker. Most
> items below have since shipped across all seven ports (**Commodore 64**,
> **Commodore 128**, **Commodore Plus/4**, **Apple IIe**, **Commander X16**,
> **Atari 8-bit**, and **Acorn BBC Master 128**) and five cartridge editions
> (`moria8-c64.crt`, `moria8-c128.crt`, `moria8-plus4.crt`, `moria8-cx16.crt`,
> `moria8-atari8.car`). Consult [`docs/FEATURE_MAP.md`](FEATURE_MAP.md) as the
> authoritative, exhaustive feature and parity database.

Verdicts:

- `Implemented`: present in product code and covered across all seven ports.
- `Partial`: present, with a documented platform or branch gap.
- `Missing`: not implemented in Moria8.
- `Approximation`: intentionally adapted 8-bit behavior, not byte-faithful Umoria.

| Area | Current Moria8 Status | Verdict | Evidence | Follow-Up / Reference |
| --- | --- | --- | --- | --- |
| **Seven platforms & five cartridges** | Disk/archive builds ship for all 7 ports (`c64`, `c128`, `plus4`, `apple2`, `cx16`, `atari8`, `bbcmaster`) alongside 5 read-only ROM cartridges (`c64`, `c128`, `plus4`, `cx16`, `atari8`). | `Implemented` | `Makefile`, `platforms/*/`, `docs/FEATURE_MAP.md` §1.3–1.4 | Complete; release gated by `make test` and `make playtest-gate`. |
| **361-item catalog, 55 egos & 12 equipment slots** | All 361 VMS item templates (`0..360` via Base-255 paged IDs in `'ITM2'` `ITEM.CAT`), 55 ego templates (`1..55` + 2 tool prefixes), 174 flavours, and 12 equipment slots (including Cloak & Secondary Weapon) ship under Save Format V2 (`$22`). | `Implemented` | `platforms/shared/item_catalog/`, `core/item_defs.s`, `core/ego_items.s`, `docs/SAVE_FORMAT_V2_PLAN.md` | Complete (`FEATURE_MAP.md` §8). |
| **279-monster catalog & persistent recall** | All 279/279 VMS species ship across all 7 ports and 5 cartridges (`MONSTER.CAT` + `MONSTER.EXT`), with 4-byte/species persistent `/` Monster Recall (`1,116 B`) persisted in Save Format V2 (`$22`). | `Implemented` | `core/monster_catalog.s`, `core/ui_recall.s`, `platforms/shared/catalog/`, `docs/MONSTER_CATALOG_DESIGN.md` | Complete (`FEATURE_MAP.md` §9.3–9.4). |
| **Chests & chest traps** | All 6 chest types (`Small/Large Wooden/Iron/Steel`) + `Ruined Chest` and all 6 chest lock/trap flags (`LOCKED`, `STR`, `POISON`, `PARA`, `EXPL`, `SUMMON`) with Search (`S`/`#`), Disarm (`SHIFT+D`), Open (`O`), and Bash (`CTRL+B`). | `Implemented` | `core/chest.s`, `core/chest_loot.s`, `core/chest_search.s`, `core/chest_summons.s`, `docs/CHEST_DESIGN.md` | Complete (`FEATURE_MAP.md` §6.6). |
| **Monster infravision & potion** | All 7 ports render warm monsters in darkness using race infravision plus potion/helm bonus, gated by shared LOS trace. | `Implemented` | `core/monster.s`, `core/dungeon_los.s`, all platform renderers | Complete (`FEATURE_MAP.md` §4.4). |
| **Balrog victory & retirement** | Balrog (`#278`) death sets `GAME_FLAG_WINNER`, plays victory SFX, grants `kingly()` bonuses on `SHIFT+Q`, draws the royal crown (`core/royal.s`), and persists winner scores. | `Implemented` | `core/combat.s`, `core/game_loop.s`, `core/royal.s`, `platforms/*/main.s` | Complete (`FEATURE_MAP.md` §6.7). |
| **Monster special attacks (19 verbs / 24 effects)** | All 19 `ADESC_*` attack descriptions and all 24 `ATK_*` effects (theft, stat drains, disenchant, eat food/light/charges, aggravate, lose EXP, acid/corrode, elemental touches) are implemented; elemental pack-item destruction/shattering is omitted. | `Implemented` | `core/monster_attack.s`, `core/monster_attack_effects.s`, `core/monster_acid.s` | Pack-item elemental destruction deferred (`FEATURE_MAP.md` §6.3–6.4). |
| **Monster spells & breaths (18 `CSPELL` flags)** | All 18 `CSPELL` flags (including Blink, Teleport Self, Summon Undead, Slow, Drain Mana, and 5 elemental breaths) are implemented; elemental breaths hit the player directly rather than acting as radius-2 balls destroying floor/pack items. | `Approximation` | `core/monster_magic.s`, `core/element_resist.s` | Ball-radius & item-destruction deltas tracked in `docs/BACKLOG.md` (`FEATURE_MAP.md` §9.2). |
| **Auto-rest disturbance** | `CTRL+R` shares the unified `zp_disturb` (`TRN-014`) disturbance latch with running, stopping on sightings, hostile monster action, damage, worsening hunger, displacement, and secret/trap discovery. | `Implemented` | `core/turn.s`, `core/game_loop.s`, `core/monster_ai.s`, `docs/TURN_RENDER_CONTRACT.md` | Complete (`FEATURE_MAP.md` §3.4). |
| **Protection from Evil & Heroism** | `zp_eff_protect` repels evil attackers `<= zp_player_lvl`; Heroism (`zp_eff_hero`) grants temporary HP, to-hit, and fear immunity. | `Implemented` | `core/monster_attack.s`, `core/turn.s`, `core/combat.s` | Complete (`FEATURE_MAP.md` §6.5). |
| **Version / System Info (`v` / `SHIFT+V`)** | `v` / `SHIFT+V` (and Title `A` -> `3`) displays version, Save V2 `$22`, `279m/361i`, geometry, hardware/drives/last I/O, and read-only session telemetry in `LEGALUI`. | `Implemented` | `core/ui_legal.s`, `core/ui_legal_sysinfo.s`, `platforms/*/legal_sysinfo.s` | Complete (`FEATURE_MAP.md` §3.3). |
| **Friendlier storage errors** | Friendly status classification across CBM DOS (`26`/`62`/`72`/`74`), Apple IIe ProDOS MLI (`storage_mli.s`), Atari8 `SIOV`, BBC `BRKV`, and CX16 HostFS, with raw diagnostic fallback. | `Implemented` | `core/storage_status.s`, `platforms/shared/save.s`, `platforms/apple2/storage_mli.s` | Minor C64 `0x`/`1x` command-status detail tracked in `docs/BACKLOG.md`. |
| **Home / store ownership split** | Player Home is separated into dedicated `OVL_HOME` (`HOME_OVERLAY_SEPARATE`) across all 7 ports. | `Implemented` | `core/ui_home.s`, `core/ui_home_text.s` | Complete (`FEATURE_MAP.md` §1.4, §5.3). |
| **Exact per-blow melee messages** | Combat mechanics are implemented; feedback uses an aggregate `(hits/blows)` summary rather than one message per blow. | `Approximation` | `core/combat.s`, `docs/COMBAT_AUDIT.md` | Intentional 8-bit message cadence (`FEATURE_MAP.md` §6.1). |
| **Plus/4 TED sound** | All 6 other ports synthesize all 10 SFX; Plus/4 `sound.s` remains stubbed/silent. | `Missing` | `platforms/commodore/plus4/sound.s` | Tracked in `docs/BACKLOG.md` (`FEATURE_MAP.md` §1.5). |
| **Numeric repeat prefixes** | Repeat count is fixed to `1` (`1-9` map to movement/rest; running uses `. <dir>`/`SHIFT+dir`, resting uses `CTRL+R`, search toggle uses `#`). | `Missing` | `core/input_tables.s` | Intentional/deferred (`FEATURE_MAP.md` §3.3). |
| **Hallucination (`image`) & inscriptions (`{`)** | Hallucination (`image` status) and manual free-text item inscriptions (`{`) are omitted; shopkeeper `rgold_adj` racial price matrix is also omitted. | `Missing` | `core/item.s`, `core/store.s` | Intentional/deferred (`FEATURE_MAP.md` §2.3, §6.5, §8.1). |

## Follow-Up Rules

- Treat [`docs/FEATURE_MAP.md`](FEATURE_MAP.md) as the authoritative parity and
  source-citation reference before opening or closing feature gaps.
- Any platform-specific gap (such as Plus/4 TED sound or `80x48` vs `198x66`
  geometry differences) must name the affected platform(s) explicitly.
