// main.s - Commander X16 boot-to-title milestone
//
// This is intentionally a narrow platform bring-up slice. Rendering follows
// the existing Commodore platform contract: direct screen-code cell writes
// through a platform-owned screen backend, not KERNAL text streaming.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(cx16_entry)

.pc = $0810 "CX16 Boot"

#import "palette_consts.s"
#import "../../build/version_strings.inc"

.const KERNAL_CINT = $ff81
.const KERNAL_SETNAM = $ffbd
.const KERNAL_SETLFS = $ffba
.const KERNAL_LOAD = $ffd5
.const KERNAL_CLOSE = $ffc3
.const KERNAL_CLRCHN = $ffcc
.const KERNAL_GETIN = $ffe4
.const CX16_STATE_TITLE = 0
.const CX16_STATE_NEW_GAME = 1
.const CX16_STATE_DUNGEON_BOOTSTRAP = 2
.const CX16_TOWN_SCREEN_ROW = 2
.const CX16_TOWN_SCREEN_COL = 7
.const CX16_TITLE_MENU_COL = 27
.const CX16_TEXT_COLOR = $01
.const MAP_BASE = $4000
.const C128 = false
.const PLUS4 = false
.const CX16_IMPORT_SHARED_GAME_LOOP = cmdLineVars.containsKey("CX16_IMPORT_SHARED_GAME_LOOP")

#import "../../core/zeropage.s"
#import "config.s"
#import "memory.s"
#import "../../core/dungeon_data.s"
#import "../../core/player_state.s"
#import "../../core/player_move_basic.s"
#import "../../core/town_map_basic.s"
#import "../../core/tile_display.s"
#import "../../core/town_interactions_basic.s"
#import "screen_vera.s"
#import "input.s"
#import "services.s"
#import "tier_storage.s"
#import "../../core/input_ui_helpers.s"
#if CX16_IMPORT_SHARED_GAME_LOOP
#import "shared_imports.s"
#endif

.label cx16_contract_prg_load_base = CX16_PRG_LOAD_BASE
.label cx16_contract_ram_bank_reg = CX16_RAM_BANK_REG
.label cx16_contract_ram_bank_default = CX16_RAM_BANK_DEFAULT
.label cx16_contract_resident_code_base = CX16_RESIDENT_CODE_BASE
.label cx16_contract_resident_code_limit = CX16_RESIDENT_CODE_LIMIT
.label cx16_contract_fixed_live_map_base = CX16_FIXED_LIVE_MAP_BASE
.label cx16_contract_fixed_live_map_end = CX16_FIXED_LIVE_MAP_END
.label cx16_contract_floor_item_base = FLOOR_ITEM_BASE
.label cx16_contract_floor_item_end = FLOOR_ITEM_END
.label cx16_contract_creature_base = CREATURE_BASE
.label cx16_contract_creature_end = CREATURE_END
.label cx16_contract_bfs_queue_base = DUNGEON_GEN_BFS_QUEUE_BASE
.label cx16_contract_bfs_queue_end = DUNGEON_GEN_BFS_QUEUE_END
.label cx16_contract_banked_ram_base = CX16_BANKED_RAM_BASE
.label cx16_contract_banked_ram_end = CX16_BANKED_RAM_END
.label cx16_contract_banked_data_base = BANKED_DATA_BASE
.label cx16_contract_banked_data_end = BANKED_DATA_END
.label cx16_contract_tier_bank_base = CX16_TIER_BANK_BASE
.label cx16_contract_tier_bank_end = CX16_TIER_BANK_END
.label cx16_contract_tier_load_base = CX16_TIER_LOAD_BASE
.label cx16_contract_tier_load_end = CX16_TIER_LOAD_END

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
    cmp #CX16_STATE_TITLE
    beq !menu+
!game:
    jmp cx16_poll_game
!menu:
    jmp cx16_poll_menu

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
    jsr town_map_basic_generate
    jmp cx16_new_game_draw

