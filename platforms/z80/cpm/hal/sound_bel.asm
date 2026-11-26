; sound_bel.asm — CP/M console BEL (0x07) audio HAL.
;
; Requires main.asm to INCLUDE "memory.inc", "state.inc", and "bdos_io.asm".
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax).

    EXPORT sound_init
    EXPORT sound_toggle
    EXPORT sound_bell

; ---------------------------------------------------------------------------
; sound_init — Enable BEL alerts by default (sound_enabled = 1).
; Preserves: BC, DE, HL, IX, IY (clobbers AF)
; ---------------------------------------------------------------------------
sound_init:
    LD   A, 1
    LD   (sound_enabled), A
    RET

; ---------------------------------------------------------------------------
; sound_toggle — Toggle sound_enabled (0 <-> 1).
; Output: A = new sound_enabled state (Z=1 if muted, Z=0 if enabled)
; Preserves: BC, DE, HL, IX, IY (clobbers AF)
; ---------------------------------------------------------------------------
sound_toggle:
    LD   A, (sound_enabled)
    XOR  1
    LD   (sound_enabled), A
    RET

; ---------------------------------------------------------------------------
; sound_bell — Emit ASCII BEL (0x07) via bdos_rawio_putc if sound_enabled != 0.
; Preserves: BC, DE, HL, IX, IY (clobbers AF)
; ---------------------------------------------------------------------------
sound_bell:
    LD   A, (sound_enabled)
    OR   A
    RET  Z
    LD   A, KEY_BEL
    JP   bdos_rawio_putc
