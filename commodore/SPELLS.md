# Additional Spells Audit

## Scope

- Commodore now uses the full `31 mage + 31 priest` catalogs instead of the old reduced `16 + 16` model.
- Spell tables, book masks, and subclass access follow `umoria`.
- Spell behavior is VMS-first where the two upstreams differ materially.
- `Legacy` below means the old Commodore baseline spell set (`1-16`).
- `Added` below means spells/prayers restored by this feature (`17-31`).

## Data And Memory

- Player spell state moved from a 2-byte learned-mask model to a full `learned/worked/forgotten/order` model.
- `player_data` grew from `82` bytes to `111` bytes.
- Net new spell-state payload is `45` bytes:
  - `4` bytes learned mask
  - `4` bytes worked mask
  - `4` bytes forgotten mask
  - `1` byte pending new spells
  - `32` bytes spell order
- The struct only grew by `29` bytes because `14` bytes came out of the old reserved tail.
- Save compatibility intentionally changed:
  - C64 `SAVE_VERSION`: `$0c -> $0d`
  - C128 `SAVE_VERSION`: `$0d -> $0e`
- C64 ownership:
  - `UiOverlay`: spell names, list data, selection UI, study/learn UI
  - `DeathOverlay`: spell execution dispatcher and low-frequency effect code
  - resident main RAM keeps the hot cast/pray command flow and only trampolines into overlay-owned selection/execution
- C128 ownership:
  - `UiOverlay`: spell names, list data, selection UI, study/learn UI
  - `DeathOverlay`: spell execution dispatcher and low-frequency effect code
- Glyph support added one small resident table: `MAX_GLYPHS = 4`, stored as `glyph_x`, `glyph_y`, `glyph_active` for `12` bytes total.

## Known Deviations

- `Detect Evil` is still implemented through the generic monster-detect path, not a strict evil-only reveal.
- `Resist Heat and Cold` currently sets the existing packed resistance flags directly instead of upstream split timers.
- The current tree now uses those flags to reduce the implemented elemental breath-damage path, but broader fire/cold consumers are still not modeled yet.
- `Glyph of Warding` is mechanically active, but there is no special dungeon-tile rendering for glyphs yet.
- Glyph break chance is currently a simplified approximation rather than the exact upstream formula.
- Class tables and book splits intentionally follow `umoria`; effect semantics intentionally prefer VMS when they differ.

## Feedback Audit

- Commodore now follows the locked hybrid upstream rule:
  - no generic `You cast...` / `You pray...` success banner
  - explicit feedback only when the effect would otherwise be silent, misleading, or easy to miss
  - obvious projectile/map/teleport/control results stay message-light
- Mage spells audited for explicit feedback:
  - direct confirmation or failure text: `2 Detect Monsters`, `4 Light Area`, `5 Cure Light Wounds`, `12 Cure Poison`, `14 Remove Curse`, `17 Create Food`, `18 Recharge Item I`, `26 Recharge Item II`, `28 Haste Self`
  - no extra cast banner by design because the outcome is already visible: `1`, `3`, `6-11`, `13`, `15-16`, `19-25`, `27`, `29-31`
- Priest prayers audited for explicit feedback:
  - direct confirmation or failure text: `1 Detect Evil`, `2 Cure Light Wounds`, `3 Bless`, `4 Remove Fear`, `5 Call Light`, `14 Create Food`, `15 Remove Curse`, `16 Resist Heat and Cold`, `17 Neutralize Poison`, `19 Cure Serious Wounds`, `20 Sense Invisible`, `21 Protection from Evil`, `24 Cure Critical Wounds`, `26 Prayer`, `28 Heal`, `31 Holy Word`
  - no extra cast banner by design because the outcome is already visible: `6-13`, `18`, `22-23`, `25`, `27`, `29-30`
- Current Commodore messaging choices after the audit:
  - `Bless`, `Chant`, and `Prayer` now show an explicit onset message when the blessed state starts
  - `Haste Self`, `Protection from Evil`, and `Sense Invisible` keep explicit onset feedback
  - `Resist Heat and Cold` now has explicit onset feedback, but it is still tied to the current packed-flag implementation rather than exact upstream timers
  - `Create Food`, `Glyph of Warding`, and `Recharge` now explain blocked/no-target cases instead of failing silently
  - timed expiry text for bless/haste/protection is still intentionally omitted on Commodore; this remains a documented deviation from richer `umoria` status messaging

