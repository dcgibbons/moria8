#importonce
// scene_mat_tile.s — mat's immediate tile render (P5).

// scene_render_mat_tile — Immediate-render the tile at zp_temp0/zp_temp1
// (render_single_tile's own inputs, which it preserves) and set mat's
// scene-dirty aggregate. Called from mat_mark_tile_dirty_if_nonlocal when
// a visible/detected monster changes a non-local tile: rendering here
// (old viewport, before update_visibility/viewport_update) means only a
// local-box redraw is needed later. Visibility-flag edge cases are
// covered by the existing reveal path, which forces a full redraw.
#importonce
// scene_mat_tile.s — mat's immediate tile render (P5).

// scene_render_mat_tile — Immediate-render the tile at zp_temp0/zp_temp1
// (render_single_tile's own inputs, which it preserves) and bump the
// scene-dirty aggregate. render_single_tile preserves zp_ptr0 for its
// callers in the monster-AI loop.
scene_render_mat_tile:
    jsr render_single_tile
    inc mat_scene_dirty
    rts
