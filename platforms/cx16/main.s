// main.s - Commander X16 boot-to-title milestone
//
// This is intentionally a narrow platform bring-up slice. Rendering follows
// the existing Commodore platform contract: direct screen-code cell writes
// through a platform-owned screen backend, not KERNAL text streaming.

.eval var CX16_OUT = "../../build/cx16"
.if (cmdLineVars.containsKey("CX16_OUT")) {
    .eval CX16_OUT = cmdLineVars.get("CX16_OUT")
}
.segmentdef Cx16DungeonGenModule [outPrg=CX16_OUT + "/DUNGEON.GEN", start=$a000, min=$a000, max=$bfff]
.segmentdef Cx16StartupOverlay   [outPrg=CX16_OUT + "/X16.START",  start=$a000, min=$a000, max=$bfff]
.segmentdef Cx16TownOverlay      [outPrg=CX16_OUT + "/X16.TOWN",   start=$a000, min=$a000, max=$bfff]
.segmentdef Cx16DeathOverlay     [outPrg=CX16_OUT + "/X16.DEATH",  start=$a000, min=$a000, max=$bfff]
.segmentdef Cx16RoyalOverlay     [outPrg=CX16_OUT + "/X16.ROYAL",  start=$a000, min=$a000, max=$bfff]
.segmentdef Cx16GenOverlay       [outPrg=CX16_OUT + "/X16.GEN",    start=$a000, min=$a000, max=$bfff]
.segmentdef Cx16HelpOverlay      [outPrg=CX16_OUT + "/X16.HELP",   start=$a000, min=$a000, max=$bfff]
.segmentdef Cx16UiOverlay        [outPrg=CX16_OUT + "/X16.UI",     start=$a000, min=$a000, max=$bfff]
.segmentdef Cx16ItemsOverlay     [outPrg=CX16_OUT + "/X16.ITEMS",  start=$a000, min=$a000, max=$bfff]
.segmentdef Cx16SpellOverlay     [outPrg=CX16_OUT + "/X16.SPELL",  start=$a000, min=$a000, max=$bfff]
.segmentdef Cx16DisarmOverlay    [outPrg=CX16_OUT + "/X16.DISARM", start=$a000, min=$a000, max=$bfff]

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
.const CX16_BOOTSTRAP_LIGHT_RADIUS = 1
.const CX16_FEATURE_CMD_OPEN = 0
.const CX16_FEATURE_CMD_CLOSE = 1
.const CX16_FEATURE_CMD_SEARCH = 2
.const CX16_FEATURE_CMD_REST = 3
.const CX16_FEATURE_CMD_SEARCH_MODE = 4
.const CX16_FEATURE_CMD_BASH = 5
.const CX16_FEATURE_CMD_TUNNEL = 6
.const CX16_FEATURE_CMD_DISARM = 7
.const CX16_ITEM_CMD_PICKUP = 0
.const CX16_ITEM_CMD_DROP = 1
.const CX16_ITEM_CMD_INVENTORY = 2
.const CX16_ITEM_CMD_EQUIPMENT = 3
.const CX16_ITEM_CMD_WEAR = 4
.const CX16_ITEM_CMD_TAKEOFF = 5
.const CX16_ITEM_CMD_EAT = 6
.const CX16_ITEM_CMD_QUAFF = 7
.const CX16_ITEM_CMD_REFUEL = 8
.const CX16_ITEM_CMD_READ = 9
.const CX16_ITEM_CMD_AIM = 10
.const CX16_ITEM_CMD_USE = 11
.const MAP_BASE = $6800
.const C128 = false
.const PLUS4 = false
.const C128_REAL_BOOT_DIAG = 0
.const hal_memory_map_row_helper_enabled = 0
.const CX16_IMPORT_SHARED_GAME_LOOP = cmdLineVars.containsKey("CX16_IMPORT_SHARED_GAME_LOOP")
#if CX16_IMPORT_SHARED_GAME_LOOP
.const DUNGEON_GEN_BUSY = 1
#else
.const DUNGEON_GEN_BUSY = 0
#endif

#import "hal/entropy_consts.s"
#import "../../core/zeropage.s"
#import "config.s"
#import "memory.s"
#define PLATFORM_ACTIVE_MONSTER_TABLE_ABSOLUTE
.const PLATFORM_ACTIVE_MONSTER_TABLE_BASE = CREATURE_BASE
#import "../../core/color.s"
#import "../../core/dungeon_data.s"
#import "../../core/monster_flags.s"
.const CX16_DUNGEON_ROOM_FLAGS = FLAG_LIT | FLAG_VISITED
#import "../../core/player_state.s"
#import "../../core/item_defs.s"
#import "../../core/dungeon_feature_gen.s"
#import "../../core/math.s"
#import "../../core/tables.s"
#import "../../core/rng.s"
#import "../../core/numeric_format.s"
#import "../../core/player_move_basic.s"
#import "../../core/player_run_stop.s"
#import "../../core/player_search.s"
#import "../../core/town_map_basic.s"
#import "../../core/tile_display.s"
#import "../../core/town_interactions_basic.s"
#import "screen_vera.s"
#import "input.s"
#import "services.s"
#import "tier_storage.s"
#import "dungeon_module.s"
#import "item_catalog.s"
#import "overlay_storage.s"
#import "map_render.s"
#if !CX16_IMPORT_SHARED_GAME_LOOP
#import "../../core/dungeon_los.s"
#endif
#import "../../core/input_ui_helpers.s"
#import "../../core/ui_messages.s"
#import "../../core/ui_status.s"
#import "../../core/huffman.s"
#import "../../core/effect_detect_monsters.s"
#if !CX16_IMPORT_SHARED_GAME_LOOP
#import "item_message.s"
#endif
#import "../../core/ui_help_clear.s"
#define ITEM_TABLES_RESIDENT_NAMES_ONLY
#define ITEM_TABLES_RESIDENT_NO_KNOWN_NAMES
#import "../../core/item.s"
#undef ITEM_TABLES_RESIDENT_NO_KNOWN_NAMES
#undef ITEM_TABLES_RESIDENT_NAMES_ONLY
#import "../../core/ego_items.s"
#import "trampolines.s"
#import "../../core/dungeon_direction.s"
#import "../../core/trap_table.s"
#import "../../core/trap_detection.s"
#import "../../core/player_dig_ability.s"
#if CX16_IMPORT_SHARED_GAME_LOOP
#import "shared_imports.s"
#endif