cx16_poll_game:
    jsr input_get_command
    jmp cx16_dispatch_game_command

cx16_dispatch_game_command:
    cmp #CMD_QUIT
    bne !not_quit+
    jmp cx16_title_enter_menu
!not_quit:
    cmp #CMD_STAIRS_DN
    bne !not_stairs_dn+
    jmp cx16_try_stairs_down
!not_stairs_dn:
    cmp #CMD_STAIRS_UP
    bne !not_stairs_up+
    jmp cx16_try_stairs_up
!not_stairs_up:
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
    bcs !not_command+
!try_move:
    jmp cx16_try_move_command
!not_command:
    cmp #CMD_REST
    beq !activity+
    cmp #CMD_SEARCH
    beq !activity+
    cmp #CMD_LOOK
    beq !activity+
    cmp #CMD_SEARCH_MODE
    beq !activity+
    cmp #CMD_AUTOREST
    beq !activity+
    cmp #CMD_SAVE
    beq !storage+
    cmp #CMD_CAST
    beq !magic+
    cmp #CMD_PRAY
    beq !magic+
    cmp #CMD_RECALL
    beq !magic+
    cmp #CMD_GAIN
    beq !magic+
    cmp #CMD_CHAR_INFO
    beq !char_info+
    cmp #CMD_MAP
    beq !info+
    cmp #CMD_HELP
    beq !help+
    cmp #CMD_VERSION
    beq !version+
    cmp #CMD_WIZARD
    beq !wizard+
    cmp #CMD_OPEN
    bcc !done+
    cmp #CMD_USE + 1
    bcc !item+
    cmp #CMD_FIRE
    bcc !done+
    cmp #CMD_TUNNEL + 1
    bcc !item+
    cmp #CMD_DISARM
    beq !item+
    jmp !done+
!activity:
    jmp cx16_show_activity_stub
!storage:
    jmp cx16_show_storage_stub
!magic:
    jmp cx16_show_magic_stub
!info:
    jmp cx16_show_info_stub
!help:
    jmp cx16_show_help
!version:
    jmp cx16_show_version
!char_info:
    jmp cx16_show_character_info
!wizard:
    jmp cx16_show_wizard_stub
!item:
    jmp cx16_show_item_stub
!done:
    rts

cx16_try_move_command:
    sec
    sbc #CMD_MOVE_N
    tax
    jsr player_move_compute_town_target
    bcc !done+
    jsr player_move_target_walkable
    bcc !done+
    jsr cx16_save_old_player
    jsr player_move_commit_target
    jsr cx16_sync_local_player_position
    jsr cx16_player_redraw
    jmp cx16_check_town_entry
!done:
    rts

cx16_check_town_entry:
    jsr town_basic_check_store_door
    bcc !done+
    sta cx16_store_idx
    jmp cx16_show_store_stub
!done:
    rts

cx16_try_stairs_down:
    jsr town_basic_check_stairs_at_player
    cmp #9
    beq !descend+
    jmp cx16_show_no_stairs
!descend:
    jmp cx16_enter_dungeon_bootstrap

cx16_try_stairs_up:
    jsr town_basic_check_stairs_at_player
    cmp #10
    beq !ascend+
    jmp cx16_show_no_stairs
!ascend:
    jmp cx16_show_ascend_stub

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

cx16_sync_local_player_position:
    lda zp_player_x
    sta cx16_player_x
    lda zp_player_y
    sta cx16_player_y
    rts

cx16_new_game_draw:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr screen_clear
    :Cx16PrintAt(0, 33, cx16_town_title_text)
    jsr cx16_render_town
    :Cx16PrintAt(26, 14, cx16_game_help_text)
    rts

cx16_show_store_stub:
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 29, cx16_store_door_text)
    lda cx16_store_idx
    clc
    adc #$31
    ldx #40
    ldy #26
    jmp screen_put_char_at

cx16_show_descend_stub:
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 22, cx16_descend_stub_text)
    rts

