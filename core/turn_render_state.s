#importonce
// turn_render_state.s — Shared per-turn render state flags

turn_scene_dirty: .byte 0

// 1 = a disk prompt (asset_load_ask_for_disk) cleared the screen since the
// last main_loop pass, which rebuilds the gameplay view and clears it (lsr).
disk_prompt_redraw_pending: .byte 0

// Reuse the dormant dirty-tile count scratch byte as the pending redraw latch.
// This keeps the action-owned redraw request alive across turn_post_action
// without growing the resident main image.
.label turn_action_redraw_pending = zp_dirty_count
