#importonce
// reu_stub.s -- Plus/4 HAL stub for C64 REU service symbols.
//
// The Plus/4 has no C64-style REU at $DF00-$DF0A. Shared tier/overlay code
// still assembles REU branches, so this file exports the same symbols without
// linking the C64 REU probing and DMA implementation into resident Plus/4 RAM.

// Keep the register constants available for shared code that assembles but
// never executes REU paths when reu_present/reu_overlays_stashed are zero.
.const REU_STATUS   = $df00
.const REU_COMMAND  = $df01
.const REU_C64LO    = $df02
.const REU_C64HI    = $df03
.const REU_REULO    = $df04
.const REU_REUHI    = $df05
.const REU_BANK     = $df06
.const REU_LENLO    = $df07
.const REU_LENHI    = $df08
.const REU_IRQMASK  = $df09
.const REU_CONTROL  = $df0a

.const REU_CMD_STASH     = $90
.const REU_CMD_FETCH     = $91
.const REU_CMD_STASH_AL  = $b0
.const REU_CMD_FETCH_AL  = $b1

reu_present:           .byte 0
reu_banks:             .byte 0
reu_size_kb:           .word 0
reu_overlays_stashed:  .byte 0
reu_loading_row:       .byte 0

reu_detect:
    lda #0
    sta reu_present
    sta reu_banks
    sta reu_size_kb
    sta reu_size_kb + 1
    sta reu_overlays_stashed
    rts

reu_load_all_tiers:
reu_stash_overlays:
reu_fetch_tier:
reu_stash:
reu_fetch:
reu_show_file:
reu_show_status:
    rts

.label reu_fn_tier_lo = hal_storage_tier_name_lo
.label reu_fn_tier_hi = hal_storage_tier_name_hi
.label reu_fn_ovl_lo = hal_storage_overlay_name_lo
.label reu_fn_ovl_hi = hal_storage_overlay_name_hi

reu_loading_hdr: .text "Loading:" ; .byte 0
