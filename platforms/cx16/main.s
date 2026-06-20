// main.s - Commander X16 boot-to-title milestone
//
// This is intentionally a narrow platform bring-up slice. Rendering follows
// the existing Commodore platform contract: direct screen-code cell writes
// through a platform-owned screen backend, not KERNAL text streaming.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(cx16_entry)

.pc = $0810 "CX16 Boot"

.const KERNAL_CINT = $ff81
.const KERNAL_GETIN = $ffe4
.const CX16_STATE_TITLE = 0
.const CX16_STATE_NEW_GAME = 1
.const CX16_PLAYFIELD_W = 20
.const CX16_PLAYFIELD_H = 10
.const CX16_PLAYFIELD_ROW = 7
.const CX16_PLAYFIELD_COL = 30
.const CX16_TEXT_COLOR = $61
.const CX16_TITLE_ACCENT_COLOR = $67
.const MAP_BASE = $4000
.const COL_WHITE = CX16_TEXT_COLOR
.const SC_AT = $00
.const SC_DOT = $2e
.const C128 = false
.const PLUS4 = false

#import "screen_vera.s"

cx16_entry:
    sei
    lda #0
    sta $01                 // Select KERNAL ROM bank before X16 KERNAL calls.
    jsr KERNAL_CINT
    jsr screen_init
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr cx16_title_print
    cli
cx16_idle:
    jsr cx16_poll_input
    jmp cx16_idle

cx16_title_print:
    lda #CX16_STATE_TITLE
    sta cx16_state
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr title_load_and_draw
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    :Cx16PrintAt(14, 21, cx16_title_new_text)
    :Cx16PrintAt(15, 21, cx16_title_load_text)
    :Cx16PrintAt(16, 21, cx16_title_quit_text)
    rts

cx16_poll_input:
    lda cx16_state
    cmp #CX16_STATE_NEW_GAME
    beq !game+
    jmp cx16_poll_menu
!game:
    jmp cx16_poll_game

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
    jmp cx16_new_game_start
!load_game:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    :Cx16PrintAt(20, 21, cx16_load_game_text)
    rts
!quit:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    :Cx16PrintAt(20, 21, cx16_quit_text)
    rts

cx16_new_game_start:
    lda #CX16_STATE_NEW_GAME
    sta cx16_state
    lda #CX16_PLAYFIELD_W / 2
    sta cx16_player_x
    lda #CX16_PLAYFIELD_H / 2
    sta cx16_player_y
    jmp cx16_new_game_draw

cx16_poll_game:
    jsr KERNAL_GETIN
    beq !done+
    cmp #$51                // Q
    beq !return_title+
    cmp #$71                // q
    beq !return_title+
    cmp #$57                // W
    beq !move_up+
    cmp #$77                // w
    beq !move_up+
    cmp #$4b                // K
    beq !move_up+
    cmp #$6b                // k
    beq !move_up+
    cmp #$53                // S
    beq !move_down+
    cmp #$73                // s
    beq !move_down+
    cmp #$4a                // J
    beq !move_down+
    cmp #$6a                // j
    beq !move_down+
    cmp #$41                // A
    beq !move_left+
    cmp #$61                // a
    beq !move_left+
    cmp #$48                // H
    beq !move_left+
    cmp #$68                // h
    beq !move_left+
    cmp #$44                // D
    beq !move_right+
    cmp #$64                // d
    beq !move_right+
    cmp #$4c                // L
    beq !move_right+
    cmp #$6c                // l
    beq !move_right+
!done:
    rts
!return_title:
    jmp cx16_title_print
!move_up:
    lda cx16_player_y
    beq !done-
    jsr cx16_save_old_player
    dec cx16_player_y
    jmp cx16_player_redraw
!move_down:
    lda cx16_player_y
    cmp #CX16_PLAYFIELD_H - 1
    beq !done-
    jsr cx16_save_old_player
    inc cx16_player_y
    jmp cx16_player_redraw
!move_left:
    lda cx16_player_x
    beq !done-
    jsr cx16_save_old_player
    dec cx16_player_x
    jmp cx16_player_redraw
!move_right:
    lda cx16_player_x
    cmp #CX16_PLAYFIELD_W - 1
    beq !done-
    jsr cx16_save_old_player
    inc cx16_player_x
    jmp cx16_player_redraw

cx16_new_game_draw:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr screen_clear
    :Cx16PrintAt(2, 31, cx16_new_game_text)
    :Cx16PrintAt(4, 30, cx16_town_stub_text)
    lda #0
    sta cx16_draw_y
!row:
    clc
    lda cx16_draw_y
    adc #CX16_PLAYFIELD_ROW
    sta zp_cursor_row
    lda #CX16_PLAYFIELD_COL
    sta zp_cursor_col
    lda #0
    sta cx16_draw_x
