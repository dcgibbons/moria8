#importonce
// reu_stub.s — Minimal inert symbols satisfying core/tier_manager.s REU hooks.
// Commander X16 preloads monster tiers into native banked RAM (Banks 5-8).

reu_present:
reu_loading_count:     .byte 0

reu_load_all_tiers:
reu_fetch_tier:
reu_show_file:
reu_render_progress:
    rts
