// main.s - Commander X16 boot-to-title milestone
//
// This is intentionally a narrow platform bring-up slice. Rendering follows
// the existing Commodore platform contract: direct screen-code cell writes
// through a platform-owned screen backend, not KERNAL text streaming.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(cx16_entry)

.pc = $0810 "CX16 Boot"

#import "palette_consts.s"

.const KERNAL_CINT = $ff81
.const KERNAL_SETNAM = $ffbd
.const KERNAL_SETLFS = $ffba
.const KERNAL_LOAD = $ffd5
.const KERNAL_CLOSE = $ffc3
.const KERNAL_CLRCHN = $ffcc
.const KERNAL_GETIN = $ffe4
.const CX16_STATE_TITLE = 0
.const CX16_STATE_NEW_GAME = 1
.const CX16_TOWN_SCREEN_ROW = 2
.const CX16_TOWN_SCREEN_COL = 7
.const CX16_STORE_W = 10
.const CX16_STORE_H = 5
.const CX16_TITLE_MENU_COL = 27
.const CX16_TEXT_COLOR = $01
.const CX16_TOWN_FLOOR_COLOR = COL_DGREY
.const CX16_TOWN_WALL_COLOR = COL_LGREY
.const CX16_TOWN_DOOR_COLOR = COL_BROWN
.const CX16_TOWN_STAIRS_COLOR = COL_WHITE
.const CX16_TOWN_PLAYER_COLOR = COL_WHITE
.const MAP_BASE = $4000
.const SC_AT = $00
.const SC_DOT = $2e
.const SC_WALL = $23
.const SC_DOOR = $27
.const SC_STAIRS_DN = $3e
.const C128 = false
.const PLUS4 = false
.const CX16_IMPORT_SHARED_GAME_LOOP = cmdLineVars.containsKey("CX16_IMPORT_SHARED_GAME_LOOP")

#import "../../core/zeropage.s"
#import "config.s"
#import "memory.s"
#import "../../core/dungeon_data.s"
#import "../../core/player_state.s"
#import "../../core/tile_walkability.s"
#import "screen_vera.s"
#import "input.s"
#import "services.s"
#import "../../core/input_ui_helpers.s"
#if CX16_IMPORT_SHARED_GAME_LOOP
#import "shared_imports.s"
#endif

cx16_entry:
    sei
    jsr cx16_memory_init    // Select KERNAL ROM and default RAM bank.
    bcc !memory_ok+
    jsr KERNAL_CINT
    jsr screen_init
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    :Cx16PrintAt(14, 30, cx16_memory_fail_text)
!halt:
    jmp !halt-
!memory_ok:
    jsr KERNAL_CINT
    jsr screen_init
    jsr cx16_services_install
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr cx16_title_enter_menu
    cli
cx16_idle:
    jsr cx16_poll_input
    jmp cx16_idle

cx16_title_enter_menu:
    lda #CX16_STATE_TITLE
    sta cx16_state
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr title_load_and_draw
    jsr title_clear_below_menu
    jmp cx16_title_draw_menu

cx16_title_draw_menu:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    lda #18
    sta zp_cursor_row
    lda #CX16_TITLE_MENU_COL
    sta zp_cursor_col
    lda #<cx16_title_menu_text
    sta zp_ptr0
    lda #>cx16_title_menu_text
    sta zp_ptr0_hi
    jmp screen_put_string

cx16_poll_input:
    lda cx16_state
    cmp #CX16_STATE_NEW_GAME
    beq !game+
    jmp cx16_poll_menu
!game:
    jmp cx16_poll_game

cx16_poll_menu:
    jsr input_get_key
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
    jsr input_get_modal_dismiss_key
    jmp cx16_title_enter_menu
!quit:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    :Cx16PrintAt(20, 21, cx16_quit_text)
    jsr input_get_modal_dismiss_key
    jmp cx16_title_enter_menu

cx16_new_game_start:
    lda #CX16_STATE_NEW_GAME
    sta cx16_state
    lda #TOWN_START_X
    sta cx16_player_x
    lda #TOWN_START_Y
    sta cx16_player_y
    jsr cx16_seed_shared_town_player
    jsr cx16_generate_town
    jmp cx16_new_game_draw

cx16_poll_game:
    jsr input_get_command
    cmp #CMD_QUIT
    beq !return_title+
    cmp #CMD_RUN_N
    bcc !not_run+
    cmp #CMD_RUN_SE + 1
    bcs !not_run+
    sec
    sbc #(CMD_RUN_N - CMD_MOVE_N)
    jmp !try_move+
