#importonce
// services.s — BBC Master 128 IRQ, BRKV fault recovery, and platform lifecycle (< $3000).
//
// Authority: docs/BBCMASTER_MEMORY_CONTRACT.md.
// Note: MOS 3.20 keyboard scanning and SOUND duration counters run from the
// 100 Hz System VIA IRQ1 handler. Because MOS IRQ1 only touches MOS workspace
// ($0090-$00FF / $0200-$02FF) and never touches $0002-$008F, $3000-$7FFF, or
// $8000-$BFFF, we keep IRQ enabled during input/MOS calls or throughout
// runtime while ensuring BRKV ($0202) is always caught by our fault handler.

#import "hal/layout.s"
#import "memory.s"
#import "sound.s"

// ============================================================
// IRQ & BRKV Vector Management
// ============================================================
hal_irq_install_runtime:
    clc
    rts

hal_irq_restore_os:
    clc
    rts

hal_irq_mask:
    sei
    rts

hal_irq_unmask:
    cli
    rts

hal_irq_ack:
    rts

hal_irq_critical_begin:
    sei
    rts

hal_irq_critical_end:
    cli
    rts

// beeb_brk_handler — Catch MOS/DFS BRK errors (BRKV $0202) and return cleanly
// to the active EnterMos/ExitMos caller with Carry set and A = fault code.
// When beeb_mos_active == 0 (unexpected BRK outside MOS), jump to panic.
beeb_brk_handler:
    lda beeb_mos_active
    beq !unhandled_brk+
    ldy #0
    lda (zp_mos_brk_ptr),y
    bne !got_err+
    lda #$ff
!got_err:
    sta beeb_last_mos_error
    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    ldx beeb_mos_saved_sp
    txs
    lda #0
    sta beeb_mos_active
    lda beeb_last_mos_error
    sec
    rts
!unhandled_brk:
    ldy #0
    lda (zp_mos_brk_ptr),y
    jmp hal_platform_panic

beeb_mos_active:     .byte 0
beeb_mos_saved_sp:   .byte 0
beeb_last_mos_error: .byte 0

// ============================================================
// Platform Lifecycle (< $3000)
// ============================================================
hal_platform_init_early:
    sei
    // Install BRKV ($0202-$0203) to catch DFS/MOS errors without printing to screen
    lda #<beeb_brk_handler
    sta MOS_BRKV
    lda #>beeb_brk_handler
    sta MOS_BRKV + 1

    // Save boot filing-system ROMSEL ($00F4) and establish Bank 4 ($04) + ACCCON_NORMAL ($01)
    lda zp_mos_romsel_shadow
    sta beeb_boot_romsel
    lda #ROMSEL_BANK4
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    cli

    // Configure MOS keyboard via OSBYTE:
    //   1. *FX 4, 1: cursor keys return $88..$8B
    lda #$04
    ldx #$01
    ldy #$00
    jsr MOS_OSBYTE
    //   2. *FX 202, 24, 231: Set bit 4 ($10 = Caps Lock OFF) and bit 3 ($08 = Shift Lock OFF)
    //      in MOS keyboard status byte $0258 so unshifted letters emit 'a'..'z'
    lda #$ca
    ldx #$18
    ldy #$e7
    jsr MOS_OSBYTE
    //   3. *FX 229, 1: Escape key emits ASCII $1B instead of Escape condition
    lda #$e5
    ldx #$01
    ldy #$00
    jsr MOS_OSBYTE

    // Initialize 80x24 Mode 0 display & 1 KB C64-ordered RAM font in LYNNE
    jsr screen_init
    clc
    rts

hal_platform_init_runtime:
    jsr hal_sound_init
    clc
    rts

beeb_platform_main_loop_begin:
    clc
    rts

beeb_platform_vector_reassert:
    lda #<beeb_brk_handler
    sta MOS_BRKV
    lda #>beeb_brk_handler
    sta MOS_BRKV + 1
    lda #<beeb_wrch_noop
    sta MOS_WRCHV
    lda #>beeb_wrch_noop
    sta MOS_WRCHV + 1
    clc
    rts

beeb_platform_runtime_resync:
    lda #ROMSEL_BANK4
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    clc
    rts

hal_platform_character_sheet_begin:
    clc
    rts

hal_platform_shutdown:
!halt:
    jmp !halt-

// hal_platform_panic — Display "Pxx" hex at top-left of Mode 0 screen and halt.
hal_platform_panic:
    pha
    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    lda #$50                // 'P' screen code
    ldx #0
    ldy #0
    jsr screen_put_char_at
    pla
    pha
    lsr
    lsr
    lsr
    lsr
    ldx #1
    jsr beeb_panic_hex
    pla
    and #$0f
    ldx #2
    jsr beeb_panic_hex
!halt:
    jmp !halt-

beeb_panic_hex:
    and #$0f
    cmp #10
    bcc !digit+
    clc
    adc #$37                // 10..15 -> 'A'..'F' ($41..$46)
    jmp !show+
!digit:
    ora #$30                // 0..9 -> '0'..'9' ($30..$39)
!show:
    ldy #0
    jmp screen_put_char_at
