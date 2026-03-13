// test_tier128.s — C128 tier transition/state regression checks for 10.2.5

#import "../../common/zeropage.s"
#import "../memory128.s"
#import "../config128.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

c128_restore_runtime_state:
    rts

// Minimal symbols required by tier_manager.s
reu_present: .byte 0
reu_loading_row: .byte 0
reu_loading_hdr: .byte 0
reu_fn_tier_lo: .byte 0, 0, 0, 0
reu_fn_tier_hi: .byte 0, 0, 0, 0
c128_cache_enabled: .byte 0
c128_cache_tiers_ready: .byte 0
c128_cache_overlays_ready: .byte 0
c128_cache_failed: .byte 0
c128_cache_tier_bits: .byte 0
c128_cache_overlay_bits: .byte 0
c128_cache_test_skip_tier: .byte 0
active_dungeon_count: .byte 0
tier_name_lo_addr: .word 0
tier_name_hi_addr: .word 0
.const MAX_DUNGEON_CREATURES = 57
cr_name_hi: .fill MAX_DUNGEON_CREATURES, 0

screen_clear: rts
screen_put_string: rts
reu_show_status: rts
reu_show_file: rts
reu_load_all_tiers: rts
reu_stash_overlays: rts
msg_print: rts
overlay_invalidate: rts
reu_fetch_tier: rts
load_tier_to_buffer: rts
c128_preload_asset_load:
    clc
    rts
c128_preload_all_overlays:
    rts

#import "../../common/tier_manager.s"

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #MACHINE_C128
    sta zp_machine_type

    // Stub tier_load: lda #1 / sta tier_loaded / rts
    lda #$a9
    sta tier_load
    lda #$01
    sta tier_load + 1
    lda #$8d
    sta tier_load + 2
    lda #<tier_loaded
    sta tier_load + 3
    lda #>tier_loaded
    sta tier_load + 4
    lda #$60
    sta tier_load + 5

fail_now:
    jmp test_fail

    // Check tier_invalidate_state clears all tracked fields.
    lda #$04
    sta current_tier
    lda #$01
    sta tier_loaded
    lda #$12
    sta c128_tier_cache_size_lo
    lda #$34
    sta c128_tier_cache_size_hi
    lda #$56
    sta tier_name_lo_addr
    lda #$78
    sta tier_name_lo_addr+1
    lda #$9a
    sta tier_name_hi_addr
    lda #$bc
    sta tier_name_hi_addr+1
    jsr tier_invalidate_state
    lda current_tier
    beq *+5
    jmp test_fail
    lda tier_loaded
    beq *+5
    jmp test_fail
    lda c128_tier_cache_size_lo
    beq *+5
    jmp test_fail
    lda c128_tier_cache_size_hi
    beq *+5
    jmp test_fail
    lda tier_name_lo_addr
    beq *+5
    jmp test_fail
    lda tier_name_lo_addr+1
    beq *+5
    jmp test_fail
    lda tier_name_hi_addr
    beq *+5
    jmp test_fail
    lda tier_name_hi_addr+1
    beq *+5
    jmp test_fail
    // First-entry routing checks.
    lda #0
    sta current_tier
    sta tier_loaded
    lda #1
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #1
    beq *+5
    jmp test_fail
    lda #0
    sta current_tier
    sta tier_loaded
    lda #10
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #2
    beq *+5
    jmp test_fail
    lda #0
    sta current_tier
    sta tier_loaded
    lda #20
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #3
    beq *+5
    jmp test_fail
    lda #0
    sta current_tier
    sta tier_loaded
    lda #30
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #4
    beq *+5
    jmp test_fail
    // In-range, step up/down, and town no-op.
    lda #1
    sta current_tier
    lda #5
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #1
    beq *+5
    jmp test_fail
    lda #1
    sta current_tier
    lda #9
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #2
    beq *+5
    jmp test_fail
    lda #2
    sta current_tier
    lda #4
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #1
    beq *+5
    jmp test_fail
    lda #2
    sta current_tier
    lda #0
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #2
    beq *+5
    jmp test_fail
    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
