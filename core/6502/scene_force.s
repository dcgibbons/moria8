#importonce
// scene_force.s — Forced-full scene change marker (P5).

// scene_force_full_redraw — Mark a scene change that immediate rendering
// cannot cover (forced-full command tails, search aggregation). Runs
// after turn_post_action. The cheap-path veto must NOT latch
// zp_dirty_count: that latch is consumed by the NEXT turn's
// turn_post_action into turn_scene_dirty, and run-step stop logic reads
// turn_scene_dirty every step, so a leaked latch cancelled auto-run
// after one step. Clearing mat_scene_dirty vetoes the cheap path
// (scene_dirty_check requires it set) without leaking state.
// Input: A = value for turn_scene_dirty.
scene_force_full_redraw:
    sta turn_scene_dirty
    lda #0
    sta mat_scene_dirty
    rts
