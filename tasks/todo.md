# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Status
- No active task in progress.
- Most recent completed work:
  - `10.4` C128 VDC threat/effect color pass
  - live threat-coded monster colors in the C128 viewport
  - first colored VDC transient effect path for bolt flashes

## Plan
- No active implementation plan.

## Notes
- Old phase docs define the intended monster palette as:
  - green = low threat
  - yellow = moderate
  - red = high
  - light red = deadly
- Existing `cr_color` is still the correct static species palette for C64 and non-live views like recall.
- The first concrete "special effect" hook is `eff_bolt -> screen_flash_at`.

## Review
- 10.4 is complete and manually accepted.
- Final shape:
  - threat-color helper lives in `commodore/c128/monster_threat_vdc.s`
  - C128 live viewport monster rendering uses threat colors
  - C64 and non-live/species-authored views still use `cr_color`
  - C128 bolt flashes use an explicit cyan transient VDC attribute