!not_run:
    cmp #CMD_MOVE_N
    bcc !done+
    cmp #CMD_MOVE_SE + 1
    bcs !done+
!try_move:
    jmp cx16_try_move_command
!done:
    rts
!return_title:
    jmp cx16_title_enter_menu

cx16_try_move_command:
    sec
    sbc #CMD_MOVE_N
    tax
    lda cx16_player_x
    clc
    adc dir_dx,x
    cmp #TOWN_MAP_COLS
    bcs !done+
    sta cx16_next_player_x
    lda cx16_player_y
    clc
    adc dir_dy,x
    cmp #TOWN_MAP_ROWS
    bcs !done+
    sta cx16_next_player_y
    jsr cx16_next_tile_walkable
    bcc !done+
    jsr cx16_save_old_player
    lda cx16_next_player_x
    sta cx16_player_x
    lda cx16_next_player_y
    sta cx16_player_y
    jsr cx16_sync_shared_player_position
    jmp cx16_player_redraw
!done:
    rts

cx16_seed_shared_town_player:
    lda #0
    sta player_data + PL_DLEVEL
    sta zp_player_dlvl
    lda #TOWN_START_X
    sta cx16_player_x
    lda #TOWN_START_Y
    sta cx16_player_y
    jmp cx16_sync_shared_player_position

cx16_sync_shared_player_position:
    lda cx16_player_x
    sta player_data + PL_MAP_X
    sta zp_player_x
    lda cx16_player_y
    sta player_data + PL_MAP_Y
    sta zp_player_y
    rts

cx16_new_game_draw:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr screen_clear
    :Cx16PrintAt(0, 33, cx16_town_title_text)
    jsr cx16_render_town
    :Cx16PrintAt(26, 14, cx16_game_help_text)
    rts

cx16_render_town:
    lda #0
    sta cx16_draw_y
!row:
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
    ldx #CX16_TOWN_PLAYER_COLOR
    bne !put+
!floor:
    jsr cx16_read_draw_tile
    jsr cx16_town_tile_to_char_color
!put:
    sta cx16_draw_char
    stx cx16_draw_color
    txa
    jsr screen_set_color
    clc
    ldy cx16_draw_y
    tya
    adc #CX16_TOWN_SCREEN_ROW
    tay
    clc
    ldx cx16_draw_x
    txa
    adc #CX16_TOWN_SCREEN_COL
    tax
    lda cx16_draw_char
    jsr screen_put_char_at
    inc cx16_draw_x
    lda cx16_draw_x
    cmp #TOWN_MAP_COLS
    bcc !col-
    inc cx16_draw_y
    lda cx16_draw_y
    cmp #TOWN_MAP_ROWS
    bcc !row-
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    rts

cx16_save_old_player:
    lda cx16_player_x
    sta cx16_old_player_x
    lda cx16_player_y
    sta cx16_old_player_y
    rts

cx16_player_redraw:
    lda cx16_old_player_x
    sta cx16_draw_x
    lda cx16_old_player_y
    sta cx16_draw_y
    jsr cx16_draw_map_cell
    clc
    lda cx16_player_y
    adc #CX16_TOWN_SCREEN_ROW
    tay
    clc
    lda cx16_player_x
    adc #CX16_TOWN_SCREEN_COL
    tax
    lda #CX16_TOWN_PLAYER_COLOR
    jsr screen_set_color
    lda #SC_AT
    jsr screen_put_char_at
    lda #CX16_TEXT_COLOR
    jmp screen_set_color

cx16_draw_map_cell:
    jsr cx16_read_draw_tile
    jsr cx16_town_tile_to_char_color
    sta cx16_draw_char
    stx cx16_draw_color
    txa
    jsr screen_set_color
    clc
    ldy cx16_draw_y
    tya
    adc #CX16_TOWN_SCREEN_ROW
    tay
    clc
    ldx cx16_draw_x
    txa
    adc #CX16_TOWN_SCREEN_COL
    tax
    lda cx16_draw_char
    jsr screen_put_char_at
    lda #CX16_TEXT_COLOR
    jmp screen_set_color

cx16_next_tile_walkable:
    lda cx16_next_player_y
    tay
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy cx16_next_player_x
    lda (zp_ptr0),y
    and #$f0
    lsr
    lsr
    lsr
    lsr
    jmp tile_is_walkable

cx16_read_draw_tile:
    ldy cx16_draw_y
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy cx16_draw_x
    lda (zp_ptr0),y
    rts

