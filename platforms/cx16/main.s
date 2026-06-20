// main.s - Commander X16 boot-to-title milestone
//
// This is intentionally a narrow platform bring-up slice: initialize KERNAL
// text output, render a title/menu, and acknowledge menu-key input.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(cx16_entry)

.pc = $0810 "CX16 Boot"

.const KERNAL_CINT = $ff81
.const KERNAL_CHROUT = $ffd2
.const KERNAL_GETIN = $ffe4
.const PRINT_PTR = $22
.const PRINT_PTR_HI = $23

cx16_entry:
    sei
    lda #0
    sta $01                 // Select KERNAL ROM bank before X16 KERNAL calls.
    jsr KERNAL_CINT
    jsr cx16_title_print
cx16_title_ready:
    cli
cx16_idle:
    jsr cx16_poll_menu
    jmp cx16_idle

cx16_title_print:
    lda #$93                // Clear screen.
    jsr KERNAL_CHROUT
    lda #<cx16_title_text
    sta PRINT_PTR
    lda #>cx16_title_text
    sta PRINT_PTR_HI
    jmp cx16_print_z

cx16_poll_menu:
    jsr KERNAL_GETIN
    beq !done+
    cmp #$4e                // N
    beq !new_game+
    cmp #$6e                // n
    beq !new_game+
    cmp #$4c                // L
    beq !load_game+
    cmp #$6c                // l
    beq !load_game+
    cmp #$51                // Q
    beq !quit+
    cmp #$71                // q
    beq !quit+
!done:
    rts
!new_game:
    lda #<cx16_new_game_text
    sta PRINT_PTR
    lda #>cx16_new_game_text
    sta PRINT_PTR_HI
    jmp cx16_print_z
!load_game:
    lda #<cx16_load_game_text
    sta PRINT_PTR
    lda #>cx16_load_game_text
    sta PRINT_PTR_HI
    jmp cx16_print_z
!quit:
    lda #<cx16_quit_text
    sta PRINT_PTR
    lda #>cx16_quit_text
    sta PRINT_PTR_HI
    jmp cx16_print_z

cx16_print_z:
!loop:
    ldy #0
    lda (PRINT_PTR),y
    beq !done+
    jsr KERNAL_CHROUT
    inc PRINT_PTR
    bne !loop-
    inc PRINT_PTR_HI
    jmp !loop-
!done:
    rts

.macro AsciiText(text) {
.for (var i = 0; i < text.size(); i++) {
    .byte text.charAt(i)
}
}

cx16_title_text:
    .byte 13,13
    :AsciiText("                     +------------------------------------+")
    .byte 13
    :AsciiText("                     |              MORIA8                |")
    .byte 13
    :AsciiText("                     |       THE DUNGEONS OF MORIA        |")
    .byte 13
    :AsciiText("                     +------------------------------------+")
    .byte 13,13
    :AsciiText("                     |       COMMANDER X16 EDITION        |")
    .byte 13,13
    :AsciiText("                     |       BOOT-TO-TITLE PORT SLICE     |")
    .byte 13,13
    :AsciiText("                     |       N)EW GAME                    |")
    .byte 13
    :AsciiText("                     |       L)OAD GAME                   |")
    .byte 13
    :AsciiText("                     |       Q)UIT                        |")
    .byte 13
    :AsciiText("                     +------------------------------------+")
    .byte 13,0

cx16_new_game_text:
    .byte 13
    :AsciiText("                     NEW GAME INPUT RECOGNIZED")
    .byte 13,0

cx16_load_game_text:
    .byte 13
    :AsciiText("                     LOAD GAME INPUT RECOGNIZED")
    .byte 13,0

cx16_quit_text:
    .byte 13
    :AsciiText("                     QUIT INPUT RECOGNIZED")
    .byte 13,0