cx16_enter_dungeon_bootstrap:
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 27, cx16_loading_tier_text)
    lda #1
    jsr cx16_load_tier_to_bank
    bcc !loaded+
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 22, cx16_tier_load_failed_text)
    rts
!loaded:
    lda #CX16_STATE_DUNGEON_BOOTSTRAP
    sta cx16_state
    lda #1
    sta cx16_loaded_tier
    sta cx16_dungeon_depth
    sta player_data + PL_DLEVEL
    sta zp_player_dlvl
    lda #CX16_TIER_BANK_BASE
    sta cx16_loaded_tier_bank
    jmp cx16_draw_dungeon_bootstrap

cx16_draw_dungeon_bootstrap:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr screen_clear
    :Cx16PrintAt(0, 31, cx16_dungeon_title_text)
    :Cx16PrintAt(4, 24, cx16_dungeon_loaded_text)
    :Cx16PrintAt(6, 24, cx16_dungeon_tier_bank_text)
    :Cx16PrintAt(8, 17, cx16_dungeon_runtime_text)
    :Cx16PrintAt(26, 13, cx16_dungeon_help_text)
    rts

cx16_show_ascend_stub:
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 22, cx16_ascend_stub_text)
    rts

cx16_show_no_stairs:
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 28, cx16_no_stairs_text)
    rts

cx16_show_help:
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 8, cx16_command_help_text)
    rts

cx16_show_version:
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 24, cx16_version_text)
    rts

cx16_show_character_info:
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 19, cx16_character_info_text)
    rts

cx16_show_activity_stub:
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 23, cx16_activity_stub_text)
    rts

cx16_show_item_stub:
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 23, cx16_item_stub_text)
    rts

cx16_show_magic_stub:
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 25, cx16_magic_stub_text)
    rts

cx16_show_storage_stub:
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 24, cx16_storage_stub_text)
    rts

cx16_show_info_stub:
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 24, cx16_info_stub_text)
    rts

cx16_show_wizard_stub:
    jsr cx16_clear_message_row
    :Cx16PrintAt(26, 26, cx16_wizard_stub_text)
    rts

cx16_clear_message_row:
    lda #26
    jsr screen_clear_row
    lda #CX16_TEXT_COLOR
    jmp screen_set_color

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
    lda #SC_PLAYER
    ldx #COL_PLAYER
    bne !put+
!floor:
    jsr cx16_read_draw_tile
    jsr tile_map_byte_to_char_color
    jsr cx16_apply_store_door_display
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
    lda #COL_PLAYER
    jsr screen_set_color
    lda #SC_PLAYER
    jsr screen_put_char_at
    lda #CX16_TEXT_COLOR
    jmp screen_set_color

cx16_draw_map_cell:
    jsr cx16_read_draw_tile
    jsr tile_map_byte_to_char_color
    jsr cx16_apply_store_door_display
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

cx16_apply_store_door_display:
    stx cx16_draw_color
    sta cx16_draw_char
    lda cx16_draw_x
    sta zp_temp3
    lda cx16_draw_y
    sta zp_temp4
    jsr town_basic_check_xy_store_door
    bcc !not_store+
    clc
    adc #SC_STORE_1
    ldx #COL_STORE
    rts
!not_store:
    lda cx16_draw_char
    ldx cx16_draw_color
    rts

cx16_read_draw_tile:
    ldy cx16_draw_y
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy cx16_draw_x
    lda (zp_ptr0),y
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
    lda #<MAP_BASE
    sta cx16_asset_load_addr_lo
    lda #>MAP_BASE
    sta cx16_asset_load_addr_hi
    lda #cx16_title_name_len
    ldx #<cx16_title_name
    ldy #>cx16_title_name
    jmp hal_asset_load_prg_header

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

cx16_store_door_text:
    :ScreenText("STORE DOOR ")
    .byte 0

cx16_descend_stub_text:
    :ScreenText("DUNGEON ENTRY NOT WIRED YET.")
    .byte 0

