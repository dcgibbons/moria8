# Monster State Contract

Load this document for monster records, AI, sleep/wake behavior, awareness,
visibility/detection, monster targeting, attacks, or spell effects on monsters.
Do not load it for renderer or inspection work that only consumes
already-authoritative monster flags; use `TURN_RENDER_CONTRACT.md` instead.

## Authority

- Moria8 state layout and production entry points: `core/monster.s`
- AI transitions: `core/monster_ai.s`
- Attack transitions: `core/monster_attack.s`, `core/monster_magic.s`
- Default upstream oracle: pinned VMS Moria
  `source/include/{misc,creature,spells}.inc`
- Secondary oracle: pinned Umoria `src/{monster,spells}.cpp`

## Live Record Inventory

Each live slot is a 12-byte record. `MX_TYPE == EMPTY_SLOT` is the sole empty
slot test and must precede mutation through table scans.

| State | Meaning | Authoritative consumer |
| --- | --- | --- |
| `MX_X`, `MX_Y` | Current map position | movement, combat, visibility |
| `MX_TYPE` | Active creature-table index or `EMPTY_SLOT` | every live-slot scan |
| `MX_HP_LO`, `MX_HP_HI` | Current 16-bit HP | combat, monster magic, flee logic |
| `MX_FLAGS.MF_AWAKE` | Monster may proceed into active AI | `monster_process_one` |
| `MX_SLEEP_CUR` | Remaining compact sleep counter | `monster_wake_check` |
| `MX_SPEED_CNT` | Movement scheduling state | monster AI tick |
| `MX_STUN` | Turns unable to act | `monster_process_one` |
| `MX_CONFUSE` | Live confusion timer used by AI | combat and `monster_process_one` |
| `MX_FLEE_LO`, `MX_FLEE_HI` | 16-bit flee HP threshold | movement/flee logic |
| `MF_PROVOKED` | Player hostility; permits town-creature retaliation | combat, bash, AI |
| `MF_VISIBLE` | Current ordinary sight and renderer authority | visibility, targeting |
| `MF_DETECTED` | Magical detection knowledge: timed Detect Monsters or immediate Detect Evil pending its post-redraw clear | renderer, free-look, and dirty tracking; not ordinary targeting |
| `MF_CONFUSED` | Defined flag with no production consumer found | not authoritative; use `MX_CONFUSE` |

`MF_VISIBLE` and `MF_DETECTED` are knowledge/render states. Detection may be
timer-owned or an immediate reveal latch; it does not grant ordinary LOS or
spell targeting. Current production also makes
`MF_VISIBLE` monsters wake-eligible outside `cr_aaf`; that behavior is disputed
and recorded below rather than silently treated as settled policy.

Ordinary wake pressure currently uses Chebyshev distance, while both upstream
oracles use `max(dx,dy) + floor(min(dx,dy)/2)`. The shared distance helper also
owns monster spell range, so convergence is tracked as a separate backlog item
with diagonal boundary tests rather than being changed incidentally here.

## Settled Transitions

| Event | Required transition | Production entry point | Existing coverage |
| --- | --- | --- | --- |
| Apply explicit sleep | Clear `MF_AWAKE`; store duration in `MX_SLEEP_CUR` | `monster_apply_sleep` | C64/C128 sleep and sanctuary suites |
| Ordinary active AI | Only `MF_AWAKE` monsters proceed past wake check | `monster_process_one` | C64 `test_monster_ai.s` |
| Empty-slot scan | Skip before writing any other field | all table scans | monster/attack tests |
| Detect Monsters | May set and expose `MF_DETECTED`; must not imply `MF_VISIBLE` | visibility producer, inspection, dirty tracking, renderers | platform detect/render tests |
| Explicit aggravation | Clear sleep and wake every live slot; upstream nearby haste remains unresolved | `monster_aggravate_all` | C64 attack and Plus/4 shared-producer coverage |

Numeric counters are unsigned bytes unless a field says otherwise. Arithmetic
must not wrap accidentally. For each changed formula, record every input and
intermediate width, carry state, mathematical range, and saturation/truncation
point. Exhaustive tests are preferred when the input domain is one byte.

Sleep spell resistance translates `rng_range(40)` from `0..39` to VMS Moria's
`randint(40)` range `1..40` before comparing against monster level.

## Decision Ledger

Accepted rows dated 2026-07-09 record explicit maintainer decisions from the
work16 behavior review; this ledger is their durable approval provenance.