## Coverage Audit

- Shared family coverage added during hardening:
  - bolts/projectiles:
    - `Magic Missile` now has a shared runtime regression proving bolt flashes originate from the correct viewport cell and do not end in `HSTR_EB_FIZZLE` on an immediate hit
    - C128 also has a direct unit guard that `screen_flash_set_color` preserves the row register used by `screen_flash_at`
  - heals:
    - shared spell/prayer heal coverage now proves:
      - tiny heals emit `You feel a little better.`
      - modest heals emit `You feel better.`
      - large heals emit `You feel much better.`
      - strongest heals emit `You feel very good.`
      - capped heals stop at max HP
      - full-HP spell/prayer heals stay silent instead of printing a bogus success message
  - timed buff/protection feedback:
    - dedicated runtime coverage now exists for bless onset/refresh and resist onset/refresh
    - `Resist Heat and Cold` now also has a direct runtime regression proving it reduces hostile breath damage
  - adjacent monster-control feedback:
    - dedicated runtime coverage now exists for `Sanctuary` no-target feedback and for actually sleeping an adjacent monster
  - detect/reveal feedback:
    - dedicated runtime coverage now exists for `Detect Monsters` result/no-result behavior
    - dedicated runtime coverage now exists for `Detect Evil` result/no-result behavior
  - area / utility / high-end priest effects:
    - dedicated runtime coverage now exists for `Sense Surroundings` map reveal behavior
    - dedicated runtime coverage now exists for `Glyph of Warding` success and blocked-by-object behavior
    - dedicated runtime coverage now exists for `Holy Word` heal/cleanse/dispel behavior
- Current focused runtime suites:
  - `commodore/c64/tests/test_effects.s`
    - shared bolt/projectile regression coverage
    - shared spell/prayer heal-family coverage
  - `commodore/c64/tests/test_utility_effects.s`
    - `Sense Surroundings`
    - `Glyph of Warding`
    - `Holy Word`
  - `commodore/c64/tests/test_prayer_feedback.s`
    - `Chant`
    - `Sanctuary`
    - `Resist Heat and Cold`
  - `commodore/c64/tests/test_detect_feedback.s`
    - `Detect Monsters`
    - `Detect Evil`
- Coverage still shallow or missing for:
  - higher-end priest book 3/4 dispel and utility prayers
  - area-effect spell families beyond the existing shared smokes and utility representatives above

## Book Layout

- Mage `M1 [Beginners-Magick]`: `1-7`
- Mage `M2 [Magick I]`: `8-16`
- Mage `M3 [Magick II]`: `17-24`
- Mage `M4 [The Mages' Guide to Power]`: `25-31`
- Priest `P1 [Beginners Handbook]`: `1-8`
- Priest `P2 [Words of Wisdom]`: `9-16`
- Priest `P3 [Chants and Blessings]`: `17-25`
- Priest `P4 [Exorcisms and Dispellings]`: `26-31`

## Mage-Affinity Catalog

`Mage`, `Rogue`, and `Ranger` use the mage-affinity catalog. Table values are `level/mana/fail`; `--` means that class cannot learn the spell.

