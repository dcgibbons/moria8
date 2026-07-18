#importonce

// Call the per-monster visibility implementation stored under KERNAL ROM.
// The caller does not depend on processor flags returned by the implementation.
run_monster_update_visibility_one:
    php
    sei
    lda $01
    pha
    lda #BANK_NO_KERNAL
    sta $01
    jsr monster_update_visibility_one
    pla
    sta $01
    plp
    rts
