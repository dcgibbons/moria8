#importonce
// title_cache_runtime.s — C128 title-art session cache in Bank 1
//
// Keeps title returns independent from the currently-mounted disk after the
// first successful title load. The cache lives in Bank 1 reserved gap 0.

c128_title_load_and_draw_cached:
    jsr c128_title_cache_is_valid
    bne !ctld_disk+
    jsr c128_title_cache_restore_to_map
    bcs !ctld_disk+
    jsr hal_screen_clear
    jmp title_render_data

!ctld_disk:
    jsr hal_asset_load_title
    bcc !ctld_loaded+
    jmp title_fallback_render
!ctld_loaded:
    lda #0
    sta zp_kernal_status
    jsr c128_title_cache_store_from_map
    jsr hal_screen_clear
    jmp title_render_data

c128_title_asset_load:
    // C128: TITLE art must load into Bank 1 MAP_BASE ($4000-$4EFF).
    // SETBNK controls LOAD destination bank; keep filename in Bank 0.
    lda #1
    ldx #0
    jsr safe_setbnk

    lda #hal_storage_title_name_len
    ldx #<hal_storage_title_name
    ldy #>hal_storage_title_name
    jsr hal_storage_setnam

    lda #2
    ldx $ba
    ldy #1
    jsr hal_storage_setlfs

    lda #0
    ldx #<MAP_BASE
    ldy #>MAP_BASE
    jsr kernal_load

    php
    sei
    lda #2
    jsr w_close

    lda #0
    ldx #0
    jsr safe_setbnk

    plp
    rts

c128_title_cache_is_valid:
    php
    sei
    lda #MMU_RAM_BANK1
    sta MMU_CR
    lda BANK1_TITLE_CACHE_MARKER_BASE
    tax
    lda #MMU_ALL_RAM
    sta MMU_CR
    plp
    txa
    cmp #C128_TITLE_CACHE_VALID_MARKER
    rts

c128_title_cache_store_from_map:
    php
    sei
    lda #MMU_RAM_BANK1
    sta MMU_CR
    lda #<MAP_BASE
    sta zp_ptr0
    lda #>MAP_BASE
    sta zp_ptr0_hi
    lda #<BANK1_TITLE_CACHE_DATA_BASE
    sta zp_ptr1
    lda #>BANK1_TITLE_CACHE_DATA_BASE
    sta zp_ptr1_hi
    lda #0
    sta BANK1_TITLE_CACHE_MARKER_BASE
!ctcs_loop:
    ldy #0
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    cmp #$ff
    beq !ctcs_done+
    jsr c128_title_cache_advance_cache_ptr
    bcc !ctcs_loop-
    lda #0
    sta BANK1_TITLE_CACHE_MARKER_BASE
    jmp !ctcs_exit+
!ctcs_done:
    lda #C128_TITLE_CACHE_VALID_MARKER
    sta BANK1_TITLE_CACHE_MARKER_BASE
!ctcs_exit:
    lda #MMU_ALL_RAM
    sta MMU_CR
    plp
    rts

// carry clear = restored successfully, carry set = cache invalid/truncated
c128_title_cache_restore_to_map:
    php
    sei
    lda #MMU_RAM_BANK1
    sta MMU_CR
    lda #<MAP_BASE
    sta zp_ptr0
    lda #>MAP_BASE
    sta zp_ptr0_hi
    lda #<BANK1_TITLE_CACHE_DATA_BASE
    sta zp_ptr1
    lda #>BANK1_TITLE_CACHE_DATA_BASE
    sta zp_ptr1_hi
!ctcr_loop:
    ldy #0
    lda (zp_ptr1),y
    sta (zp_ptr0),y
    cmp #$ff
    beq !ctcr_done+
    jsr c128_title_cache_advance_cache_ptr
    bcc !ctcr_loop-
    lda #0
    sta BANK1_TITLE_CACHE_MARKER_BASE
    ldx #1
    bne !ctcr_exit+
!ctcr_done:
    ldx #0
!ctcr_exit:
    lda #MMU_ALL_RAM
    sta MMU_CR
    plp
    txa
    bne !ctcr_fail+
    clc
    rts
!ctcr_fail:
    sec
    rts

// advance source/dest pointers while keeping the cache pointer inside the
// reserved Bank 1 title-cache slot
// carry clear = room remains, carry set = exceeded reserved cache region
c128_title_cache_advance_cache_ptr:
    inc zp_ptr1
    bne !cache_ok+
    inc zp_ptr1_hi
!cache_ok:
    inc zp_ptr0
    bne !map_ok+
    inc zp_ptr0_hi
!map_ok:
    lda zp_ptr1_hi
    cmp #>(BANK1_TITLE_CACHE_END + 1)
    bcc !room+
    bne !full+
    lda zp_ptr1
    cmp #<(BANK1_TITLE_CACHE_END + 1)
    bcc !room+
!full:
    sec
    rts
!room:
    clc
    rts