| # | Status | Book | Spell | Mage | Rogue | Ranger | Effect | Notes |
|---|---|---|---|---|---|---|---|---|
| 1 | Legacy | M1 | Magic Missile | 1/1/22 | -- | 3/1/30 | Directional magic bolt `2d6` | - |
| 2 | Legacy | M1 | Detect Monsters | 1/1/23 | 5/1/50 | 3/2/35 | Monster detection | - |
| 3 | Legacy | M1 | Phase Door | 1/2/24 | 7/2/55 | 3/2/35 | Short self-teleport | - |
| 4 | Legacy | M1 | Light Area | 1/2/26 | 9/3/60 | 5/3/35 | Lights room/corridor | - |
| 5 | Legacy | M1 | Cure Light Wounds | 3/3/25 | 11/4/65 | 5/3/40 | Heal `4d4` | - |
| 6 | Legacy | M1 | Find Hidden Traps/Doors | 3/3/25 | 13/5/70 | 5/4/45 | Detect traps and doors | - |
| 7 | Legacy | M1 | Stinking Cloud | 3/3/27 | -- | 7/5/40 | Poison-gas ball `9` | - |
| 8 | Legacy | M2 | Confusion | 3/4/30 | 15/6/75 | 7/6/40 | Directional confusion | - |
| 9 | Legacy | M2 | Lightning Bolt | 5/4/30 | -- | 9/7/40 | Directional lightning bolt `3d8` | - |
| 10 | Legacy | M2 | Trap/Door Destruction | 5/5/30 | 17/7/80 | 9/8/45 | Destroy traps and doors | - |
| 11 | Legacy | M2 | Sleep I | 5/5/30 | 19/8/85 | 11/8/40 | Put one monster to sleep | - |
| 12 | Legacy | M2 | Cure Poison | 5/5/35 | 21/9/90 | 11/9/45 | Clear poison | - |
| 13 | Legacy | M2 | Teleport Self | 7/6/35 | -- | 13/10/45 | Long self-teleport | - |
| 14 | Legacy | M2 | Remove Curse | 7/6/50 | 23/10/95 | 13/11/55 | Remove curse from equipped items | Priest version is broader |
| 15 | Legacy | M2 | Frost Bolt | 7/6/40 | -- | 15/12/50 | Directional frost bolt `4d8` | - |
| 16 | Legacy | M2 | Turn Stone to Mud | 9/7/44 | -- | 15/13/50 | Convert wall to mud | - |
| 17 | Added | M3 | Create Food | 9/7/45 | 25/12/95 | 17/17/55 | Create food on player tile | - |
| 18 | Added | M3 | Recharge Item I | 9/7/75 | 27/15/99 | 17/17/90 | Recharge wand/staff, with break risk | - |
| 19 | Added | M3 | Sleep II | 9/7/45 | -- | 21/17/55 | Sleep adjacent monsters | Uses VMS-style local sleep, not mass sleep |
| 20 | Added | M3 | Polymorph Other | 11/7/45 | -- | 21/19/60 | Replace target monster with another | - |
| 21 | Added | M3 | Identify | 11/7/99 | 29/18/99 | 23/25/95 | Item identify prompt | - |
| 22 | Added | M3 | Sleep III | 13/7/50 | -- | 23/20/60 | Sleep all visible monsters | - |
| 23 | Added | M3 | Fire Bolt | 15/9/50 | -- | 25/20/60 | Directional fire bolt `6d8` | - |
| 24 | Added | M3 | Slow Monster | 17/9/50 | -- | 25/21/65 | Slow target monster | - |
| 25 | Added | M4 | Frost Ball | 19/12/55 | -- | 27/21/65 | Frost ball `33` | - |
| 26 | Added | M4 | Recharge Item II | 21/12/90 | -- | 29/23/95 | Stronger recharge with break risk | - |
| 27 | Added | M4 | Teleport Other | 23/12/60 | -- | 31/25/70 | Teleport target monster away | - |
| 28 | Added | M4 | Haste Self | 25/12/65 | -- | 33/25/75 | Temporary self-speed boost | - |
| 29 | Added | M4 | Fire Ball | 29/18/65 | -- | 35/25/80 | Fire ball `49` | - |
| 30 | Added | M4 | Word of Destruction | 33/21/80 | -- | 37/30/95 | Destroy surrounding area | - |
| 31 | Added | M4 | Genocide | 37/25/95 | -- | -- | Remove one creature type | - |

## Priest-Affinity Catalog

`Priest` and `Paladin` use the priest-affinity catalog. Table values are `level/mana/fail`.

