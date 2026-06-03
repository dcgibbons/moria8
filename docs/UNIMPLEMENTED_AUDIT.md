# Unimplemented Feature Audit

This audit is source-backed against the current Moria8 workspace. Local Umoria
is used as the parity oracle where the feature is part of classic gameplay.

Verdicts:

- `Implemented`: present in product code and covered enough for current scope.
- `Partial`: present, but platform, fidelity, or coverage is incomplete.
- `Missing`: no product implementation found.
- `Approximation`: intentionally compact behavior, not byte-faithful Umoria.

| Area | Moria8 status | Verdict | Evidence | Backlog disposition |
| --- | --- | --- | --- | --- |
| Monster infravision | C64, C128, and Plus/4 render warm monsters in darkness using race infravision and timed potion range. Terrain/items are not revealed. Exact wall-blocking LOS is still approximated by range. | Implemented | `monster_is_infra_visible_at` in `commodore/common/dungeon_los.s`; `CF_INFRA` in `commodore/common/monster.s`; C64/Plus4 renderers; C128 VDC renderer; Umoria `monsterIsVisible`, `CD_INFRA`, `see_infra` | Keep exact LOS blocking as backlog work. |
| Infravision potion | Timer exists and now contributes +1 effective infravision range while active, matching Umoria's `timed_infra` increment model. | Implemented | `iq_effect_infravision` in `commodore/common/player_item_commands.s`; `player_get_infra_range` in `dungeon_los.s`; Umoria `player_quaff.cpp`, `game_run.cpp` | Add broader end-to-end coverage as needed. |
| Balrog victory | Balrog death sets a compact winner flag, blocks save-and-exit, routes Shift+Q through retirement and royal art, and marks winner scores. Focused coverage is still thin. | Implemented | `CREATURE_BALROG` in `commodore/c64/creature_data/creature_tiers.s`; `combat_note_kill` in `commodore/common/combat.s`; retirement path in `commodore/common/game_loop.s`; royal overlay in `commodore/common/royal.s` | Keep coverage follow-up in backlog. |
| Chests | No chest object state, chest traps, chest open/bash/disarm flow, or persistence found. | Missing | `docs/BACKLOG.md`; item/feature/disarm sources | Backlog item already exists. |
| Full monster catalog | Moria8 ships a selected tier roster rather than all 279 Umoria creatures; global monster IDs and complete recall persistence are not done. | Partial | `tools/parse_creatures.py`; `commodore/c64/creature_data`; `docs/MONSTERS.md` | Backlog item already exists. |
| Unsupported monster special attacks | Several Umoria attack effects are collapsed to normal/poison/etc. | Approximation | `tools/parse_creatures.py::UMORIA_TO_C64_ATK`; `docs/COMBAT_AUDIT.md` | Add explicit backlog item for high-value special effects. |
| Monster spells/breath breadth | Spell flags are compact and do not cover every upstream spell behavior. | Approximation | `tools/parse_creatures.py::map_spell_flags`; `commodore/common/monster_magic.s` | Covered by monster catalog/behavior expansion backlog. |
| Auto-rest disturbance | `CTRL+R` exists, but not every silent danger goes through a shared disturbance flag. | Partial | `docs/BACKLOG.md`; rest command tests/source | Backlog item already exists. |
| Exact per-blow melee messages | Mechanics are implemented; feedback is an aggregate `(hits/blows)` summary rather than one message per blow. | Approximation | `docs/COMBAT_AUDIT.md`; `docs/BACKLOG.md`; combat message code | Optional backlog item already exists. |
| Protection/super-heroism parity | Combat audit identifies missing or incomplete status parity. | Partial/Missing | `docs/COMBAT_AUDIT.md` | Add/retain backlog items for status parity after v1.1.0. |
| Numeric repeat prefixes | Input code explicitly leaves numeric prefixes deferred; repeat count is always 1. | Missing | `commodore/c64/input.s`; `commodore/plus4/input.s` | Add backlog item. |
| Plus/4 TED sound | Sound backend is still silent despite TED hardware. | Missing | `commodore/plus4/sound.s`; `docs/BACKLOG.md` | Backlog item already exists. |
| Version/System Info command | `CMD_VERSION` exists as a hidden/probe-oriented path, not a polished cross-platform view. | Partial | `docs/BACKLOG.md`; input/command dispatch | Backlog item already exists. |
| Friendlier storage errors | Raw storage diagnostics exist; some player-facing messages remain terse or device-specific. | Partial | `docs/BACKLOG.md`; storage HAL/save/disk setup sources | Backlog item already exists. |
| Home/store ownership split | The visible stale-footer bug is fixed, but Home still shares too much store rendering ownership. | Partial | `docs/BACKLOG.md`; store/Home UI code | Backlog item already exists. |

## Follow-Up Rules

- Do not treat an approximation as accurate unless the docs say it is an
  intentional Moria8 limit.
- Any feature with platform-specific behavior must name the platform gap in
  the backlog item.
- For C128 rendering work, the acceptance gate includes the runtime-low
  boundary assertions. The renderer must not overlap the floor-item table.