.label cx16_contract_prg_load_base = CX16_PRG_LOAD_BASE
.label cx16_contract_ram_bank_count = CX16_RAM_BANK_COUNT
.label cx16_contract_ram_bank_reg = CX16_RAM_BANK_REG
.label cx16_contract_ram_bank_default = CX16_RAM_BANK_DEFAULT
.label cx16_contract_ram_bank_last = CX16_RAM_BANK_LAST
.label cx16_contract_transient_bank_base = CX16_TRANSIENT_BANK_BASE
.label cx16_contract_transient_bank_end = CX16_TRANSIENT_BANK_END
.label cx16_contract_resident_code_base = CX16_RESIDENT_CODE_BASE
.label cx16_contract_resident_code_limit = CX16_RESIDENT_CODE_LIMIT
.label cx16_contract_resident_product_limit = CX16_RESIDENT_PRODUCT_LIMIT
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
.label cx16_contract_dungeon_module_bank = CX16_DUNGEON_MODULE_BANK
.label cx16_contract_dungeon_module_load_base = CX16_DUNGEON_MODULE_LOAD_BASE
.label cx16_contract_dungeon_module_load_end = CX16_DUNGEON_MODULE_LOAD_END
.label cx16_contract_dungeon_module_entry = CX16_DUNGEON_MODULE_ENTRY
.label cx16_contract_item_catalog_bank_base = CX16_ITEM_CATALOG_BANK_BASE
.label cx16_contract_item_catalog_bank_end = CX16_ITEM_CATALOG_BANK_END
.label cx16_contract_item_catalog_primary_bank = CX16_ITEM_CATALOG_PRIMARY_BANK
.label cx16_contract_item_catalog_load_base = CX16_ITEM_CATALOG_LOAD_BASE
.label cx16_contract_item_catalog_load_end = CX16_ITEM_CATALOG_LOAD_END
.label cx16_contract_title_source_bank = CX16_TITLE_SOURCE_BANK
.label cx16_contract_title_source_load_base = CX16_TITLE_SOURCE_LOAD_BASE
.label cx16_contract_title_source_load_end = CX16_TITLE_SOURCE_LOAD_END
.label cx16_contract_overlay_cache_bank_base = CX16_OVERLAY_CACHE_BANK_BASE
.label cx16_contract_overlay_cache_bank_end = CX16_OVERLAY_CACHE_BANK_END
.label cx16_contract_overlay_startup_bank = CX16_OVERLAY_STARTUP_BANK
.label cx16_contract_overlay_town_bank = CX16_OVERLAY_TOWN_BANK
.label cx16_contract_overlay_death_bank = CX16_OVERLAY_DEATH_BANK
.label cx16_contract_overlay_royal_bank = CX16_OVERLAY_ROYAL_BANK
.label cx16_contract_overlay_gen_bank = CX16_OVERLAY_GEN_BANK
.label cx16_contract_overlay_help_bank = CX16_OVERLAY_HELP_BANK
.label cx16_contract_overlay_ui_bank = CX16_OVERLAY_UI_BANK
.label cx16_contract_overlay_items_bank = CX16_OVERLAY_ITEMS_BANK
.label cx16_contract_overlay_spell_bank = CX16_OVERLAY_SPELL_BANK
.label cx16_contract_overlay_disarm_bank = CX16_OVERLAY_DISARM_BANK
.label cx16_contract_overlay_slot_bank_base = CX16_OVERLAY_SLOT_BANK_BASE
.label cx16_contract_overlay_slot_bank_end = CX16_OVERLAY_SLOT_BANK_END
.label cx16_contract_overlay_free_bank_base = CX16_OVERLAY_FREE_BANK_BASE
.label cx16_contract_overlay_free_bank_end = CX16_OVERLAY_FREE_BANK_END
.label cx16_contract_data_cache_bank_base = CX16_DATA_CACHE_BANK_BASE
.label cx16_contract_data_cache_bank_end = CX16_DATA_CACHE_BANK_END
.label cx16_contract_work_bank_base = CX16_WORK_BANK_BASE
.label cx16_contract_work_bank_end = CX16_WORK_BANK_END

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
    jsr cx16_loader_screen_begin
    jsr cx16_preload_static_assets
    bcc !assets_ok+
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    :Cx16PrintAt(14, 30, cx16_asset_load_failed_text)
    jmp !halt-
!assets_ok:
    jsr rng_seed
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr msg_init
    jsr cx16_title_enter_menu
    cli
cx16_idle:
    jsr cx16_poll_input
    jmp cx16_idle

// cx16_preload_static_assets — Load immutable gameplay payloads before title.
// Output: carry clear = all cached; carry set = failure, cx16_preload_status:
//         1 item catalog, 2 monster tier, 3 dungeon module, 4 overlay.
cx16_preload_static_assets:
    lda #0
    sta cx16_preload_status
    lda #cx16_item_catalog_file_len
    ldx #<cx16_item_catalog_file
    ldy #>cx16_item_catalog_file
    jsr cx16_loader_show_file
    jsr cx16_load_item_catalog
    bcs !item_fail+
    lda #1
    sta cx16_preload_tier
!tier_loop:
    ldx cx16_preload_tier
    dex
    lda cx16_tier_file_lo,x
    sta zp_ptr0
    lda cx16_tier_file_hi,x
    sta zp_ptr0_hi
    lda cx16_tier_file_len,x
    ldx zp_ptr0
    ldy zp_ptr0_hi
    jsr cx16_loader_show_file
    lda cx16_preload_tier
    jsr cx16_load_tier_to_bank
    bcs !tier_fail+
    inc cx16_preload_tier
    lda cx16_preload_tier
    cmp #5
    bcc !tier_loop-
    lda #cx16_dungeon_module_file_len
    ldx #<cx16_dungeon_module_file
    ldy #>cx16_dungeon_module_file
    jsr cx16_loader_show_file
    jsr cx16_load_dungeon_module
    bcs !module_fail+
    jsr cx16_preload_all_overlays
    bcs !overlay_fail+
    clc
    rts
!item_fail:
    lda #1
    sta cx16_preload_status
    sec
    rts
!tier_fail:
    lda #2
    sta cx16_preload_status
    sec
    rts
!module_fail:
    lda #3
    sta cx16_preload_status
    sec
    rts
!overlay_fail:
    lda #4
    sta cx16_preload_status
    sec
    rts

cx16_loader_screen_begin:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr screen_clear
    :Cx16PrintAt(2, 4, cx16_loading_header_text)
    lda #5
    sta cx16_loader_row
    rts

// Print the next boot-preload filename, C128-style.
// Input: A = filename length, X/Y = filename pointer.
cx16_loader_show_file:
    sta cx16_loader_name_len
    stx zp_ptr0
    sty zp_ptr0_hi
    lda cx16_loader_row
    sta zp_cursor_row
    lda #8
    sta zp_cursor_col
    jsr screen_set_cursor
    jsr vera_set_addr_inc1
    ldy #0
!loop:
    cpy cx16_loader_name_len
    bcs !done+
    lda (zp_ptr0),y
    jsr vera_put_char_with_attr
    iny
    jmp !loop-
!done:
    inc cx16_loader_row
    rts

cx16_title_enter_menu:
    lda #CX16_STATE_TITLE
    sta cx16_state
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr cx16_call_startup_overlay_entry
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
    jsr rng_seed
    lda #$ff
    sta zp_run_dir
    lda #CX16_STATE_NEW_GAME
    sta cx16_state
    lda #TOWN_START_X
    sta cx16_player_x
    lda #TOWN_START_Y
    sta cx16_player_y
    jsr cx16_seed_bootstrap_player_state
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
    jmp cx16_run_command
!not_run:
    cmp #CMD_MOVE_N
    bcs !move_low_ok+
    jmp !done+
!move_low_ok:
    cmp #CMD_MOVE_SE + 1
    bcs !not_command+
!try_move:
    jmp cx16_try_move_command
!not_command:
    cmp #CMD_SEARCH
    bne !not_search+
    jmp !search+
!not_search:
    cmp #CMD_OPEN
    bne !not_open+
    jmp !open+
!not_open:
    cmp #CMD_CLOSE
    bne !not_close+
    jmp !close+
!not_close:
    cmp #CMD_BASH
    bne !not_bash+
    jmp !bash+
!not_bash:
    cmp #CMD_TUNNEL
    bne !not_tunnel+
    jmp !tunnel+
!not_tunnel:
    cmp #CMD_DISARM
    bne !not_disarm+
    jmp !disarm+
!not_disarm:
    cmp #CMD_REST
    bne !not_rest+
    jmp !rest+
!not_rest:
    cmp #CMD_LOOK
    bne !not_look+
    jmp !activity+
!not_look:
    cmp #CMD_SEARCH_MODE
    bne !not_search_mode+
    jmp !search_mode+
!not_search_mode:
    cmp #CMD_AUTOREST
    bne !not_autorest+
    jmp !activity+
!not_autorest:
    cmp #CMD_SAVE
    bne !not_save+
    jmp !storage+
!not_save:
    cmp #CMD_CAST
    bne !not_cast+
    jmp !magic+
