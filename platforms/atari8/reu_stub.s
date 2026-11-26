#importonce
// reu_stub.s — Atari 8-bit minimal inert stub for C64 REU symbols read by
// main.s and core/6502/tier_manager.s.
//
// Atari 130XE extended RAM caching is handled transparently inside
// hal_asset_load_prg_header / hal_asset_load_title in storage.s.

reu_present:           .byte 0
reu_banks:             .byte 0
reu_size_kb:           .word 0
reu_loading_count:     .byte 0

reu_load_all_tiers:
reu_fetch_tier:
reu_show_file:
reu_render_progress:
    rts