!col:
    lda cx16_draw_x
    cmp cx16_player_x
    bne !floor+
    lda cx16_draw_y
    cmp cx16_player_y
    bne !floor+
    lda #SC_AT
    bne !put+
!floor:
    lda #SC_DOT
!put:
    jsr screen_put_char
    inc cx16_draw_x
    lda cx16_draw_x
    cmp #CX16_PLAYFIELD_W
    bcc !col-
    inc cx16_draw_y
    lda cx16_draw_y
    cmp #CX16_PLAYFIELD_H
    bcc !row-
    :Cx16PrintAt(19, 15, cx16_game_help_text)
    rts

cx16_save_old_player:
    lda cx16_player_x
    sta cx16_old_player_x
    lda cx16_player_y
    sta cx16_old_player_y
    rts

cx16_player_redraw:
    clc
    lda cx16_old_player_y
    adc #CX16_PLAYFIELD_ROW
    tay
    clc
    lda cx16_old_player_x
    adc #CX16_PLAYFIELD_COL
    tax
    lda #SC_DOT
    jsr screen_put_char_at
    clc
    lda cx16_player_y
    adc #CX16_PLAYFIELD_ROW
    tay
    clc
    lda cx16_player_x
    adc #CX16_PLAYFIELD_COL
    tax
    lda #SC_AT
    jmp screen_put_char_at

.macro Cx16PrintAt(row, col, text) {
    lda #row
    sta zp_cursor_row
    lda #col
    sta zp_cursor_col
    lda #<text
    sta zp_ptr0
    lda #>text
    sta zp_ptr0_hi
    jsr screen_put_string
}

.macro ScreenText(text) {
.for (var i = 0; i < text.size(); i++) {
    .var c = text.charAt(i)
    .if (c >= 65 && c <= 90) {
        .byte c - 64
    } else {
        .byte c
    }
}
}

// CX16 title asset shim. The shared title renderer consumes a MAP_BASE segment
// stream, while real CX16 disk/storage loading is a later port slice.
hal_asset_load_title:
    lda #<cx16_title_art_stream
    sta zp_ptr0
    lda #>cx16_title_art_stream
    sta zp_ptr0_hi
    lda #<MAP_BASE
    sta zp_ptr1
    lda #>MAP_BASE
    sta zp_ptr1_hi
    ldy #0
!copy:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    cmp #$ff
    beq !done+
    iny
    bne !copy-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    jmp !copy-
!done:
    clc
    rts

#import "../commodore/common/title_screen.s"

title_str:
    :ScreenText("MORIA8")
    .byte 0

cx16_title_art_stream:
    .byte 2, 0, CX16_TEXT_COLOR
    :ScreenText("+------------------------------------+")
    .byte 0
    .byte 3, 0, CX16_TITLE_ACCENT_COLOR
    :ScreenText("               MORIA8                ")
    .byte 0
    .byte 4, 0, CX16_TITLE_ACCENT_COLOR
    :ScreenText("        THE DUNGEONS OF MORIA        ")
    .byte 0
    .byte 5, 0, CX16_TEXT_COLOR
    :ScreenText("+------------------------------------+")
    .byte 0
    .byte 8, 0, CX16_TEXT_COLOR
    :ScreenText("        COMMANDER X16 EDITION        ")
    .byte 0
    .byte 11, 0, CX16_TEXT_COLOR
    :ScreenText("       SHARED TITLE RENDERER         ")
    .byte 0
    .byte $ff

cx16_title_new_text:
    :ScreenText("        N)EW GAME                    ")
    .byte 0

cx16_title_load_text:
    :ScreenText("        L)OAD GAME                   ")
    .byte 0

cx16_title_quit_text:
    :ScreenText("        Q)UIT                        ")
    .byte 0

cx16_new_game_text:
    :ScreenText("NEW GAME STUB")
    .byte 0

cx16_town_stub_text:
    :ScreenText("TOWN PLACEHOLDER")
    .byte 0

cx16_load_game_text:
    :ScreenText("LOAD GAME INPUT RECOGNIZED")
    .byte 0

cx16_quit_text:
    :ScreenText("QUIT INPUT RECOGNIZED")
    .byte 0

cx16_game_help_text:
    :ScreenText("WASD OR HJKL MOVES. Q RETURNS TO TITLE.")
    .byte 0

cx16_state: .byte CX16_STATE_TITLE
cx16_player_x: .byte 0
cx16_player_y: .byte 0
cx16_old_player_x: .byte 0
cx16_old_player_y: .byte 0
cx16_draw_x: .byte 0
cx16_draw_y: .byte 0