cx16_town_tile_to_char_color:
    and #$f0
    cmp #TILE_FLOOR
    beq !floor+
    cmp #TILE_DOOR_OPEN
    beq !door+
    cmp #TILE_STAIRS_DN
    beq !stairs+
    lda #SC_WALL
    ldx #CX16_TOWN_WALL_COLOR
    rts
!floor:
    lda #SC_DOT
    ldx #CX16_TOWN_FLOOR_COLOR
    rts
!door:
    lda #SC_DOOR
    ldx #CX16_TOWN_DOOR_COLOR
    rts
!stairs:
    lda #SC_STAIRS_DN
    ldx #CX16_TOWN_STAIRS_COLOR
    rts

cx16_generate_town:
    lda #0
    sta cx16_draw_y
!floor_row:
    ldy cx16_draw_y
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy #0
    lda #TILE_FLOOR | TOWN_FLAGS
!floor_col:
    sta (zp_ptr0),y
    iny
    cpy #TOWN_MAP_COLS
    bne !floor_col-
    inc cx16_draw_y
    lda cx16_draw_y
    cmp #TOWN_MAP_ROWS
    bcc !floor_row-

    ldx #0
    ldy #0
    lda #TILE_CORNER_TL | TOWN_FLAGS
    jsr cx16_write_town_tile
    ldx #TOWN_MAP_COLS - 1
    ldy #0
    lda #TILE_CORNER_TR | TOWN_FLAGS
    jsr cx16_write_town_tile
    ldx #0
    ldy #TOWN_MAP_ROWS - 1
    lda #TILE_CORNER_BL | TOWN_FLAGS
    jsr cx16_write_town_tile
    ldx #TOWN_MAP_COLS - 1
    ldy #TOWN_MAP_ROWS - 1
    lda #TILE_CORNER_BR | TOWN_FLAGS
    jsr cx16_write_town_tile

    ldx #1
!top_bottom:
    txa
    pha
    ldy #0
    lda #TILE_WALL_H | TOWN_FLAGS
    jsr cx16_write_town_tile
    pla
    tax
    txa
    pha
    ldy #TOWN_MAP_ROWS - 1
    lda #TILE_WALL_H | TOWN_FLAGS
    jsr cx16_write_town_tile
    pla
    tax
    inx
    cpx #TOWN_MAP_COLS - 1
    bne !top_bottom-

    ldy #1
!left_right:
    tya
    pha
    ldx #0
    lda #TILE_WALL_V | TOWN_FLAGS
    jsr cx16_write_town_tile
    pla
    tay
    tya
    pha
    ldx #TOWN_MAP_COLS - 1
    lda #TILE_WALL_V | TOWN_FLAGS
    jsr cx16_write_town_tile
    pla
    tay
    iny
    cpy #TOWN_MAP_ROWS - 1
    bne !left_right-

    ldx #0
!store:
    stx cx16_store_idx
    jsr cx16_draw_store
    ldx cx16_store_idx
    inx
    cpx #8
    bne !store-

    ldx #TOWN_STAIRS_X
    ldy #TOWN_STAIRS_Y
    lda #TILE_STAIRS_DN | TOWN_FLAGS
    jmp cx16_write_town_tile

cx16_draw_store:
    ldx cx16_store_idx
    lda store_pos_x,x
    sta cx16_store_left
    clc
    adc #CX16_STORE_W - 1
    sta cx16_store_right
    lda store_pos_y,x
    sta cx16_store_top
    clc
    adc #CX16_STORE_H - 1
    sta cx16_store_bottom

    ldx cx16_store_left
    ldy cx16_store_top
    lda #TILE_CORNER_TL | TOWN_FLAGS
    jsr cx16_write_town_tile
    ldx cx16_store_right
    ldy cx16_store_top
    lda #TILE_CORNER_TR | TOWN_FLAGS
    jsr cx16_write_town_tile
    ldx cx16_store_left
    ldy cx16_store_bottom
    lda #TILE_CORNER_BL | TOWN_FLAGS
    jsr cx16_write_town_tile
    ldx cx16_store_right
    ldy cx16_store_bottom
    lda #TILE_CORNER_BR | TOWN_FLAGS
    jsr cx16_write_town_tile

    lda cx16_store_left
    clc
    adc #1
    sta cx16_draw_x
!store_h:
    ldx cx16_draw_x
    ldy cx16_store_top
    lda #TILE_WALL_H | TOWN_FLAGS
    jsr cx16_write_town_tile
    ldx cx16_draw_x
    ldy cx16_store_bottom
    lda #TILE_WALL_H | TOWN_FLAGS
    jsr cx16_write_town_tile
    inc cx16_draw_x
    lda cx16_draw_x
    cmp cx16_store_right
    bne !store_h-

    lda cx16_store_top
    clc
    adc #1
    sta cx16_draw_y
