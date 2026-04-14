#importonce
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
.const SFX_LEVELUP     = $05  // Level up
.const SFX_SPELL      = $06  // Spell cast success
.const SFX_SPELL_FAIL = $07  // Spell fizzle
.const SFX_HUNGER_WARN  = $08  // Entered hungry/weak
.const SFX_HUNGER_FAINT = $09  // Entered faint

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
// Preserves: X, Y
sound_play:
    cmp #SFX_NONE
    beq !done+
    cmp #10
    bcs !done+              // Defensive: ignore invalid effect IDs instead of indirect-jumping into garbage
    sta zp_snd_effect
    txa
    pha
    tya
    pha

    // Gate off first (in case previous sound still playing)
    lda #0
    sta SID_V3_CTRL

    // Dispatch to effect setup
    lda zp_snd_effect
    beq !play_bump+
    cmp #SFX_HIT
    beq !play_hit+
    cmp #SFX_MISS
    beq !play_miss+
    cmp #SFX_PICKUP
    beq !play_pickup+
    cmp #SFX_DEATH
    beq !play_death+
    cmp #SFX_LEVELUP
    beq !play_levelup+
    cmp #SFX_SPELL
    beq !play_spell+
    cmp #SFX_SPELL_FAIL
    beq !play_spell_fail+
    cmp #SFX_HUNGER_WARN
    beq !play_hunger_warn+
    jsr sfx_hunger_faint
    jmp !restore+
!play_bump:
    jsr sfx_bump
    jmp !restore+
!play_hit:
    jsr sfx_hit
    jmp !restore+
!play_miss:
    jsr sfx_miss
    jmp !restore+
!play_pickup:
    jsr sfx_pickup
    jmp !restore+
!play_death:
    jsr sfx_death
    jmp !restore+
!play_levelup:
    jsr sfx_levelup
    jmp !restore+
!play_spell:
    jsr sfx_spell
    jmp !restore+
!play_spell_fail:
    jsr sfx_spell_fail
    jmp !restore+
!play_hunger_warn:
    jsr sfx_hunger_warn

!restore:
    pla
    tay
    pla
    tax

!done:
    rts

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
    lda #$0a                // Attack=0, Decay=10 (longer decay, no sustain)
    sta SID_V3_AD
    lda #$00                // Sustain=0, Release=0
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
    lda #$0c                // Attack=0, Decay=12 (longer decay, no sustain)
    sta SID_V3_AD
    lda #$00                // Sustain=0, Release=0
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

// Spell: ethereal triangle wave
sfx_spell:
    lda #$08
    sta SID_V3_AD
    lda #$00
    sta SID_V3_SR
    lda #$00
    sta SID_V3_FREQ_LO
    lda #$14
    sta SID_V3_FREQ_HI
    lda #WAVE_TRIANGLE | WAVE_GATE
    sta SID_V3_CTRL
    rts

// Spell fail: short noise buzz
sfx_spell_fail:
    lda #$06
    sta SID_V3_AD
    lda #$00
    sta SID_V3_SR
    lda #$00
    sta SID_V3_FREQ_LO
    lda #$0c
    sta SID_V3_FREQ_HI
    lda #WAVE_NOISE | WAVE_GATE
    sta SID_V3_CTRL
    rts

// Hunger warn: restrained low narrow pulse
sfx_hunger_warn:
    lda #$27
    sta SID_V3_AD
    lda #$00
    sta SID_V3_SR
    lda #$00
    sta SID_V3_PW_LO
    lda #$02
    sta SID_V3_PW_HI
    lda #$00
    sta SID_V3_FREQ_LO
    lda #$08
    sta SID_V3_FREQ_HI
    lda #WAVE_PULSE | WAVE_GATE
    sta SID_V3_CTRL
    rts

// Hunger faint: lower, harsher pulse used only at the final danger state
sfx_hunger_faint:
    lda #$3a
    sta SID_V3_AD
    lda #$00
    sta SID_V3_SR
    lda #$00
    sta SID_V3_PW_LO
    lda #$01
    sta SID_V3_PW_HI
    lda #$00
    sta SID_V3_FREQ_LO
    lda #$05
    sta SID_V3_FREQ_HI
    lda #WAVE_PULSE | WAVE_GATE
    sta SID_V3_CTRL
    rts