| # | Status | Book | Prayer | Priest | Paladin | Effect | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Legacy | P1 | Detect Evil | 1/1/10 | 1/1/30 | Detect hostile/evil creatures | Current Commodore still uses generic monster detect |
| 2 | Legacy | P1 | Cure Light Wounds | 1/2/15 | 2/2/35 | Heal `3d3` | - |
| 3 | Legacy | P1 | Bless | 1/2/20 | 3/3/35 | Bless timer `12-23 + current` | - |
| 4 | Legacy | P1 | Remove Fear | 1/2/25 | 5/3/35 | Clear fear | - |
| 5 | Legacy | P1 | Call Light | 3/2/25 | 5/4/35 | Lights room/corridor | - |
| 6 | Legacy | P1 | Find Traps | 3/3/27 | 7/5/40 | Detect traps | - |
| 7 | Legacy | P1 | Detect Doors/Stairs | 3/3/27 | 7/5/40 | Detect doors and stairs | Restored to reveal both doors and stairs |
| 8 | Legacy | P1 | Slow Poison | 3/3/28 | 9/7/40 | Reduce poison severity | - |
| 9 | Legacy | P2 | Blind Creature | 5/4/29 | 9/7/40 | Directional blind/stun effect | - |
| 10 | Legacy | P2 | Portal | 5/4/30 | 9/8/40 | Self-teleport | - |
| 11 | Legacy | P2 | Cure Medium Wounds | 5/4/32 | 11/9/40 | Heal `4d4` | - |
| 12 | Legacy | P2 | Chant | 5/5/34 | 11/10/45 | Bless timer `24-47 + current` | - |
| 13 | Legacy | P2 | Sanctuary | 7/5/36 | 11/10/45 | Sleep adjacent monsters | Uses VMS-style local sanctuary |
| 14 | Legacy | P2 | Create Food | 7/5/38 | 13/10/45 | Create food on player tile | - |
| 15 | Legacy | P2 | Remove Curse | 7/6/38 | 13/11/45 | Remove curses from carried and equipped items | Broader than mage version |
| 16 | Legacy | P2 | Resist Heat and Cold | 7/7/38 | 15/13/45 | Reduce implemented elemental breath damage via packed resist flags | Still uses packed-flag shortcut, not timed upstream duration |
| 17 | Added | P3 | Neutralize Poison | 9/6/38 | 15/15/50 | Clear poison | - |
| 18 | Added | P3 | Orb of Draining | 9/7/38 | 17/15/50 | Holy ball damage `3d6 + level` | - |
| 19 | Added | P3 | Cure Serious Wounds | 9/7/40 | 17/15/50 | Heal `8d4` | - |
| 20 | Added | P3 | Sense Invisible | 11/8/42 | 19/15/50 | See invisible / invis sense | - |
| 21 | Added | P3 | Protection from Evil | 11/8/42 | 19/15/50 | Protection timer `25-49 + current` | - |
| 22 | Added | P3 | Earthquake | 11/9/55 | 21/17/50 | Local earthquake | - |
| 23 | Added | P3 | Sense Surroundings | 13/10/45 | 23/17/50 | Map surrounding area | - |
| 24 | Added | P3 | Cure Critical Wounds | 13/11/45 | 25/20/50 | Heal `16d4` | - |
| 25 | Added | P3 | Turn Undead | 15/12/50 | 27/21/50 | Turn undead in sight | - |
| 26 | Added | P4 | Prayer | 15/14/50 | 29/22/50 | Bless timer `48-95 + current` | - |
| 27 | Added | P4 | Dispel Undead | 17/14/55 | 31/24/60 | Dispel undead for `3 * level` | - |
| 28 | Added | P4 | Heal | 21/16/60 | 33/28/60 | Heal `200` HP | - |
| 29 | Added | P4 | Dispel Evil | 25/20/70 | 35/32/70 | Dispel evil for `3 * level` | - |
| 30 | Added | P4 | Glyph of Warding | 33/24/90 | 37/36/90 | Place a blocking glyph on the player tile | Active mechanically; no special tile render yet |
| 31 | Added | P4 | Holy Word | 39/32/80 | 39/38/90 | Heal to full, remove fear/poison, restore stats, 3 turns invulnerability, dispel evil for `4 * level` | Now matches upstream `umoria` |

## Upstream Comparison Notes

- `umoria` is the source of truth for:
  - the full 31-entry class spell tables
  - subclass access (`rogue`, `ranger`, `paladin`)
  - per-book spell masks instead of fixed `4 spells/book`
  - the richer learned/worked/forgotten/order state model
- VMS is the source of truth for the main semantic choices:
  - `Sleep II` and `Sanctuary` are local sleep effects, not the broader alternatives found in some later ports
  - priest `Remove Curse` is treated as the stronger all-items version
- `umoria` is now the source of truth for `Holy Word`:
  - full heal
  - remove fear and poison
  - restore all stats
  - grant 3 turns of invulnerability
  - dispel evil for `4 * level`
- Remaining follow-up candidates if stricter parity is required:
  - exact evil-only detection for `Detect Evil`
  - exact timed handling for `Resist Heat and Cold`
  - exact glyph-render and glyph-break formulas