!not_cast:
    cmp #CMD_PRAY
    bne !not_pray+
    jmp !magic+
!not_pray:
    cmp #CMD_RECALL
    bne !not_recall+
    jmp !magic+
!not_recall:
    cmp #CMD_GAIN
    bne !not_gain+
    jmp !magic+
!not_gain:
    cmp #CMD_CHAR_INFO
    bne !not_char_info+
    jmp !char_info+
!not_char_info:
    cmp #CMD_MAP
    bne !not_map+
    jmp !info+
!not_map:
    cmp #CMD_HELP
    bne !not_help+
    jmp !help+
!not_help:
    cmp #CMD_VERSION
    bne !not_version+
    jmp !version+
!not_version:
    cmp #CMD_WIZARD
    bne !not_wizard+
    jmp !wizard+
!not_wizard:
    cmp #CMD_PICKUP
    bne !not_pickup+
    jmp !pickup+
!not_pickup:
    cmp #CMD_DROP
    bne !not_drop+
    jmp !drop+
!not_drop:
    cmp #CMD_INVENTORY
    bne !not_inventory+
    jmp !inventory+
!not_inventory:
    cmp #CMD_EQUIPMENT
    bne !not_equipment+
    jmp !equipment+
!not_equipment:
    cmp #CMD_WEAR
    bne !not_wear+
    jmp !wear+
!not_wear:
    cmp #CMD_TAKEOFF
    bne !not_takeoff+
    jmp !takeoff+
!not_takeoff:
    cmp #CMD_EAT
    bne !not_eat+
    jmp !eat+
!not_eat:
    cmp #CMD_QUAFF
    bne !not_quaff+
    jmp !quaff+
!not_quaff:
    cmp #CMD_REFUEL
    bne !not_refuel+
    jmp !refuel+
!not_refuel:
    cmp #CMD_READ
    bne !not_read+
    jmp !read+
!not_read:
    cmp #CMD_AIM
    bne !not_aim+
    jmp !aim+
!not_aim:
    cmp #CMD_USE
    bne !not_use+
    jmp !use+
!not_use:
    cmp #CMD_OPEN
    bcc !done+
    cmp #CMD_USE + 1
    bcc !item+
    cmp #CMD_FIRE
    bcc !done+
    cmp #CMD_TUNNEL + 1
    bcc !item+
    jmp !done+
!activity:
    jmp cx16_show_activity_stub
!rest:
    jmp cx16_cmd_rest
!search_mode:
    jmp cx16_cmd_search_mode
!search:
    jmp cx16_cmd_search
!open:
    jmp cx16_cmd_open
!close:
    jmp cx16_cmd_close
!bash:
    jmp cx16_cmd_bash
!tunnel:
    jmp cx16_cmd_tunnel
!disarm:
    jmp cx16_cmd_disarm
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
!pickup:
    jmp cx16_cmd_pickup
!drop:
    jmp cx16_cmd_drop
!inventory:
    jmp cx16_cmd_inventory
!equipment:
    jmp cx16_cmd_equipment
!wear:
    jmp cx16_cmd_wear
!takeoff:
    jmp cx16_cmd_takeoff
!eat:
    jmp cx16_cmd_eat
!quaff:
    jmp cx16_cmd_quaff
!refuel:
    jmp cx16_cmd_refuel
!read:
    jmp cx16_cmd_read
!aim:
    jmp cx16_cmd_aim
!use:
    jmp cx16_cmd_use
!item:
    jmp cx16_show_item_stub
!done:
    rts

cx16_try_move_command:
    sec
    sbc #CMD_MOVE_N
    tax
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq cx16_try_dungeon_move
    txa
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

cx16_try_dungeon_move:
    jsr cx16_try_dungeon_step_dir
    rts

cx16_try_dungeon_step_dir:
    jsr player_move_compute_target
    bcc !done+
    jsr cx16_running_target_is_trap
    bcs !done+
    jsr player_move_target_walkable
    bcc !done+
    lda zp_run_dir
    cmp #$ff
    beq !not_running+
    jsr cx16_save_run_lit_state
!not_running:
    jsr cx16_save_old_player
    lda cx16_view_x
    sta cx16_old_view_x
    lda cx16_view_y
    sta cx16_old_view_y
    jsr player_move_commit_target
    jsr trap_check_at_player
    lda #0
    rol
    pha
    jsr cx16_sync_local_player_position
    jsr update_visibility
    jsr cx16_update_dungeon_view
    lda cx16_view_x
    cmp cx16_old_view_x
    bne !full+
    lda cx16_view_y
    cmp cx16_old_view_y
    bne !full+
    jsr cx16_render_dungeon_local_area
    jsr cx16_draw_dungeon_ui
    jmp !return+
!full:
    jsr cx16_refresh_dungeon_view
!return:
    pla
    beq !moved+
    clc
    rts
!moved:
    sec
    rts
!done:
    clc
    rts

cx16_save_run_lit_state:
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    :MapRead_ptr0_y()
    and #FLAG_LIT
    sta run_was_lit
    rts

cx16_running_target_is_trap:
    lda zp_run_dir
    cmp #$ff
    beq !clear+
    lda zp_temp0
    and #TILE_TYPE_MASK
    cmp #TILE_TRAP
    bne !clear+
    sec
    rts
!clear:
    clc
    rts

cx16_run_command:
    pha
    jsr msg_clear
    pla
    sec
    sbc #CMD_RUN_N
    sta zp_run_dir
    tax
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    bne !single_step+
!loop:
    ldx zp_run_dir
    jsr cx16_try_dungeon_step_dir
    bcc !stop+
    jsr run_check_stop
    bcs !stop+
    jsr input_run_cancel_check
    bne !stop+
    jmp !loop-
!single_step:
    txa
    clc
    adc #CMD_MOVE_N
    jmp cx16_try_move_command
!stop:
    lda #$ff
    sta zp_run_dir
    rts

cx16_cmd_open:
    lda #CX16_FEATURE_CMD_OPEN
    jmp cx16_call_feature_overlay_command

cx16_cmd_close:
    lda #CX16_FEATURE_CMD_CLOSE
    jmp cx16_call_feature_overlay_command

cx16_cmd_search:
    lda #CX16_FEATURE_CMD_SEARCH
    jmp cx16_call_feature_overlay_command

cx16_cmd_rest:
    lda #CX16_FEATURE_CMD_REST
    jmp cx16_call_feature_overlay_command

cx16_cmd_search_mode:
    lda #CX16_FEATURE_CMD_SEARCH_MODE
    jmp cx16_call_feature_overlay_command

cx16_cmd_bash:
    lda #CX16_FEATURE_CMD_BASH
    jmp cx16_call_feature_overlay_command

cx16_cmd_tunnel:
    lda #CX16_FEATURE_CMD_TUNNEL
    jmp cx16_call_feature_overlay_command

cx16_cmd_disarm:
    lda #CX16_FEATURE_CMD_DISARM
    jmp cx16_call_feature_overlay_command

cx16_cmd_pickup:
    lda #CX16_ITEM_CMD_PICKUP
    jmp cx16_call_items_overlay_command

cx16_cmd_drop:
    lda #CX16_ITEM_CMD_DROP
    jmp cx16_call_items_overlay_command

cx16_cmd_inventory:
    lda #CX16_ITEM_CMD_INVENTORY
    jmp cx16_call_items_overlay_command

cx16_cmd_equipment:
    lda #CX16_ITEM_CMD_EQUIPMENT
    jmp cx16_call_items_overlay_command

cx16_cmd_wear:
    lda #CX16_ITEM_CMD_WEAR
    jmp cx16_call_items_overlay_command

cx16_cmd_takeoff:
    lda #CX16_ITEM_CMD_TAKEOFF
    jmp cx16_call_items_overlay_command

cx16_cmd_eat:
    lda #CX16_ITEM_CMD_EAT
    jmp cx16_call_items_overlay_command

