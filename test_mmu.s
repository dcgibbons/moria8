.pc = $2000
    sei
    lda #$05
    sta $d506
    lda #$0e
    sta $ff00
    lda #$2f
    sta $00

    lda #$37
    sta $01
    lda $f2d5
    sta $02

    lda #$35
    sta $01
    lda $f2d5
    sta $03

    // infinite loop
    jmp *
