#importonce
// reu_stub128.s -- C128 HAL stub for C64 REU service symbols.
//
// The C128 port forces REU absent: tier and overlay data use the Bank 1
// cache instead of REU DMA. Shared tier/overlay code still assembles
// REU branches gated on reu_present, so this file exports the same symbols
// without linking the C64 REU probing and DMA implementation into resident
// C128 RAM. reu_show_file keeps its real body because the boot preload
// progress display uses it unconditionally.

reu_present:           .byte 0
reu_banks:             .byte 0
reu_size_kb:           .word 0
reu_overlays_stashed:  .byte 0
reu_loading_count:     .byte 0

reu_load_all_tiers:
reu_fetch_tier:
reu_show_status:
reu_render_progress:
    rts

// reu_show_file — Advance the shared C128 loading progress display.
reu_show_file:
    jmp c128_show_load_progress

// Display pointer tables (0-based index). These intentionally point at the
// platform-owned KERNAL filename literals; do not add separate display copies.
.label reu_fn_tier_lo = hal_storage_tier_name_lo
.label reu_fn_tier_hi = hal_storage_tier_name_hi
.label reu_fn_ovl_lo = hal_storage_overlay_name_lo
.label reu_fn_ovl_hi = hal_storage_overlay_name_hi
.assert "Tier filename table count stays in sync", hal_storage_tier_name_hi - hal_storage_tier_name_lo, 4