cx16_cmd_quaff:
    lda #CX16_ITEM_CMD_QUAFF
    jmp cx16_call_items_overlay_command

cx16_cmd_refuel:
    lda #CX16_ITEM_CMD_REFUEL
    jmp cx16_call_items_overlay_command

cx16_cmd_read:
    lda #CX16_ITEM_CMD_READ
    jmp cx16_call_items_overlay_command

cx16_cmd_aim:
    lda #CX16_ITEM_CMD_AIM
    jmp cx16_call_items_overlay_command

cx16_cmd_use:
    lda #CX16_ITEM_CMD_USE
    jmp cx16_call_items_overlay_command

cx16_call_feature_overlay_command:
    pha
    lda CX16_RAM_BANK_REG
    pha
    lda #CX16_OVERLAY_DISARM_BANK
    sta CX16_RAM_BANK_REG
    pla
    sta cx16_overlay_saved_bank
    pla
    jsr cx16_overlay_feature_command_entry
    pha
    lda cx16_overlay_saved_bank
    sta CX16_RAM_BANK_REG
    pla
    rts

cx16_call_items_overlay_command:
    pha
    lda CX16_RAM_BANK_REG
    pha
    lda #CX16_OVERLAY_ITEMS_BANK
    sta CX16_RAM_BANK_REG
    pla
    sta cx16_overlay_saved_bank
    pla
    jsr cx16_overlay_items_command_entry
    pha
    lda cx16_overlay_saved_bank
    sta CX16_RAM_BANK_REG
    pla
    rts

cx16_call_startup_overlay_entry:
    lda CX16_RAM_BANK_REG
    pha
    lda #CX16_OVERLAY_STARTUP_BANK
    sta CX16_RAM_BANK_REG
    jsr cx16_overlay_startup_entry
    pla
    sta CX16_RAM_BANK_REG
    rts

cx16_overlay_saved_bank: .byte 0

cx16_after_item_turn:
    jsr cx16_sync_local_player_position
    jsr cx16_save_old_player
    jsr update_visibility
    jsr cx16_update_dungeon_view
    jsr cx16_render_dungeon_local_area
    jmp cx16_draw_dungeon_ui

cx16_after_feature_turn:
    jsr cx16_sync_shared_player_position
    jsr cx16_sync_local_player_position
    jsr cx16_save_old_player
    jsr update_visibility
    jsr cx16_update_dungeon_view
    jsr cx16_render_dungeon_local_area
    jmp cx16_draw_dungeon_ui

cx16_after_shared_move_turn:
    jsr cx16_save_old_player
    lda cx16_view_x
    sta cx16_old_view_x
    lda cx16_view_y
    sta cx16_old_view_y
    jsr cx16_sync_local_player_position
    jsr update_visibility
    jsr cx16_update_dungeon_view
    lda cx16_view_x
    cmp cx16_old_view_x
    bne !full+
    lda cx16_view_y
    cmp cx16_old_view_y
    bne !full+
    jsr cx16_render_dungeon_local_area
    jmp cx16_draw_dungeon_ui
!full:
    jmp cx16_refresh_dungeon_view

cx16_check_town_entry:
    jsr town_basic_check_store_door
    bcc !done+
    sta cx16_store_idx
    jmp cx16_show_store_stub
!done:
    rts

cx16_try_stairs_down:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !dungeon+
    jsr town_basic_check_stairs_at_player
    cmp #9
    beq !descend+
    jmp cx16_show_no_stairs
!descend:
    jmp cx16_enter_dungeon_bootstrap
!dungeon:
    jsr cx16_current_tile_type
    cmp #9
    beq !deeper+
    jmp cx16_show_no_stairs
!deeper:
    jmp cx16_show_deeper_stub

cx16_try_stairs_up:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !dungeon+
    jsr town_basic_check_stairs_at_player
    cmp #10
    beq !ascend+
    jmp cx16_show_no_stairs
!ascend:
    jmp cx16_show_ascend_stub
!dungeon:
    jsr cx16_current_tile_type
    cmp #10
    beq !ascend_town+
    jmp cx16_show_no_stairs
!ascend_town:
    jmp cx16_return_to_town

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

cx16_seed_bootstrap_player_state:
    lda #0
    ldx #PL_STRUCT_SIZE - 1
!clear_player:
    sta player_data,x
    dex
    bpl !clear_player-

    lda #FI_EMPTY
    ldx #TOTAL_INV_SLOTS - 1
!clear_inv_ids:
    sta inv_item_id,x
    dex
    bpl !clear_inv_ids-

    lda #0
    ldx #TOTAL_INV_SLOTS - 1
!clear_inv_meta:
    sta inv_qty,x
    sta inv_p1,x
    sta inv_to_hit,x
    sta inv_to_dam,x
    sta inv_to_ac,x
    sta inv_flags,x
    sta inv_ego,x
    dex
    bpl !clear_inv_meta-

    lda #1
    sta player_data + PL_LEVEL
    sta zp_player_lvl
    sta player_data + PL_LIGHT_RAD
    sta zp_light_radius
    lda #0
    sta player_data + PL_MHP_HI
    sta player_data + PL_HP_HI
    sta zp_player_mhp_hi
    sta zp_player_hp_hi
    lda #18
    sta player_data + PL_STR_CUR
    sta zp_player_str
    lda #12
    sta player_data + PL_INT_CUR
    sta zp_player_int
    sta player_data + PL_WIS_CUR
    sta zp_player_wis
    lda #16
    sta player_data + PL_DEX_CUR
    sta zp_player_dex
    lda #12
    sta player_data + PL_CON_CUR
    sta zp_player_con
    sta player_data + PL_CHR_CUR
    sta zp_player_chr
    lda #0
    sta player_data + PL_RACE
    sta player_data + PL_CLASS
    sta player_data + PL_DLEVEL
    sta player_data + PL_MANA
    sta player_data + PL_MAX_MANA
    sta player_data + PL_AC
    sta player_data + PL_GOLD_2
    sta player_data + PL_HUNGER
    sta zp_player_race
    sta zp_player_class
    sta zp_player_dlvl
    sta zp_player_mp
    sta zp_player_mmp
    sta zp_player_ac
    sta zp_hunger_state
    lda #12
    sta player_data + PL_MHP_LO
    sta player_data + PL_HP_LO
    sta zp_player_mhp_lo
    sta zp_player_hp_lo
    lda #200
    sta player_data + PL_GOLD_0
    lda #0
    sta player_data + PL_GOLD_1
    lda #<2000
    sta player_data + PL_FOOD_LO
    sta zp_player_food
    lda #>2000
    sta player_data + PL_FOOD_HI
    sta zp_player_food_hi
    lda #$03
    sta player_data + PL_NAME
    lda #$18
    sta player_data + PL_NAME + 1
    lda #$31
    sta player_data + PL_NAME + 2
    lda #$36
    sta player_data + PL_NAME + 3
    lda #0
    sta player_data + PL_NAME + 4

    lda #63
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON
    lda #0
    sta inv_p1 + EQUIP_WEAPON
    sta inv_to_hit + EQUIP_WEAPON
    sta inv_to_dam + EQUIP_WEAPON
    sta inv_to_ac + EQUIP_WEAPON
    sta inv_flags + EQUIP_WEAPON
    sta inv_ego + EQUIP_WEAPON
    rts

cx16_new_game_draw:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr screen_clear
    jsr cx16_render_town
    jmp cx16_draw_town_ui

cx16_show_store_stub:
    lda #<cx16_store_door_text
    sta zp_ptr0
    lda #>cx16_store_door_text
    sta zp_ptr0_hi
    jsr msg_print
    lda cx16_store_idx
    clc
    adc #$31
    jmp msg_print_char

