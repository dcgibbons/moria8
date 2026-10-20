#importonce
// overlay_storage.s — Commander X16 boot bank preloader & O(1) RAM bank
// switcher for overlays (Banks 9-20) and monster tiers (Banks 5-8).

#import "hal/storage_policy.s"

cx16_banks_preloaded: .byte 0
cx16_preload_idx:     .byte 0

// ============================================================
// cx16_preload_banks — Preload all 19 runtime banked payloads from device 8
// into RAM Banks 3..21 at $A000 at boot time.
// ============================================================
cx16_preload_banks:
    lda #0
    sta cx16_banks_preloaded

    // 1. Bank 3: CX16.AUXDATA
    lda #CX16_BANK_AUXDATA
    sta CX16_RAM_BANK_REG
    lda #cx16_auxdata_name_len
    ldx #<cx16_auxdata_name
    ldy #>cx16_auxdata_name
    jsr cx16_kernal_load_banked_window
    bcs !fatal+

    // 2. Bank 4: CX16.HUFFDATA
    lda #CX16_BANK_HUFFDATA
    sta CX16_RAM_BANK_REG
    lda #cx16_huffdata_name_len
    ldx #<cx16_huffdata_name
    ldy #>cx16_huffdata_name
    jsr cx16_kernal_load_banked_window
    bcs !fatal+

    // 3. Banks 5..8: MONSTER.DB.1..4
    lda #0
    sta cx16_preload_idx
!tier_loop:
    ldx cx16_preload_idx
    txa
    clc
    adc #CX16_BANK_TIER_BASE
    sta CX16_RAM_BANK_REG
    lda hal_storage_tier_name_len,x
    pha
    lda hal_storage_tier_name_hi,x
    tay
    lda hal_storage_tier_name_lo,x
    tax
    pla
    jsr cx16_kernal_load_banked_window
    bcs !fatal+
    inc cx16_preload_idx
    lda cx16_preload_idx
    cmp #4
    bcc !tier_loop-

    // 4. Banks 9..20: 12 overlays (OVL.START .. OVL.TITLE)
    lda #0
    sta cx16_preload_idx
!ovl_loop:
    ldx cx16_preload_idx
    txa
    clc
    adc #CX16_BANK_OVERLAY_BASE
    sta CX16_RAM_BANK_REG
    lda hal_storage_overlay_name_len,x
    pha
    lda hal_storage_overlay_name_hi,x
    tay
    lda hal_storage_overlay_name_lo,x
    tax
    pla
    jsr cx16_kernal_load_banked_window
    bcs !fatal+
    inc cx16_preload_idx
    lda cx16_preload_idx
    cmp #hal_platform_overlay_count
    bcc !ovl_loop-

    // 5. Bank 21: TITLE art stream
    lda #CX16_BANK_TITLE_ART
    sta CX16_RAM_BANK_REG
    lda #hal_storage_title_name_len
    ldx #<hal_storage_title_name
    ldy #>hal_storage_title_name
    jsr cx16_kernal_load_banked_window
    bcs !fatal+

    lda #1
    sta cx16_banks_preloaded
    clc
    rts

!fatal:
    lda #HAL_STATUS_ERR_WRONG_MEDIA
    jmp hal_platform_panic

// ============================================================
// cx16_asset_try_bank_switch — Resolve overlay or tier load by switching
// CX16_RAM_BANK_REG ($00) when preloaded.
// Input: X = filename pointer lo, Y = filename pointer hi.
// Output: C=0 bank switched; C=1 not matched / not preloaded.
// ============================================================
cx16_asset_try_bank_switch:
    lda cx16_banks_preloaded
    beq !miss+
    stx zp_temp0
    sty zp_temp1

    // Check 12 overlays -> Bank (index + 9)
    ldx #hal_platform_overlay_count - 1
!find_ovl:
    lda hal_storage_overlay_name_lo,x
    cmp zp_temp0
    bne !next_ovl+
    lda hal_storage_overlay_name_hi,x
    cmp zp_temp1
    beq !found_ovl+
!next_ovl:
    dex
    bpl !find_ovl-

    // Check 4 monster tiers -> Bank (index + 5)
    ldx #3
!find_tier:
    lda hal_storage_tier_name_lo,x
    cmp zp_temp0
    bne !next_tier+
    lda hal_storage_tier_name_hi,x
    cmp zp_temp1
    beq !found_tier+
!next_tier:
    dex
    bpl !find_tier-

!miss:
    sec
    rts

!found_ovl:
    txa
    clc
    adc #CX16_BANK_OVERLAY_BASE
    sta CX16_RAM_BANK_REG
    clc
    rts

!found_tier:
    txa
    clc
    adc #CX16_BANK_TIER_BASE
    sta CX16_RAM_BANK_REG
    clc
    rts