!store_v:
    ldx cx16_store_left
    ldy cx16_draw_y
    lda #TILE_WALL_V | TOWN_FLAGS
    jsr cx16_write_town_tile
    ldx cx16_store_right
    ldy cx16_draw_y
    lda #TILE_WALL_V | TOWN_FLAGS
    jsr cx16_write_town_tile
    inc cx16_draw_y
    lda cx16_draw_y
    cmp cx16_store_bottom
    bne !store_v-

    lda cx16_store_top
    clc
    adc #1
    sta cx16_draw_y
!store_fill_y:
    lda cx16_store_left
    clc
    adc #1
    sta cx16_draw_x
!store_fill_x:
    ldx cx16_draw_x
    ldy cx16_draw_y
    lda #TILE_WALL_H
    jsr cx16_write_town_tile
    inc cx16_draw_x
    lda cx16_draw_x
    cmp cx16_store_right
    bne !store_fill_x-
    inc cx16_draw_y
    lda cx16_draw_y
    cmp cx16_store_bottom
    bne !store_fill_y-

    ldx cx16_store_idx
    lda store_door_x,x
    tax
    ldy cx16_store_idx
    lda store_door_y,y
    tay
    lda #TILE_DOOR_OPEN | TOWN_FLAGS
    jmp cx16_write_town_tile

cx16_write_town_tile:
    sta cx16_tile_value
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    txa
    tay
    lda cx16_tile_value
    sta (zp_ptr0),y
    rts

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

// CX16 title asset loader. The Makefile builds TITLE from core/title_data.s
// beside moria16.prg, and runcx16 launches from that directory.
hal_asset_load_title:
    lda #cx16_title_name_len
    ldx #<cx16_title_name
    ldy #>cx16_title_name
    jsr KERNAL_SETNAM
    lda #2
    ldx #8
    ldy #0
    jsr KERNAL_SETLFS
    lda #0
    lda #<MAP_BASE
    tax
    lda #>MAP_BASE
    tay
    lda #0
    jsr KERNAL_LOAD
    php
    lda #2
    jsr KERNAL_CLOSE
    jsr KERNAL_CLRCHN
    plp
    rts

#import "../commodore/common/title_screen.s"

title_str:
    :ScreenText("MORIA8")
    .byte 0

cx16_title_name:
    .byte $54, $49, $54, $4c, $45 // "TITLE"
.label cx16_title_name_len = * - cx16_title_name

cx16_title_menu_text:
    :ScreenText("N)EW  L)OAD  Q)UIT")
    .byte 0

cx16_town_title_text:
    :ScreenText("TOWN")
    .byte 0

cx16_load_game_text:
    :ScreenText("LOAD GAME INPUT RECOGNIZED")
    .byte 0

cx16_quit_text:
    :ScreenText("QUIT INPUT RECOGNIZED")
    .byte 0

cx16_game_help_text:
    :ScreenText("HJKL/YUBN OR NUMBERS MOVE. SHIFT-Q RETURNS TO TITLE.")
    .byte 0

cx16_memory_fail_text:
    :ScreenText("CX16 RAM BANK TEST FAILED")
    .byte 0

cx16_state: .byte CX16_STATE_TITLE
cx16_player_x: .byte 0
cx16_player_y: .byte 0
cx16_old_player_x: .byte 0
cx16_old_player_y: .byte 0
cx16_next_player_x: .byte 0
cx16_next_player_y: .byte 0
cx16_draw_x: .byte 0
cx16_draw_y: .byte 0
cx16_draw_char: .byte 0
cx16_draw_color: .byte 0
cx16_tile_value: .byte 0
cx16_store_idx: .byte 0
cx16_store_left: .byte 0
cx16_store_right: .byte 0
cx16_store_top: .byte 0
cx16_store_bottom: .byte 0

program_end:
#if !CX16_IMPORT_SHARED_GAME_LOOP
.assert "CX16 resident boot code stays below MAP_BASE", program_end <= MAP_BASE, true
#endif
.assert "CX16 town uses shared town width", TOWN_MAP_COLS, 66
.assert "CX16 town uses shared town height", TOWN_MAP_ROWS, 22
.assert "CX16 town row stride matches fixed live map", MAP_COLS, 198
.assert "CX16 shared town start x", TOWN_START_X, 31
.assert "CX16 shared town start y", TOWN_START_Y, 18
