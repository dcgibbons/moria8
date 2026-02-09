// sound.s — Minimal SID sound effects
//
// Simple fire-and-forget sound effects using SID voice 3.
// Voice 3 is used to avoid conflicts with any future music
// (voices 1 and 2 reserved).
//
// Each effect sets waveform, ADSR, frequency, then gates on.
// The SID hardware handles the envelope — no per-frame update needed
// for simple effects. The timer in zp_snd_timer can be used to
// gate off after a duration if needed, but most effects use
// short envelopes that self-release.

// SID registers
.const SID_BASE     = $d400

// Voice 3 registers (offset +14 from SID base)
.const SID_V3_FREQ_LO  = SID_BASE + 14
.const SID_V3_FREQ_HI  = SID_BASE + 15
.const SID_V3_PW_LO    = SID_BASE + 16
.const SID_V3_PW_HI    = SID_BASE + 17
.const SID_V3_CTRL     = SID_BASE + 18
.const SID_V3_AD        = SID_BASE + 19
.const SID_V3_SR        = SID_BASE + 20

// Global SID registers
.const SID_FILTER_LO   = SID_BASE + 21
.const SID_FILTER_HI   = SID_BASE + 22
.const SID_FILTER_CTRL = SID_BASE + 23
.const SID_VOLUME      = SID_BASE + 24

// Waveform control bits
.const WAVE_GATE     = $01
.const WAVE_TRIANGLE = $10
.const WAVE_SAW      = $20
.const WAVE_PULSE    = $40
.const WAVE_NOISE    = $80

// Sound effect IDs
.const SFX_NONE     = $ff
.const SFX_BUMP     = $00  // Wall collision
.const SFX_HIT      = $01  // Melee hit landed
.const SFX_MISS     = $02  // Melee miss
.const SFX_PICKUP   = $03  // Item picked up
.const SFX_DEATH    = $04  // Player death
.const SFX_LEVELUP  = $05  // Level up

// ============================================================
// Subroutines
// ============================================================

// sound_init — Initialize SID for sound effects
// Sets volume to max, clears voice 3.
// Preserves: X, Y
sound_init:
    // Set master volume to max (lower nibble of $D418)
    lda #$0f
    sta SID_VOLUME
    // Clear voice 3
    lda #0
    sta SID_V3_CTRL
    sta SID_V3_AD
    sta SID_V3_SR
    sta SID_V3_FREQ_LO
    sta SID_V3_FREQ_HI
    lda #SFX_NONE
    sta zp_snd_effect
    rts

// sound_play — Play a sound effect
// Input: A = SFX_* constant
// Preserves: nothing
sound_play:
    cmp #SFX_NONE
    beq !done+
    sta zp_snd_effect

    // Gate off first (in case previous sound still playing)
    lda #0
    sta SID_V3_CTRL

    // Dispatch to effect setup
    lda zp_snd_effect
    asl                     // x2 for word-sized jump table
    tax
    lda sfx_table,x
    sta zp_ptr0
    lda sfx_table + 1,x
    sta zp_ptr0_hi
    jmp (zp_ptr0)           // Indirect jump to effect setup

!done:
    rts

// Sound effect jump table
sfx_table:
    .word sfx_bump
    .word sfx_hit
    .word sfx_miss
    .word sfx_pickup
    .word sfx_death
    .word sfx_levelup

// --- Individual effect setups ---
// Each sets frequency, ADSR, waveform, then gates on.

// Bump: short low noise burst
sfx_bump:
    lda #$08                // Attack=0, Decay=8
    sta SID_V3_AD
    lda #$00                // Sustain=0, Release=0
    sta SID_V3_SR
    lda #$00                // Low frequency
    sta SID_V3_FREQ_LO
    lda #$04
    sta SID_V3_FREQ_HI
    lda #WAVE_NOISE | WAVE_GATE
    sta SID_V3_CTRL
    rts

// Hit: medium pitch sawtooth punch
sfx_hit:
    lda #$09                // Attack=0, Decay=9
    sta SID_V3_AD
    lda #$00
    sta SID_V3_SR
    lda #$00
    sta SID_V3_FREQ_LO
    lda #$10
    sta SID_V3_FREQ_HI
    lda #WAVE_SAW | WAVE_GATE
    sta SID_V3_CTRL
    rts

// Miss: quick high noise blip
sfx_miss:
    lda #$05                // Attack=0, Decay=5
    sta SID_V3_AD
    lda #$00
    sta SID_V3_SR
    lda #$00
    sta SID_V3_FREQ_LO
    lda #$20
    sta SID_V3_FREQ_HI
    lda #WAVE_NOISE | WAVE_GATE
    sta SID_V3_CTRL
    rts

// Pickup: bright rising triangle
sfx_pickup:
    lda #$06                // Attack=0, Decay=6
    sta SID_V3_AD
    lda #$50                // Sustain=5, Release=0
    sta SID_V3_SR
    lda #$00
    sta SID_V3_FREQ_LO
    lda #$18
    sta SID_V3_FREQ_HI
    lda #WAVE_TRIANGLE | WAVE_GATE
    sta SID_V3_CTRL
    rts

// Death: long low descending noise
sfx_death:
    lda #$0f                // Attack=0, Decay=15 (long)
    sta SID_V3_AD
    lda #$09                // Sustain=0, Release=9 (long tail)
    sta SID_V3_SR
    lda #$00
    sta SID_V3_FREQ_LO
    lda #$03
    sta SID_V3_FREQ_HI
    lda #WAVE_NOISE | WAVE_GATE
    sta SID_V3_CTRL
    rts

// Level up: bright pulse chord
sfx_levelup:
    lda #$09                // Attack=0, Decay=9
    sta SID_V3_AD
    lda #$a0                // Sustain=10, Release=0
    sta SID_V3_SR
    lda #$00                // Pulse width 50%
    sta SID_V3_PW_LO
    lda #$08
    sta SID_V3_PW_HI
    lda #$00
    sta SID_V3_FREQ_LO
    lda #$1c
    sta SID_V3_FREQ_HI
    lda #WAVE_PULSE | WAVE_GATE
    sta SID_V3_CTRL
    rts