cx16_show_descend_stub:
    lda #<cx16_descend_stub_text
    sta zp_ptr0
    lda #>cx16_descend_stub_text
    sta zp_ptr0_hi
    jmp msg_print

cx16_enter_dungeon_bootstrap:
    jsr msg_clear
    lda #1
    jsr cx16_generate_dungeon_level
    bcc !module_ok+
    lda #<cx16_dungeon_module_failed_text
    sta zp_ptr0
    lda #>cx16_dungeon_module_failed_text
    sta zp_ptr0_hi
    jmp msg_print
!module_ok:
    lda #1
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    jsr item_spawn_level
    lda #CX16_BOOTSTRAP_LIGHT_RADIUS
    sta zp_light_radius
    sta player_data + PL_LIGHT_RAD
    jsr update_visibility
    lda #CX16_STATE_DUNGEON_BOOTSTRAP
    sta cx16_state
    lda #1
    sta cx16_loaded_tier
    lda #CX16_TIER_BANK_BASE
    sta cx16_loaded_tier_bank
    jsr cx16_draw_dungeon_bootstrap
    lda #<cx16_dungeon_loaded_text
    sta zp_ptr0
    lda #>cx16_dungeon_loaded_text
    sta zp_ptr0_hi
    jmp msg_print

cx16_draw_dungeon_bootstrap:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr screen_clear
    jmp cx16_refresh_dungeon_view

cx16_refresh_dungeon_view:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr cx16_update_dungeon_view
    jsr cx16_render_dungeon_viewport
    jmp cx16_draw_dungeon_ui

cx16_return_to_town:
    lda #CX16_STATE_NEW_GAME
    sta cx16_state
    lda #0
    sta player_data + PL_DLEVEL
    sta zp_player_dlvl
    lda #TOWN_START_X
    sta cx16_player_x
    lda #TOWN_START_Y
    sta cx16_player_y
    jsr cx16_sync_shared_player_position
    jsr town_map_basic_generate
    jmp cx16_new_game_draw

cx16_show_deeper_stub:
    lda #<cx16_deeper_stub_text
    sta zp_ptr0
    lda #>cx16_deeper_stub_text
    sta zp_ptr0_hi
    jmp msg_print

cx16_show_ascend_stub:
    lda #<cx16_ascend_stub_text
    sta zp_ptr0
    lda #>cx16_ascend_stub_text
    sta zp_ptr0_hi
    jmp msg_print

cx16_show_no_stairs:
    lda #<cx16_no_stairs_text
    sta zp_ptr0
    lda #>cx16_no_stairs_text
    sta zp_ptr0_hi
    jmp msg_print

cx16_show_help:
    jsr cx16_draw_help_view
    jsr input_get_modal_dismiss_key
    jmp cx16_restore_current_view

cx16_draw_help_view:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr screen_clear
    :Cx16PrintAt(3, 35, cx16_help_title_text)
    :Cx16PrintAt(7, 14, cx16_help_move_text)
    :Cx16PrintAt(9, 14, cx16_help_run_text)
    :Cx16PrintAt(11, 14, cx16_help_feature_text)
    :Cx16PrintAt(13, 14, cx16_help_item_text)
    :Cx16PrintAt(15, 14, cx16_help_views_text)
    :Cx16PrintAt(20, 33, cx16_press_key_text)
    rts

cx16_show_version:
    jsr cx16_draw_version_view
    jsr input_get_modal_dismiss_key
    jmp cx16_restore_current_view

cx16_draw_version_view:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr screen_clear
    :Cx16PrintAt(7, 33, cx16_version_title_text)
    :Cx16PrintAt(10, 24, cx16_version_text)
    :Cx16PrintAt(13, 24, cx16_version_policy_text)
    :Cx16PrintAt(20, 33, cx16_press_key_text)
    rts

cx16_show_character_info:
    jsr cx16_draw_character_view
    jsr input_get_modal_dismiss_key
    jmp cx16_restore_current_view

cx16_draw_character_view:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr screen_clear
    :Cx16PrintAt(3, 33, cx16_character_title_text)
    :Cx16PrintAt(6, 20, cx16_character_name_label)
    lda #6
    sta zp_cursor_row
    lda #26
    sta zp_cursor_col
    lda #<(player_data + PL_NAME)
    sta zp_ptr0
    lda #>(player_data + PL_NAME)
    sta zp_ptr0_hi
    jsr screen_put_string
    :Cx16PrintAt(8, 20, cx16_character_race_label)
    lda #8
    sta zp_cursor_row
    lda #26
    sta zp_cursor_col
    ldx zp_player_race
    lda race_name_ptrs_lo,x
    sta zp_ptr0
    lda race_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string
    :Cx16PrintAt(8, 42, cx16_character_class_label)
    lda #8
    sta zp_cursor_row
    lda #49
    sta zp_cursor_col
    ldx zp_player_class
    lda class_name_ptrs_lo,x
    sta zp_ptr0
    lda class_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string
    :Cx16PrintAt(10, 20, cx16_character_level_label)
    lda zp_player_lvl
    jsr screen_put_decimal
    :Cx16PrintAt(10, 42, cx16_character_depth_label)
    lda zp_player_dlvl
    jsr screen_put_decimal
    :Cx16PrintAt(12, 20, cx16_character_hp_label)
    lda zp_player_hp_lo
    sta zp_temp0
    lda zp_player_hp_hi
    sta zp_temp1
    jsr screen_put_decimal_16
    lda #$2f
    jsr screen_put_char
    lda zp_player_mhp_lo
    sta zp_temp0
    lda zp_player_mhp_hi
    sta zp_temp1
    jsr screen_put_decimal_16
    :Cx16PrintAt(12, 42, cx16_character_ac_label)
    lda zp_player_ac
    jsr screen_put_decimal
    :Cx16PrintAt(14, 20, cx16_character_gold_label)
    lda player_data + PL_GOLD_0
    sta zp_temp0
    lda player_data + PL_GOLD_1
    sta zp_temp1
    jsr screen_put_decimal_16
    :Cx16PrintAt(20, 33, cx16_press_key_text)
    rts

cx16_show_activity_stub:
    lda #<cx16_activity_stub_text
    sta zp_ptr0
    lda #>cx16_activity_stub_text
    sta zp_ptr0_hi
    jmp msg_print

cx16_show_item_stub:
    lda #<cx16_item_stub_text
    sta zp_ptr0
    lda #>cx16_item_stub_text
    sta zp_ptr0_hi
    jmp msg_print

cx16_show_magic_stub:
    lda #<cx16_magic_stub_text
    sta zp_ptr0
    lda #>cx16_magic_stub_text
    sta zp_ptr0_hi
    jmp msg_print

cx16_show_storage_stub:
    lda #<cx16_storage_stub_text
    sta zp_ptr0
    lda #>cx16_storage_stub_text
    sta zp_ptr0_hi
    jmp msg_print

cx16_show_info_stub:
    lda #<cx16_info_stub_text
    sta zp_ptr0
    lda #>cx16_info_stub_text
    sta zp_ptr0_hi
    jmp msg_print

cx16_show_wizard_stub:
    lda #<cx16_wizard_stub_text
    sta zp_ptr0
    lda #>cx16_wizard_stub_text
    sta zp_ptr0_hi
    jmp msg_print

cx16_draw_town_ui:
    jsr status_draw
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    :Cx16PrintAt(29, 14, cx16_game_help_text)
    rts

cx16_draw_dungeon_ui:
    jsr status_draw
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    :Cx16PrintAt(29, 10, cx16_dungeon_help_text)
    rts

msg_print_char:
    jmp screen_put_char

cx16_restore_current_view:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !dungeon+
    cmp #CX16_STATE_NEW_GAME
    beq !town+
    jmp cx16_title_enter_menu
!dungeon:
    jmp cx16_draw_dungeon_bootstrap