cx16_loading_tier_text:
    :ScreenText("LOADING TIER 1...")
    .byte 0

cx16_tier_load_failed_text:
    :ScreenText("TIER LOAD FAILED.")
    .byte 0

cx16_dungeon_title_text:
    :ScreenText("DUNGEON LEVEL 1")
    .byte 0

cx16_dungeon_loaded_text:
    :ScreenText("MONSTER.DB.1 LOADED")
    .byte 0

cx16_dungeon_tier_bank_text:
    :ScreenText("TIER 1 RESIDENT IN RAM BANK 4")
    .byte 0

cx16_dungeon_runtime_text:
    :ScreenText("DUNGEON GENERATION AND RENDERING ARE NEXT.")
    .byte 0

cx16_dungeon_help_text:
    :ScreenText("SHIFT-Q RETURNS TO TITLE. FULL DUNGEON LOOP NOT WIRED YET.")
    .byte 0

cx16_ascend_stub_text:
    :ScreenText("YOU ARE ALREADY IN TOWN.")
    .byte 0

cx16_no_stairs_text:
    :ScreenText("YOU SEE NO STAIRS HERE.")
    .byte 0

cx16_command_help_text:
    :ScreenText("MOVE HJKL/YUBN/12346789. > STAIRS. SHIFT-Q TITLE.")
    .byte 0

cx16_version_text:
    :ScreenText("MORIA8 CX16 BOOTSTRAP ")
    :EmitTitleVersionScreen()
    .byte 0

cx16_character_info_text:
    :ScreenText("CHARACTER INFO: TOWN BOOTSTRAP, DEPTH 0.")
    .byte 0

cx16_activity_stub_text:
    :ScreenText("SEARCH/REST/LOOK NOT WIRED YET.")
    .byte 0

cx16_item_stub_text:
    :ScreenText("ITEM/FEATURE COMMAND NOT WIRED YET.")
    .byte 0

cx16_magic_stub_text:
    :ScreenText("MAGIC/RECALL NOT WIRED YET.")
    .byte 0

cx16_storage_stub_text:
    :ScreenText("SAVE/LOAD NOT WIRED YET.")
    .byte 0

cx16_info_stub_text:
    :ScreenText("INFO/HELP NOT WIRED YET.")
    .byte 0

cx16_wizard_stub_text:
    :ScreenText("WIZARD MODE NOT ENABLED.")
    .byte 0

cx16_memory_fail_text:
    :ScreenText("CX16 RAM BANK TEST FAILED")
    .byte 0

cx16_state: .byte CX16_STATE_TITLE
cx16_player_x: .byte 0
cx16_player_y: .byte 0
cx16_old_player_x: .byte 0
cx16_old_player_y: .byte 0
cx16_draw_x: .byte 0
cx16_draw_y: .byte 0
cx16_draw_char: .byte 0
cx16_draw_color: .byte 0
cx16_store_idx: .byte 0
cx16_loaded_tier: .byte 0
cx16_loaded_tier_bank: .byte 0
cx16_dungeon_depth: .byte 0

program_end:
#if !CX16_IMPORT_SHARED_GAME_LOOP
.assert "CX16 product image stays below fixed live-map base", program_end <= CX16_RESIDENT_CODE_LIMIT, true
#else
.assert "CX16 shared-gameplay probe crosses fixed live-map base; keep link-only", program_end > CX16_FIXED_LIVE_MAP_BASE, true
.assert "CX16 shared-gameplay probe crosses VERA I/O hole; keep link-only", program_end > CX16_IO_BASE, true
#endif
.assert "CX16 town uses shared town width", TOWN_MAP_COLS, 66
.assert "CX16 town uses shared town height", TOWN_MAP_ROWS, 22
.assert "CX16 town row stride matches fixed live map", MAP_COLS, 198
.assert "CX16 shared town start x", TOWN_START_X, 31
.assert "CX16 shared town start y", TOWN_START_Y, 18
