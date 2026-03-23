# Active Task Scratchpad

This file is a temporary working scratchpad.

## Role
- Put the current task plan here while work is in progress.
- Keep only active checklists, current verification steps, and short working notes.
- Move durable completed-work notes to `commodore/BUILDPLAN_HISTORY.md`.
- Keep the long-lived active backlog in `commodore/BUILDPLAN.md`.

## Current Status
- Active task: none.
- Latest completed task: C128 banked combat relocation + cached `OVL.UI`.
- Commit-sized result:
  - help / inventory / equipment / character moved to cached `OVL.UI`
  - spell / projectile / ranged / tunnel spill cluster moved into resident `$F000` banked runtime
  - staged `banked_payload` source now proves `banked_payload_end <= $E000`
  - C64 build path restored by importing `player_magic_tail.s` on non-C128

### Review
- The corrected C128 design is now implemented and verified.
- Final accepted shape:
  - no executable code in `$0800-$0BFF`
  - no resident shared compute in `$E000-$EFFF`
  - spell / ranged / tunnel spill cluster relocated into resident `$F000` banked runtime
  - low-frequency modal UI moved to cached `OVL.UI`
- Verified outcomes:
  - `Ranged-fire handler stays out of I/O hole` assert now passes
  - staged-source safety now proves `banked_payload_end <= $E000`
  - help / inventory / equipment / character sheet all route through cached `OVL.UI`
  - C64 build still resolves `mage_effect_dispatch` / `priest_effect_dispatch`

### Verification
- `make -C commodore/c64 build`
- `make -B -C commodore/c128 build128`
- `make test128-fast`
- `make test128-fast-smoke`
- `TEST_FILTER='main128_layout|boot_title_idle_smoke|scripted_summary_to_town_smoke|town_overlay_smoke|death_overlay_smoke' bash commodore/c128/run_tests128.sh`
- Manual checks accepted by the user:
  - help / inventory / equipment / character
  - cast / pray
