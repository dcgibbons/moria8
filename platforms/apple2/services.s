// services.s — Apple IIe hal_sound_* (speaker), hal_irq_* (SEI world),
// hal_platform_* lifecycle.
//
// Sound: synchronous speaker clicks at $C030, one tone per semantic ID
// (SFX_* IDs from core/sound.s, which this port does not import). M4 polish
// replaces the single-tone table with shaped patterns.
//
// IRQ: the game runs SEI with no interrupt sources (plan, Zero-Page
// Strategy). hal_irq_unmask deliberately stays masked — that is the correct
// policy on this hardware, not a placeholder: unmasking would only expose
// the firmware-IRQ-clobbers-$45 hazard with no source to serve.

#import "hal/layout.s"

// ============================================================
// Sound
// ============================================================

// Per-ID tone table: period (smaller = higher pitch), pulse count.
a2_sfx_period:
    .byte $60, $40, $20, $50, $18, $30, $28, $70, $50, $18
a2_sfx_count:
    .byte $18, $30, $10, $20, $c0, $60, $50, $40, $30, $e0

// hal_sound_init — Silence speaker state. Preserves X, Y.
hal_sound_init:
hal_sound_stop:
    lda #0
    sta zp_snd_timer
    sta zp_snd_phase
    lda #$ff                // SFX_NONE
    sta zp_snd_effect
    clc
    rts

// hal_sound_play — A = SFX_* ID (0-9). Clicks the speaker.
// Preserves: nothing (A, X, Y clobbered)
hal_sound_play:
    cmp #10
    bcs !done+              // unknown ID / SFX_NONE -> silence
    tax
    lda a2_sfx_period,x
    sta zp_temp4
    lda a2_sfx_count,x
    tay
    ldx zp_temp4
!pulse:
    sta $c030               // toggle speaker
!wait:
    dex
    bne !wait-
    ldx zp_temp4
    dey
    bne !pulse-
!done:
    clc
    rts

// hal_sound_update — Clicks are synchronous; no envelope to advance.
hal_sound_update:
    clc
    rts

// ============================================================
// IRQ (SEI world)
// ============================================================

hal_irq_install_runtime:
    sei
    clc
    rts

hal_irq_restore_os:
    sei
    clc
    rts

hal_irq_mask:
    sei
    rts

hal_irq_unmask:
    rts                     // policy: remain SEI (see header)

hal_irq_ack:
    rts

hal_irq_critical_begin:
    sei
    rts

hal_irq_critical_end:
    rts

// ============================================================
// Platform lifecycle
// ============================================================

// Soft switches (display-related A2_* consts live in screen_a2.s)
.const A2_80STORE_ON  = $c001
.const A2_80COL_ON    = $c00d
.const A2_ALTCHARSET_ON = $c00f

// hal_platform_init_early — Establish display + firmware state.
// Preserves: nothing
hal_platform_init_early:
    sta A2_TEXT_ON          // text mode
    sta A2_80COL_ON         // 80-column display
    sta A2_80STORE_ON       // PAGE2 now selects text page half
    sta A2_ALTCHARSET_ON    // alternate charset (upper/lower)
    sta A2_PAGE2_OFF        // main half active
    sta A2_INTC3ROM         // internal C3 firmware for AUXMOVE
    jsr a2_ramdisk_disconnect
    jsr a2_install_zp_thunks
    clc
    rts

// a2_ramdisk_disconnect — Remove ProDOS's /RAM volume from the device
// list (TRM 5.2.2.2 procedure). /RAM's volume directory and bitmap live
// in aux blocks 02-03 — the aux text page ($0400-$07FF) — so ProDOS
// volume searches would otherwise read our display bytes as a directory
// (the first volume searched on a miss is /RAM; a garbage directory is a
// crash vector). The game never uses /RAM, so the disconnect is silent.
a2_ramdisk_disconnect:
    php
    sei
    lda $bf98               // MACHID: bits 5,4 = 11 -> 128K
    and #$30
    cmp #$30
    bne !done+
    lda $bf26               // slot 3 drive 2 vector == "no device"?
    cmp $bf10
    bne !cont+
    lda $bf27
    cmp $bf11
    beq !done+
!cont:
    ldy $bf31               // DEVCNT
!loop:
    lda $bf32,y             // DEVLST,Y
    and #$f3                // /RAM-class unit ids $B3/$B7/$BB/$BF
    cmp #$b3
    beq !found+
    dey
    bpl !loop-
    bmi !done+
!found:
!getloop:
    lda $bf32+1,y           // bubble trailing units down
    sta $bf32,y
    beq !exit+
    iny
    bne !getloop-
!exit:
    lda $bf10               // copy "no device connected" vector in
    sta $bf26
    lda $bf11
    sta $bf27
    dec $bf31               // DEVCNT--
!done:
    plp
    rts

// hal_platform_init_runtime — Runtime machine state after payload load.
hal_platform_init_runtime:
    jsr hal_sound_init
    clc
    rts

a2_platform_main_loop_begin:
    clc
    rts

a2_platform_vector_reassert:
    clc
    rts

// ProDOS uses 80STORE/PAGE2 while servicing MLI calls and may return with
// 80STORE off. Restore the renderer's 80-column interleave invariant.
a2_platform_runtime_resync:
    sta A2_80STORE_ON
    sta A2_PAGE2_OFF
    clc
    rts

hal_platform_character_sheet_begin:
    clc
    rts

// hal_platform_shutdown — Return to ProDOS via MLI QUIT.
hal_platform_shutdown:
    jsr $bf00
    .byte $29               // QUIT
    .word a2_quit_params
    // QUIT does not return on success; on error fall through to a safe loop
!halt:
    jmp !halt-

a2_quit_params:
    .byte 4                 // param count
    .byte 0                 // reserved
    .byte 0                 // reserved
    .word 0                 // reserved
    .byte 0                 // reserved
    .word 0                 // reserved

// hal_platform_panic — A = status. Show "Pxx" hex at row 0 and halt.
hal_platform_panic:
    pha
    lda #$d0                // 'P' normal video
    ldx #0
    ldy #0
    jsr screen_put_char_at
    pla
    pha
    lsr
    lsr
    lsr
    lsr
    jsr a2_panic_hex
    pla
    and #$0f
    jsr a2_panic_hex
!halt:
    jmp !halt-

a2_panic_hex:
    and #$0f
    cmp #10
    bcc !digit+
    clc
    adc #$b7                // 'A'-9 normal video ($c1 = 'A')
    jmp !show+
!digit:
    ora #$b0                // '0' normal video
!show:
    inx
    ldy #0
    jmp screen_put_char_at