!town:
    jmp cx16_new_game_draw

#if !CX16_IMPORT_SHARED_GAME_LOOP
generation_busy_tick:
    rts
#endif

tramp_dig_ability:
    jmp calc_dig_ability

c128_town_dump_mark:
    rts

#if !CX16_IMPORT_SHARED_GAME_LOOP
player_search_mode_on:
    lda player_data + PL_FLAGS
    ora #PLF_SEARCHING
    cmp player_data + PL_FLAGS
    beq !done+
    sta player_data + PL_FLAGS
    lda zp_ui_dirty
    ora #$01
    sta zp_ui_dirty
!done:
    rts

player_search_mode_off:
    lda player_data + PL_FLAGS
    and #($ff - PLF_SEARCHING)
    cmp player_data + PL_FLAGS
    beq !done+
    sta player_data + PL_FLAGS
    lda zp_ui_dirty
    ora #$01
    sta zp_ui_dirty
!done:
    rts

trap_trigger:
    lda CX16_RAM_BANK_REG
    pha
    txa
    pha
    lda #CX16_OVERLAY_DISARM_BANK
    sta CX16_RAM_BANK_REG
    pla
    tax
    jsr cx16_overlay_trap_trigger
    pla
    sta CX16_RAM_BANK_REG
    rts

player_death_check:
    lda zp_player_hp_hi
    bmi !dead+
    ora zp_player_hp_lo
    beq !dead+
    rts
!dead:
    lda zp_game_flags
    ora #$01
    sta zp_game_flags
    lda #SFX_DEATH
    jmp hal_sound_play

decrement_stat:
    cmp #109
    bcs !above_108+
    cmp #88
    bcs !range_88_108+
    cmp #19
    bcs !range_19_87+
    cmp #4
    bcc !dec_done+
    sec
    sbc #1
    rts
!above_108:
    sec
    sbc #1
    rts
!range_88_108:
    pha
    lda #1
    ldx #6
    ldy #2
    jsr math_dice
    pla
    sec
    sbc zp_math_a
    rts
!range_19_87:
    pha
    lda #1
    ldx #15
    ldy #5
    jsr math_dice
    pla
    sec
    sbc zp_math_a
    cmp #19
    bcs !dec_done+
    lda #18
!dec_done:
    rts

creature_name_buf:
    .fill 32, 0
#endif

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
// beside moria16.prg. Keep it in banked RAM so title art does not pin the
// resident image below the old $6000 staging address.
hal_asset_load_title:
    jsr cx16_save_ram_bank
    lda #CX16_TITLE_SOURCE_BANK
    jsr cx16_select_ram_bank_a
    lda #<CX16_TITLE_SOURCE_LOAD_BASE
    sta cx16_asset_load_addr_lo
    lda #>CX16_TITLE_SOURCE_LOAD_BASE
    sta cx16_asset_load_addr_hi
    lda #cx16_title_name_len
    ldx #<cx16_title_name
    ldy #>cx16_title_name
    jsr hal_asset_load_prg_header
    php
    jsr cx16_restore_ram_bank
    plp
    rts

hal_title_art_read_ptr1:
    lda CX16_RAM_BANK_REG
    sta cx16_title_read_saved_bank
    lda #CX16_TITLE_SOURCE_BANK
    sta CX16_RAM_BANK_REG
    lda (zp_ptr1),y
    pha
    lda cx16_title_read_saved_bank
    sta CX16_RAM_BANK_REG
    pla
    rts

cx16_title_read_saved_bank: .byte 0

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

cx16_dungeon_module_failed_text:
    :ScreenText("DUNGEON MODULE LOAD FAILED.")
    .byte 0

cx16_dungeon_title_text:
    :ScreenText("DUNGEON LEVEL 1")
    .byte 0

cx16_dungeon_loaded_text:
    :ScreenText("MONSTER TIER 1 READY")
    .byte 0

cx16_dungeon_help_text:
    :ScreenText("HJKL/YUBN OR NUMBERS MOVE. < RETURNS TO TOWN. SHIFT-Q TITLE.")
    .byte 0

cx16_press_key_text:
    :ScreenText("PRESS ANY KEY")
    .byte 0

cx16_help_title_text:
    :ScreenText("COMMANDS")
    .byte 0

cx16_help_move_text:
    :ScreenText("MOVE: HJKL/YUBN OR 12346789")
    .byte 0

cx16_help_run_text:
    :ScreenText("RUN: SHIFTED DIRECTION KEYS")
    .byte 0

cx16_help_feature_text:
    :ScreenText("FEATURES: O)PEN C)LOSE S)EARCH R)EST")
    .byte 0

cx16_help_item_text:
    :ScreenText("ITEMS: G)ET D)ROP I)NVENTORY E)QUIPMENT")
    .byte 0

cx16_help_views_text:
    :ScreenText("VIEWS: ?)HELP C)HARACTER V)ERSION")
    .byte 0

cx16_version_title_text:
    :ScreenText("MORIA8")
    .byte 0

cx16_version_policy_text:
    :ScreenText("CX16 PORT IN PROGRESS")
    .byte 0

cx16_character_title_text:
    :ScreenText("CHARACTER")
    .byte 0

cx16_character_name_label:
    :ScreenText("NAME: ")
    .byte 0

cx16_character_race_label:
    :ScreenText("RACE: ")
    .byte 0

cx16_character_class_label:
    :ScreenText("CLASS: ")
    .byte 0

cx16_character_level_label:
    :ScreenText("LEVEL: ")
    .byte 0

cx16_character_depth_label:
    :ScreenText("DEPTH: ")
    .byte 0

cx16_character_hp_label:
    :ScreenText("HP: ")
    .byte 0

cx16_character_ac_label:
    :ScreenText("AC: ")
    .byte 0

cx16_character_gold_label:
    :ScreenText("GOLD: ")
    .byte 0

cx16_ascend_stub_text:
    :ScreenText("YOU ARE ALREADY IN TOWN.")
    .byte 0

cx16_deeper_stub_text:
    :ScreenText("DEEPER DUNGEON LEVELS NOT WIRED YET.")
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

cx16_asset_load_failed_text:
    :ScreenText("ASSET LOAD FAILED")
    .byte 0

cx16_loading_header_text:
    :ScreenText("LOADING:")
    .byte 0

cx16_state: .byte CX16_STATE_TITLE
cx16_player_x: .byte 0
cx16_player_y: .byte 0
cx16_store_idx: .byte 0
cx16_loaded_tier: .byte 0
cx16_loaded_tier_bank: .byte 0
cx16_dungeon_depth: .byte 0
cx16_preload_status: .byte 0
cx16_preload_tier: .byte 0
cx16_loader_row: .byte 0
cx16_loader_name_len: .byte 0

.segment Cx16DungeonGenModule
cx16_dungeon_module_entry:
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    lda #0
    sta level_entry_dir
    jsr dungeon_generate
    clc
    lda #CX16_DUNGEON_MODULE_MAGIC_A
    ldx #CX16_DUNGEON_MODULE_MAGIC_X
    ldy #CX16_DUNGEON_MODULE_VERSION
    rts

#import "../../core/special_room_gen.s"
#import "../../core/dungeon_gen.s"

cx16_dungeon_module_end:
.print "CX16 dungeon module: " + (cx16_dungeon_module_end - CX16_DUNGEON_MODULE_LOAD_BASE) + " bytes at $A000-$" + toHexString(cx16_dungeon_module_end)
.assert "CX16 dungeon module fits one banked-RAM window", cx16_dungeon_module_end <= CX16_DUNGEON_MODULE_LOAD_END + 1, true

.segment Cx16StartupOverlay
cx16_overlay_startup_entry:
#if !CX16_IMPORT_SHARED_GAME_LOOP
    jsr title_load_and_draw
    jmp title_clear_below_menu
