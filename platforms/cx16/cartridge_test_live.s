// Diagnostic helper for headless live-IRQ / VERA PSG / KEYHDL verification of
// build/moria8-cx16.crt. Compiled against cartridge main.sym and spliced into a
// temporary test copy of MORIA8.PRG by platforms/cx16/test_cartridge.py.
.cpu _65c02
#import "cartridge_product_symbols.inc"

.assert "Resident program ends at or below $9980", program_end <= $9980, true

.pc = $9980 "Live Cold-Boot Sound & IRQ Diagnostic"
live_test_entry:
    lda live_init_seen
    bne !after_p+
    php
    pla
    sta live_saved_p
    lda #1
    sta live_init_seen
!after_p:
    jsr hal_sound_update
    lda live_stage
    beq !stage0+
    cmp #1
    beq !stage1+
    jmp $ffff           // Stage 2 ("Roll Statistics"): trigger dump.bin & exit

!stage0:
    jsr wait_3_jiffies
    bcs !stage0_ready+
    rts
!stage0_ready:
    lda $00
    pha
    stz $00
    stz $01
    lda #$31            // X16 keynum $31 ('N') press
    jsr call_keyhdl
    lda cx16_key_down + 6
    sta live_keydown_sample
    lda #$b1            // X16 keynum $31 ('N') release
    jsr call_keyhdl
    lda cx16_key_down + 6
    sta live_keyup_sample
    pla
    sta $00
    stz $01
    lda #$4e            // PETSCII 'N' -> KERNAL kbdbuf_put
    jsr $fec3
    lda #1
    sta live_stage
    rts

!stage1:
    lda zp_snd_timer
    beq !sound_done+
    lda live_saw_snd_timer
    bne !sound_still_on+
    lda zp_snd_timer
    sta live_saw_snd_timer
!sound_still_on:
    rts
!sound_done:
    jsr wait_2_jiffies
    bcs !stage1_ready+
    rts
!stage1_ready:
    stz $01
    lda #$41            // PETSCII 'A' -> KERNAL kbdbuf_put
    jsr $fec3
    lda #2
    sta live_stage
    rts

wait_3_jiffies:
    lda #3
    bra wait_n_jiffies
wait_2_jiffies:
    lda #2
wait_n_jiffies:
    sta live_wait_target
    stz $01
    jsr $ffde           // KERNAL RDTIM -> A = jiffy low byte
    ldx live_jiffy_armed
    bne !check_elapsed+
    sta live_jiffy_start
    lda #1
    sta live_jiffy_armed
    clc
    rts
!check_elapsed:
    sec
    sbc live_jiffy_start
    cmp live_wait_target
    bcc !not_yet+
    stz live_jiffy_armed
    sec
    rts
!not_yet:
    clc
    rts

call_keyhdl:
    jmp ($032e)

live_stage:          .byte 0
live_saved_p:        .byte 0
live_jiffy_armed:    .byte 0
live_jiffy_start:    .byte 0
live_keydown_sample: .byte 0
live_keyup_sample:   .byte 0
live_saw_snd_timer:  .byte 0
live_init_seen:      .byte 0
live_wait_target:    .byte 0

.assert "Live test helper fits below tier-name pool ($9B00)", * <= $9b00, true
