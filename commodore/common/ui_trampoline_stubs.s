#importonce
// ui_trampoline_stubs.s — Test-only aliases for trampolines
//
// In the game build, trampolines bank out KERNAL to call $F000/$E000 code.
// In test builds, the code is at normal addresses so direct calls work.

// $F000 UI screen trampolines
.label tramp_ui_char_display = ui_char_display
.label tramp_ui_inv_display = ui_inv_display
.label tramp_ui_help_display = ui_help_display
.label tramp_ui_equip_display = ui_equip_display

// $E000 store overlay trampolines
.label tramp_store_init_all = store_init_all
.label tramp_store_restock_all = store_restock_all
.label tramp_store_enter = store_enter

// $E000 startup overlay trampolines
.label tramp_player_create = player_create

// ============================================================
// R14 stubs — functions from main.s needed by ego_items.s,
// ui_inventory.s, and ui_store.s in test context
// ============================================================

// roll_tool_ego_check — Handle ego roll for digging tools
// Called from roll_ego_type (ego_items.s) when category != ICAT_WEAPON.
// A = category value from it_category lookup
// Returns: A = ego type (0, 1, or 2)
roll_tool_ego_check:
    cmp #ICAT_DIGGING           // Re-test A (flags stale from prior CMP in roll_ego_type)
    bne !rtc_zero+              // category != 0 → not a digging tool
    lda zp_player_dlvl
    cmp #10
    bcc !rtc_zero+              // DL < 10 → basic only (ego=0)
    lda #100
    jsr rng_range               // [0, 99]
    cmp #10
    bcc !rtc_ego2+              // 10% → check for Dwarven (ego=2)
    cmp #35
    bcc !rtc_ego1+              // 25% → Gnomish/Orcish (ego=1)
!rtc_zero:
    lda #0                      // 65% → basic
    rts
!rtc_ego2:
    lda zp_player_dlvl
    cmp #20
    bcc !rtc_ego1+              // DL 10-19 can't get ego=2, downgrade to ego=1
    lda #2
    rts
!rtc_ego1:
    lda #1
    rts

// banked_ego_put_suffix — Write ego suffix to screen (no banking in tests)
banked_ego_put_suffix:
    cmp #0
    beq !beps_done+
    jsr ego_get_suffix_ptr
    ldy #0
!beps_loop:
    lda (zp_ptr0),y
    beq !beps_done+
    sty beps_save_y2
    jsr screen_put_char
    ldy beps_save_y2
    iny
    jmp !beps_loop-
!beps_done:
    rts
beps_save_y2: .byte 0

// put_tool_ego_prefix — Print ego prefix for digging tools
// Input: A = ego (1 or 2), X = item type ID (62 or 63)
put_tool_ego_prefix:
    sec
    sbc #1                      // ego - 1
    sta ptep_temp2
    txa
    sec
    sbc #62                     // type - 62
    asl                         // * 2
    clc
    adc ptep_temp2              // + (ego - 1) → index
    tax
    lda tool_ego_pfx_lo,x
    sta zp_ptr0
    lda tool_ego_pfx_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string
    rts

ptep_temp2: .byte 0

ego_pfx_gnomish: .text "Gnomish " ; .byte 0
ego_pfx_orcish:  .text "Orcish " ; .byte 0
ego_pfx_dwarven: .text "Dwarven " ; .byte 0

tool_ego_pfx_lo:
    .byte <ego_pfx_gnomish, <ego_pfx_dwarven
    .byte <ego_pfx_orcish,  <ego_pfx_dwarven
tool_ego_pfx_hi:
    .byte >ego_pfx_gnomish, >ego_pfx_dwarven
    .byte >ego_pfx_orcish,  >ego_pfx_dwarven

// put_inv_name_with_ego — Print item name with ego prefix/suffix
// Input: X = inventory slot index
put_inv_name_with_ego:
    lda inv_item_id,x
    sta pinwe_id
    stx pinwe_sl
    tax
    lda it_category,x
    bne !pinwe_not_tool+
    ldx pinwe_sl
    lda inv_ego,x
    beq !pinwe_not_tool+
    ldx pinwe_id
    jsr put_tool_ego_prefix
    lda pinwe_id
    jsr item_get_name_ptr
    jsr screen_put_string
    rts
!pinwe_not_tool:
    lda pinwe_id
    jsr item_get_name_ptr
    jsr screen_put_string
    ldx pinwe_sl
    lda inv_ego,x
    jsr banked_ego_put_suffix
    rts
pinwe_id: .byte 0
pinwe_sl: .byte 0