#else
    rts
#endif
    #import "../commodore/common/title_screen.s"
    :Cx16OverlayMarker(1)
cx16_overlay_startup_end:
.print "CX16 STARTUP overlay: " + (cx16_overlay_startup_end - $a000) + " bytes at $A000-$" + toHexString(cx16_overlay_startup_end)
.assert "CX16 STARTUP overlay fits banked window", cx16_overlay_startup_end <= CX16_BANKED_RAM_END + 1, true

.segment Cx16TownOverlay
cx16_overlay_town_entry:
    rts
    :Cx16OverlayMarker(2)
cx16_overlay_town_end:
.print "CX16 TOWN overlay: " + (cx16_overlay_town_end - $a000) + " bytes at $A000-$" + toHexString(cx16_overlay_town_end)
.assert "CX16 TOWN overlay fits banked window", cx16_overlay_town_end <= CX16_BANKED_RAM_END + 1, true

.segment Cx16DeathOverlay
cx16_overlay_death_entry:
    rts
    :Cx16OverlayMarker(3)
cx16_overlay_death_end:
.print "CX16 DEATH overlay: " + (cx16_overlay_death_end - $a000) + " bytes at $A000-$" + toHexString(cx16_overlay_death_end)
.assert "CX16 DEATH overlay fits banked window", cx16_overlay_death_end <= CX16_BANKED_RAM_END + 1, true

.segment Cx16RoyalOverlay
cx16_overlay_royal_entry:
    rts
    :Cx16OverlayMarker(CX16_OVERLAY_SLOT_ROYAL)
cx16_overlay_royal_end:
.print "CX16 ROYAL overlay: " + (cx16_overlay_royal_end - $a000) + " bytes at $A000-$" + toHexString(cx16_overlay_royal_end)
.assert "CX16 ROYAL overlay fits banked window", cx16_overlay_royal_end <= CX16_BANKED_RAM_END + 1, true

.segment Cx16GenOverlay
cx16_overlay_gen_entry:
    rts
    :Cx16OverlayMarker(5)
cx16_overlay_gen_end:
.print "CX16 GEN overlay: " + (cx16_overlay_gen_end - $a000) + " bytes at $A000-$" + toHexString(cx16_overlay_gen_end)
.assert "CX16 GEN overlay fits banked window", cx16_overlay_gen_end <= CX16_BANKED_RAM_END + 1, true

.segment Cx16HelpOverlay
cx16_overlay_help_entry:
    rts
    :Cx16OverlayMarker(6)
cx16_overlay_help_end:
.print "CX16 HELP overlay: " + (cx16_overlay_help_end - $a000) + " bytes at $A000-$" + toHexString(cx16_overlay_help_end)
.assert "CX16 HELP overlay fits banked window", cx16_overlay_help_end <= CX16_BANKED_RAM_END + 1, true

.segment Cx16UiOverlay
cx16_overlay_ui_entry:
    rts
    :Cx16OverlayMarker(7)
cx16_overlay_ui_end:
.print "CX16 UI overlay: " + (cx16_overlay_ui_end - $a000) + " bytes at $A000-$" + toHexString(cx16_overlay_ui_end)
.assert "CX16 UI overlay fits banked window", cx16_overlay_ui_end <= CX16_BANKED_RAM_END + 1, true

.segment Cx16ItemsOverlay
cx16_overlay_items_entry:
cx16_overlay_items_command_entry:
#if !CX16_IMPORT_SHARED_GAME_LOOP
    cmp #CX16_ITEM_CMD_PICKUP
    bne !not_pickup+
    jmp !pickup+
!not_pickup:
    cmp #CX16_ITEM_CMD_DROP
    bne !not_drop+
    jmp !drop+
!not_drop:
    cmp #CX16_ITEM_CMD_INVENTORY
    bne !not_inventory+
    jmp !inventory+
!not_inventory:
    cmp #CX16_ITEM_CMD_EQUIPMENT
    bne !not_equipment+
    jmp !equipment+
!not_equipment:
    cmp #CX16_ITEM_CMD_WEAR
    bne !not_wear+
    jmp !wear+
!not_wear:
    cmp #CX16_ITEM_CMD_TAKEOFF
    bne !not_takeoff+
    jmp !takeoff+
!not_takeoff:
    cmp #CX16_ITEM_CMD_EAT
    bne !not_eat+
    jmp !eat+
!not_eat:
    cmp #CX16_ITEM_CMD_QUAFF
    bne !not_quaff+
    jmp !quaff+
!not_quaff:
    cmp #CX16_ITEM_CMD_REFUEL
    bne !not_refuel+
    jmp !refuel+
!not_refuel:
    cmp #CX16_ITEM_CMD_READ
    bne !not_read+
    jmp !read+
!not_read:
    cmp #CX16_ITEM_CMD_AIM
    bne !not_aim+
    jmp !aim+
!not_aim:
    cmp #CX16_ITEM_CMD_USE
    bne !not_use+
    jmp !use+
!not_use:
    rts

!pickup:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !pickup_dungeon+
    jmp cx16_show_item_stub
!pickup_dungeon:
    jsr msg_clear
    jsr item_pickup
    bcc !pickup_done+
    jmp cx16_after_item_turn
!pickup_done:
    rts

!drop:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !drop_dungeon+
    jmp cx16_show_item_stub
!drop_dungeon:
    jsr msg_clear
    jsr item_drop
    bcc !drop_done+
    jmp cx16_after_item_turn
!drop_done:
    rts

!inventory:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !inventory_dungeon+
    jmp cx16_show_item_stub
!inventory_dungeon:
    lda #$ff
    sta piw_filter
    jsr input_prepare_modal_dismiss_key
    jsr ui_inv_display
    jsr input_get_modal_dismiss_key
    jmp cx16_refresh_dungeon_view

!equipment:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !equipment_dungeon+
    jmp cx16_show_item_stub
!equipment_dungeon:
    jsr input_prepare_modal_dismiss_key
    jsr ui_equip_display
    jsr input_get_modal_dismiss_key
    jmp cx16_refresh_dungeon_view

!wear:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !wear_dungeon+
    jmp cx16_show_item_stub
!wear_dungeon:
    jsr msg_clear
    jsr item_wear
    bcc !wear_done+
    jmp cx16_after_item_turn
!wear_done:
    rts

!takeoff:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !takeoff_dungeon+
    jmp cx16_show_item_stub
!takeoff_dungeon:
    jsr msg_clear
    jsr item_takeoff
    bcc !takeoff_done+
    jmp cx16_after_item_turn
!takeoff_done:
    rts

!eat:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !eat_dungeon+
    jmp cx16_show_item_stub
!eat_dungeon:
    jsr msg_clear
    jsr item_eat
    bcc !eat_done+
    jmp cx16_after_item_turn
!eat_done:
    rts

!quaff:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !quaff_dungeon+
    jmp cx16_show_item_stub
!quaff_dungeon:
    jsr msg_clear
    jsr item_quaff
    bcc !quaff_done+
    jmp cx16_after_item_turn
!quaff_done:
    rts

!refuel:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !refuel_dungeon+
    jmp cx16_show_item_stub
!refuel_dungeon:
    jsr msg_clear
    jsr item_refuel
    bcc !refuel_done+
    jmp cx16_after_item_turn
!refuel_done:
    rts

!read:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !read_dungeon+
    jmp cx16_show_item_stub
!read_dungeon:
    jsr msg_clear
    jsr item_read_scroll
    bcc !read_done+
    jmp cx16_after_item_turn
!read_done:
    rts

!aim:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !aim_dungeon+
    jmp cx16_show_item_stub
!aim_dungeon:
    jsr msg_clear
    jsr item_aim_wand
    bcc !aim_done+
    jmp cx16_after_item_turn
!aim_done:
    rts

