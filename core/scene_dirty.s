#importonce
// scene_dirty.s — Per-turn scene-dirty consumption (P5).
//
// scene_dirty_check — Pick the cheap or full redraw path for a
// turn_scene_dirty turn. Cheap (render only the player's local box) iff
// the turn's dirt is provably already rendered, i.e. mat_scene_dirty is
// set (mat immediate-rendered non-local monster tiles at mark time).
// Anything the immediate render cannot cover (forced-full command
// tails, search aggregation, combat kills, spell tile effects) never
// sets mat_scene_dirty — scene_force_full_redraw explicitly clears it
// to veto the cheap path — so the full fallback handles it. No
// zp_dirty_count guard: every producer of that latch runs mid-turn and
// is consumed by turn_post_action, so it is always clear at dispatch.
scene_dirty_check:
    lda mat_scene_dirty
    beq !sdc_full+
    jsr render_local_area
    jmp scene_post_move
!sdc_full:
    jmp scene_full_fallback
