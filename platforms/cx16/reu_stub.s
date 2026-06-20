#importonce
// reu_stub.s - Commander X16 non-REU service symbols.
//
// CX16 has native banked RAM, not a C64 REU at $DF00. Shared tier setup still
// assembles REU branches, so export inert symbols and keep reu_present clear.

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

reu_loading_hdr: .text "Loading:" ; .byte 0