!use:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !use_dungeon+
    jmp cx16_show_item_stub
!use_dungeon:
    jsr msg_clear
    jsr item_use_staff
    bcc !use_done+
    jmp cx16_after_item_turn
!use_done:
    rts
#else
    rts
#endif
#if !CX16_IMPORT_SHARED_GAME_LOOP
    press_key_str:
        :ScreenText("Press any key")
        .byte 0
#endif
    #import "../../core/player_food_consts.s"
    #import "../../core/hunger_state.s"
    #import "../../core/fear_state.s"
    #import "../../core/player_combat_calc.s"
    #import "../../core/player_recalc_equipment.s"
    #import "../../core/item_desc_banked.s"
    #import "../../core/player_item_prompt.s"
    #import "../../core/ui_inventory.s"
    #import "../../core/player_item_select.s"
    #define SPELL_EFFECTS_INCLUDE_IDENTIFY
    #import "../../core/spell_effects.s"
    #undef SPELL_EFFECTS_INCLUDE_IDENTIFY
    #import "../../core/effect_heal.s"
    #import "../../core/player_heal_feedback.s"
    #import "../../core/player_item_commands.s"
    #import "../../core/item_actions_overlay.s"
    #import "../../core/ui_equipment.s"
    :Cx16OverlayMarker(8)
cx16_overlay_items_end:
.print "CX16 ITEMS overlay: " + (cx16_overlay_items_end - $a000) + " bytes at $A000-$" + toHexString(cx16_overlay_items_end)
.assert "CX16 ITEMS overlay fits banked window", cx16_overlay_items_end <= CX16_BANKED_RAM_END + 1, true

.segment Cx16SpellOverlay
cx16_overlay_spell_entry:
    rts
    :Cx16OverlayMarker(9)
cx16_overlay_spell_end:
.print "CX16 SPELL overlay: " + (cx16_overlay_spell_end - $a000) + " bytes at $A000-$" + toHexString(cx16_overlay_spell_end)
.assert "CX16 SPELL overlay fits banked window", cx16_overlay_spell_end <= CX16_BANKED_RAM_END + 1, true

.segment Cx16DisarmOverlay
cx16_overlay_disarm_entry:
cx16_overlay_feature_command_entry:
#if !CX16_IMPORT_SHARED_GAME_LOOP
    cmp #CX16_FEATURE_CMD_OPEN
    bne !not_open+
    jmp !open+
!not_open:
    cmp #CX16_FEATURE_CMD_CLOSE
    bne !not_close+
    jmp !close+
!not_close:
    cmp #CX16_FEATURE_CMD_SEARCH
    bne !not_search+
    jmp !search+
!not_search:
    cmp #CX16_FEATURE_CMD_REST
    bne !not_rest+
    jmp !rest+
!not_rest:
    cmp #CX16_FEATURE_CMD_SEARCH_MODE
    bne !not_search_mode+
    jmp !search_mode+
!not_search_mode:
    cmp #CX16_FEATURE_CMD_BASH
    bne !not_bash+
    jmp !bash+
!not_bash:
    cmp #CX16_FEATURE_CMD_TUNNEL
    bne !not_tunnel+
    jmp !tunnel+
!not_tunnel:
    cmp #CX16_FEATURE_CMD_DISARM
    bne !not_disarm+
    jmp !disarm+
!not_disarm:
    rts

!open:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !open_dungeon+
    jmp cx16_show_item_stub
!open_dungeon:
    jsr msg_clear
    jsr get_direction_target
    bcc !open_done+
    jsr door_try_open
    bcc !open_done+
    jmp cx16_after_feature_turn
!open_done:
    rts

!close:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !close_dungeon+
    jmp cx16_show_item_stub
!close_dungeon:
    jsr msg_clear
    jsr get_direction_target
    bcc !close_done+
    jsr door_try_close
    bcc !close_done+
    jmp cx16_after_feature_turn
!close_done:
    rts

!search:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !search_dungeon+
    jmp cx16_show_activity_stub
!search_dungeon:
    jsr msg_clear
    jsr do_search
    jmp cx16_after_feature_turn

!rest:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !rest_dungeon+
    jmp cx16_show_activity_stub
!rest_dungeon:
    jsr msg_clear
    jmp cx16_after_feature_turn

!search_mode:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !search_mode_dungeon+
    jmp cx16_show_activity_stub
!search_mode_dungeon:
    jsr msg_clear
    lda player_data + PL_FLAGS
    and #PLF_SEARCHING
    beq !toggle_on+
    jsr player_search_mode_off
    lda #<search_mode_off_str
    sta zp_ptr0
    lda #>search_mode_off_str
    sta zp_ptr0_hi
    jmp !print+
!toggle_on:
    jsr player_search_mode_on
    lda #<search_mode_on_str
    sta zp_ptr0
    lda #>search_mode_on_str
    sta zp_ptr0_hi
!print:
    jsr msg_print
    jmp cx16_after_feature_turn

!bash:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !bash_dungeon+
    jmp cx16_show_item_stub
!bash_dungeon:
    jsr msg_clear
    jsr bash_command
    bcc !bash_done+
    jmp cx16_after_feature_turn
!bash_done:
    rts

!tunnel:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !tunnel_dungeon+
    jmp cx16_show_item_stub
!tunnel_dungeon:
    jsr msg_clear
    jsr player_tunnel
    bcc !tunnel_done+
    jmp cx16_after_feature_turn
!tunnel_done:
    rts

!disarm:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON_BOOTSTRAP
    beq !disarm_dungeon+
    jmp cx16_show_item_stub
!disarm_dungeon:
    jsr msg_clear
    jsr disarm_command
    bcc !disarm_done+
    jmp cx16_after_shared_move_turn
!disarm_done:
    rts
#else
    rts
#endif

#if !CX16_IMPORT_SHARED_GAME_LOOP
    search_mode_on_str:
        .text "Search mode on." ; .byte 0

    search_mode_off_str:
        .text "Search mode off." ; .byte 0
#endif

    #import "../../core/dungeon_feature_actions.s"
    #import "../../core/disarm_helpers.s"
    #import "../../core/disarm.s"
    #import "../../core/tunnel.s"
    #import "../../core/bash.s"

cx16_overlay_trap_trigger:
#if !CX16_IMPORT_SHARED_GAME_LOOP
    #import "../../core/trap_effects_body.s"
#else
    rts
#endif
    :Cx16OverlayMarker(CX16_OVERLAY_SLOT_DISARM)
cx16_overlay_disarm_end:
.print "CX16 DISARM overlay: " + (cx16_overlay_disarm_end - $a000) + " bytes at $A000-$" + toHexString(cx16_overlay_disarm_end)
.assert "CX16 DISARM overlay fits banked window", cx16_overlay_disarm_end <= CX16_BANKED_RAM_END + 1, true

.segment Default
program_end:
#if !CX16_IMPORT_SHARED_GAME_LOOP
.assert "CX16 product image stays below fixed live-map base", program_end <= CX16_RESIDENT_CODE_LIMIT, true
.assert "CX16 product image keeps resident growth reserve", program_end <= CX16_RESIDENT_PRODUCT_LIMIT, true
#else
.assert "CX16 shared-gameplay probe crosses fixed live-map base; keep link-only", program_end > CX16_FIXED_LIVE_MAP_BASE, true
.assert "CX16 shared-gameplay probe crosses VERA I/O hole; keep link-only", program_end > CX16_IO_BASE, true
#endif
.assert "CX16 town uses shared town width", TOWN_MAP_COLS, 66
.assert "CX16 town uses shared town height", TOWN_MAP_ROWS, 22
.assert "CX16 town row stride matches fixed live map", MAP_COLS, 198
.assert "CX16 shared town start x", TOWN_START_X, 31
.assert "CX16 shared town start y", TOWN_START_Y, 18
