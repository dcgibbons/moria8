# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Task
- [x] Audit the current XP/level-up implementation and history context for `BUG-XP-PACE`.
- [ ] Compare the current behavior against original Umoria source/runtime expectations.
- [ ] Get a consultant second opinion on the likely remaining pace drift.
- [ ] Write a concrete `BUG-XP-PACE` design with recommended audit/fix order.

## Plan
- [x] Inspect `combat_award_xp`, `combat_compute_level_threshold`, and `combat_check_levelup`.
- [x] Re-read the prior fractional-XP history entry so the new design does not duplicate solved work.
- [ ] Verify original Umoria level-threshold / expfact / level-up-halving behavior from primary source.
- [ ] Identify which remaining drift hypotheses are most plausible and cheapest to prove.
- [ ] Write the recommended design and consultant-backed next steps here.

## Working Read

### Current code facts
- `commodore/common/combat.s`
  - `combat_award_xp` still uses `(cr_xp * cr_level) / player_level`.
  - Fractional remainders are accumulated in `PL_XP_FRAC_LO/HI`.
  - `combat_compute_level_threshold` multiplies the threshold table by `PL_EXPFACT / 100`.
  - `combat_check_levelup` compares only the whole 16-bit threshold against the 24-bit whole XP and then applies the original-style one-level-per-kill excess-halving behavior.
- `commodore/common/tables.s`
  - XP thresholds are still a 16-bit table with `65535` sentinels for level 30+.
- `commodore/common/player_create.s`
  - `PL_EXPFACT` is still stored as `race_xp% + class_xp%`.

### Prior history that matters
- `commodore/BUILDPLAN_HISTORY.md` already records MC2.2 fractional XP accumulation as complete.
- That means `BUG-XP-PACE` should be treated as a fresh audit of remaining drift, not a rerun of the old min-1 / truncation bug.

## Consultant Second Opinion

- The consultant agreed that the strongest remaining suspects are on the threshold/data side, not the basic kill-award formula.
- Recommended audit order:
  1. prove a small regression matrix first
  2. verify monster XP/level data and the full threshold curve against original source
  3. re-check the level-up retention contract
  4. only then change award/threshold code
- Important reminder:
  - if the XP math matches original but leveling still feels fast in play, the bug may really be content pacing (monster distribution / deep spawns), not XP arithmetic

## `BUG-XP-PACE` Design

### Problem Statement
- Playtesting suggests characters gain levels faster than stock Umoria.
- A prior fix already restored hidden fractional XP accumulation, so the remaining drift is likely elsewhere.

### Proven Current State
1. **Kill XP formula matches the expected Umoria shape**
   - `combat_award_xp` uses `(cr_xp * cr_level) / player_level`.
   - It also carries fractional remainders in `PL_XP_FRAC_LO/HI`.
2. **Experience factor shape also matches Umoria structurally**
   - `PL_EXPFACT` is built as race XP factor + class XP factor.
   - Original Umoria does the same additive composition.
3. **One major parity risk is already visible in current code**
   - `xp_level_lo/hi` in `commodore/common/tables.s` saturates to `65535` for level 29+.
   - Original Umoria continues rising to 75,000 / 100,000 / 150,000 / 200,000 / 300,000 / 400,000 / 500,000 / 750,000 / 1,500,000 / 2,500,000 / 5,000,000 / 10,000,000.
   - So late-game advancement is definitely too fast today, even before any deeper audit.

### Likely Root-Cause Buckets
1. **Threshold truncation**
   - Highest-confidence bug.
   - The current 16-bit threshold representation cannot encode the original late-game curve.
2. **Unverified threshold parity before level 29**
   - The low/mid table entries look source-matched, but they should still be proven as a full curve instead of assumed from comments.
3. **Level-up progression contract**
   - Current code hard-caps to one level-up per kill, then halves retained excess.
   - Original Umoria loops while XP still exceeds the next threshold, with halving applied during each gain-level step.
   - This is a real parity difference, though it would usually make the port level more slowly on very large awards, not faster.
4. **Content pacing masquerading as XP pacing**
   - If the arithmetic/threshold audit passes for the levels users are actually reaching, the remaining culprit is likely monster distribution:
     - deeper/higher-XP monsters appearing too early
     - roster/tier/deep-fallback behavior producing richer XP than stock Umoria

### Recommended Fix Shape
1. **Split the work into Phase A and Phase B**
   - Phase A:
     - audit and repair XP math/threshold parity
   - Phase B:
     - only if needed, audit gameplay/content pacing separately
2. **Phase A implementation target**
   - Replace the current 16-bit threshold representation with a 24-bit threshold table or equivalent 24-bit computation path.
   - Update `combat_compute_level_threshold` to produce a real 24-bit adjusted threshold.
   - Update `combat_check_levelup` to compare full 24-bit XP against the full adjusted threshold.
3. **Phase A scope discipline**
   - Do not change monster spawn/tier logic in the same patch.
   - Do not change the basic kill-XP formula unless original-source verification disproves it.
   - Treat multi-level-per-award parity as a separate sub-decision after the threshold audit:
     - if strict Umoria fidelity is the goal, the current one-level cap should probably be revisited
     - if practical gameplay parity is already restored by threshold repair, that follow-up can stay separate

### Required Proof Before Code Change
1. Verify original Umoria primary sources for:
   - full base XP threshold curve
   - additive race+class experience factor contract
   - kill XP formula
   - multi-level gain behavior and excess-halving semantics
2. Add focused regression coverage for:
   - low-level threshold gate
   - non-100 `PL_EXPFACT` threshold scaling
   - level-29+ threshold values beyond 65535
   - retained-excess behavior after level-up
3. Add one explicit “late-game threshold” test that would fail under the current 16-bit sentinel table.

### Decision Rule After Phase A
1. If the corrected threshold/multi-level parity brings leveling in line with stock Umoria:
   - close `BUG-XP-PACE`
2. If play still feels fast after the arithmetic audit:
   - re-scope the remaining work as content pacing, likely around monster-level / monster-XP distribution rather than XP math itself

### Recommended Next Step
- Start with a narrow source-and-test audit focused on threshold representation.
- That is the highest-confidence fix, the lowest-risk change, and the one most clearly proven wrong by the current code.
