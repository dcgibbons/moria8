// dungeon_los.s — Line of sight / visibility
//
// Phase 3: Town is always fully lit and visible.
// Full LOS calculation added in Phase 4/5 for dungeon levels.

// ============================================================
// Subroutines
// ============================================================

// town_light_all — Mark all town tiles as lit + visited
// No-op: town_generate already sets LIT+VISITED flags on all tiles.
// Preserves: A, X, Y
town_light_all:
    rts

// los_is_visible — Check if a map position is visible to the player
// Input: X = map x, Y = map y
// Output: carry set = visible, carry clear = not visible
// Phase 3: always returns visible (town is fully lit)
// Preserves: A, X, Y
los_is_visible:
    sec
    rts