| ID | Status | Owner/date | Scope and selected rule | Evidence/enforcement | Supersedes |
| --- | --- | --- | --- | --- | --- |
| MON-001 | Accepted | Project maintainer, 2026-07-09 | Detected-only monsters are renderable/inspectable knowledge but are not ordinary spell targets | maintainer decision; targeting and renderer tests; inspection test `NOT IMPLEMENTED` | none |
| MON-002 | Accepted | Project maintainer, 2026-07-09 | Explicit sleep clears `MF_AWAKE` and stores the compact duration | `monster_apply_sleep`; sleep/sanctuary tests | none |
| MON-003 | Disputed current behavior | Project maintainer, 2026-07-09 | Production lets `MF_VISIBLE` bypass `cr_aaf` for wake eligibility; eligible wake pressure is gated by race/class stealth as in VMS Moria | `monster_ai.s::monster_wake_check`; C64 stealth-gate regressions | none |
| MON-004 | Accepted | Project maintainer, 2026-07-09 | Initial sleep uses the compact randomized mapping and saturates at `$ff`; arithmetic must not wrap | `monster_initial_sleep`; C64 maximum-input regression | none |
| MON-005 | Accepted | Project maintainer, 2026-07-09 | Auto-rest suppresses ordinary deterministic wake pressure, matching VMS Moria | `monster_wake_check`; C64 AI rest regression | none |
| MON-006 | Accepted in part | Project maintainer, 2026-07-09 | Explicit/group wakes clear `MX_SLEEP_CUR`; Sleep I/II/III use monster-level resistance; aggravation wakes globally | shared helpers and C64/C128/Plus4 focused gates; no-sleep immunity and upstream nearby aggravation haste remain open | none |
| MON-007 | Accepted | Project maintainer, 2026-07-10 | Compact ordinary wake pressure uses distance steps `{8,8,4,3,2,2,1...}` scaled from VMS Moria's `floor(75/d)`; an eligible zero sleep counter wakes before rest/stealth gates | explicit maintainer direction to address staff review; C64 deterministic wake regressions | none |

## Conditional Verification Matrix

Select rows for the transitions changed and document omitted relevant rows.

| Change | Required cases |
| --- | --- |
| Spawn/sleep arithmetic | zero, ordinary, maximum source value; overflow and monotonicity |
| Wake eligibility | inside, at, and outside awareness boundary; visible/not visible; rest state if relevant |
| Wake transition | counter remains positive, reaches zero, underflows; group and explicit paths if affected |
| Spell/attack state | success, resistance/immunity if represented, empty slot, last slot |
| Visibility/detection | visible-only, detected-only, neither, LOS blocked, production targeting |
| Shared implementation | affected C64, C128, and Plus/4 production paths or explicit exemption |

Test-local copies prove harness behavior only. At least one regression test must
execute the changed production routine through its real dispatch/overlay path.

## Executable Enforcement

| Invariant | Current gate | Command/status |
| --- | --- | --- |
| Basic AI wake transitions | `platforms/commodore/c64/tests/test_monster_ai.s` | `TEST_FILTER='monster_ai' make test64` |
| Compact wake-pressure buckets and spawn-to-AI flow | `platforms/commodore/c64/tests/test_monster_ai.s` | deterministic distances 0-8/20 and production spawn cases at 1/6/8; C128/Plus4 have no dedicated ordinary-wake harness and rely on identical shared source plus product layout gates |
| C64 Detect Evil behavior | `platforms/commodore/c64/tests/test_detect_evil.s` | `TEST_FILTER='detect_evil' make test64`; does not prove timed Detect Monsters lifecycle |
| C128 detection dispatch/effect pieces | `platforms/commodore/c128/tests/test_detect_monsters128.s`, `test_detect_evil128.s` use test-local stubs/helpers | `TEST_FILTER='detect_monsters128|detect_evil128' make test128`; complete producer path `NOT IMPLEMENTED` |
| C64 detected-only targeting exclusion | `platforms/commodore/c64/tests/test_dispel_evil_prayer.s` | `TEST_FILTER='dispel_evil_prayer' make test64` |
| C128 detected-only targeting exclusion | `platforms/commodore/c128/tests/test_dispel_evil_prayer128.s` | `TEST_FILTER='dispel_evil_prayer128' make test128` |
| C64 renderer consumption | `platforms/commodore/c64/tests/test_render.s` | `TEST_FILTER='render' make test64`; seeded flags do not prove the producer |
| Plus/4 renderer consumption | `platforms/commodore/plus4/tests/test_renderplus4.s` | `TEST_FILTER='renderplus4' make testplus4` |
| Plus/4 production visibility-wrapper integration | `platforms/commodore/plus4/tests/test_visibility_renderplus4.s` | `TEST_FILTER='visibility_renderplus4' make testplus4` |
| C128 renderer consumption | `platforms/commodore/c128/tests/test_vdc_scroll_delta128.s` | `TEST_FILTER='vdc_scroll_delta128' make test128`; seeded cases do not prove the producer |
| C64 spell sleep dispatch | C64 sleep/sanctuary test files | `TEST_FILTER='sleep|sanctuary' make test64`; Sleep II exercises production feedback/resistance and pins the level-40 boundary; some other paths use test-local helpers |
| C128 spell sleep behavior | C128 sleep/sanctuary test files | `TEST_FILTER='sleep|sanctuary' make test128`; production-overlay coverage incomplete |
| Plus/4 shared sleep/wake/aggravation producer | `platforms/commodore/plus4/tests/test_visibility_renderplus4.s` | `TEST_FILTER='visibility_renderplus4' make testplus4` |
| One-byte sleep arithmetic maximum boundary | `platforms/commodore/c64/tests/test_monster.s` | `TEST_FILTER='monster' make test64`; exhaustive byte-domain gate remains `NOT IMPLEMENTED` |
| Detected-only production free-look inspection | none | `NOT IMPLEMENTED` |
| Complete cross-platform timed Detect Monsters producer lifecycle | none | `NOT IMPLEMENTED` |
