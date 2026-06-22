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
.const CX16_STATE_DUNGEON = 2
.const CX16_STATE_DEAD = 3
.const CX16_TOWN_SCREEN_ROW = 2
.const CX16_TOWN_SCREEN_COL = 7
.const CX16_TITLE_MENU_COL = 27
.const CX16_TEXT_COLOR = $01
.const CX16_DUNGEON_LIGHT_RADIUS = 1
.const CX16_FEATURE_CMD_OPEN = 0
.const CX16_FEATURE_CMD_CLOSE = 1
.const CX16_FEATURE_CMD_SEARCH = 2
.const CX16_FEATURE_CMD_REST = 3
.const CX16_FEATURE_CMD_SEARCH_MODE = 4
.const CX16_FEATURE_CMD_LOOK = 5
.const CX16_FEATURE_CMD_AUTOREST = 6
.const CX16_FEATURE_CMD_BASH = 7
.const CX16_FEATURE_CMD_TUNNEL = 8
.const CX16_FEATURE_CMD_DISARM = 9
.const CX16_UI_CMD_HELP = 0
.const CX16_UI_CMD_VERSION = 1
.const CX16_UI_CMD_CHARACTER = 2
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
.const CX16_ITEM_CMD_SEED_SURVIVAL_LOOT = 12
.const CX16_ACTIVE_MONSTER_COUNT = 32
.const CX16_ACTIVE_MONSTER_ENTRY_SIZE = 12
.const CX16_ACTIVE_MONSTER_X_OFFSET = 0
.const CX16_ACTIVE_MONSTER_Y_OFFSET = 1
.const CX16_ACTIVE_MONSTER_TYPE_OFFSET = 2
.const CX16_ACTIVE_MONSTER_EMPTY_SLOT = $ff
.const CX16_MON_CMD_SPAWN_LEVEL = 0
.const CX16_MON_CMD_PLAYER_ATTACK = 1
.const CX16_MON_CMD_ADJACENT_ATTACK = 2
.const CX16_TIER_FIELD_DISPLAY = 0
.const CX16_TIER_FIELD_COLOR = 1
.const CX16_TIER_FIELD_LEVEL = 4
.const CX16_TIER_FIELD_HD_NUM = 5
.const CX16_TIER_FIELD_HD_SIDES = 6
.const CX16_TIER_FIELD_AC = 7
.const CX16_TIER_FIELD_XP_LO = 10
.const CX16_TIER_FIELD_XP_HI = 11
.const CX16_TIER_FIELD_ATK0_TYPE = 12
.const CX16_TIER_FIELD_ATK0_DICE = 13
.const CX16_TIER_FIELD_ATK0_SIDES = 14
.const CX16_TIER_FIELD_NAME_LO = 20
.const CX16_TIER_FIELD_NAME_HI = 21
.const CX16_ATK_NORMAL = 1
.const CX16_MON_ATTACK_BASE_TOHIT_COUNT = 21
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
#import "../../core/stat_display.s"
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
#import "../../core/turn.s"
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
    cmp #CX16_STATE_DEAD
    beq !dead+
!game:
    jmp cx16_poll_game
!menu:
    jmp cx16_poll_menu
!dead:
    jmp cx16_poll_dead

cx16_poll_menu:
    jsr input_get_key
    cmp #$4e                // N
    beq !new_game+
    cmp #$6e                // n
    beq !new_game+
!done:
    rts
!new_game:
    jmp cx16_new_game_start

cx16_poll_dead:
    jsr input_get_command
    cmp #CMD_QUIT
    beq !title+
    rts
!title:
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
    jsr cx16_seed_starting_player_state
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
    jmp !look+
!not_look:
    cmp #CMD_SEARCH_MODE
    bne !not_search_mode+
    jmp !search_mode+
!not_search_mode:
    cmp #CMD_AUTOREST
    bne !not_autorest+
    jmp !autorest+
!not_autorest:
    cmp #CMD_CHAR_INFO
    bne !not_char_info+
    jmp !char_info+
!not_char_info:
    cmp #CMD_HELP
    bne !not_help+
    jmp !help+
!not_help:
    cmp #CMD_VERSION
    bne !not_version+
    jmp !version+
!not_version:
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
    jmp cx16_show_dungeon_only_message
!rest:
    jmp cx16_cmd_rest
!look:
    jmp cx16_cmd_look
!search_mode:
    jmp cx16_cmd_search_mode
!autorest:
    jmp cx16_cmd_autorest
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
!help:
    jmp cx16_show_help
!version:
    jmp cx16_show_version
!char_info:
    jmp cx16_show_character_info
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
    jmp cx16_show_dungeon_only_message
!done:
    rts

cx16_try_move_command:
    pha
    jsr msg_clear
    pla
    sec
    sbc #CMD_MOVE_N
    tax
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
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
    lda zp_temp0
    and #FLAG_OCCUPIED
    beq !not_occupied+
    lda zp_run_dir
    cmp #$ff
    bne !done+
    jsr cx16_player_attack_target
    bcc !done+
    jmp cx16_after_feature_turn
!not_occupied:
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
    jsr cx16_consume_turn_searchable
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
    cmp #CX16_STATE_DUNGEON
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

cx16_cmd_look:
    lda #CX16_FEATURE_CMD_LOOK
    jmp cx16_call_feature_overlay_command

cx16_cmd_search_mode:
    lda #CX16_FEATURE_CMD_SEARCH_MODE
    jmp cx16_call_feature_overlay_command

cx16_cmd_autorest:
    lda #CX16_FEATURE_CMD_AUTOREST
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
    jsr cx16_draw_inventory_view
    jsr input_get_modal_dismiss_key
    jmp cx16_restore_current_view

cx16_draw_inventory_view:
    lda #CX16_ITEM_CMD_INVENTORY
    jmp cx16_call_items_overlay_command

cx16_cmd_equipment:
    jsr cx16_draw_equipment_view
    jsr input_get_modal_dismiss_key
    jmp cx16_restore_current_view

cx16_draw_equipment_view:
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

cx16_call_ui_overlay_command:
    pha
    lda CX16_RAM_BANK_REG
    pha
    lda #CX16_OVERLAY_UI_BANK
    sta CX16_RAM_BANK_REG
    pla
    sta cx16_overlay_saved_bank
    pla
    jsr cx16_overlay_ui_entry
    pha
    lda cx16_overlay_saved_bank
    sta CX16_RAM_BANK_REG
    pla
    rts

cx16_call_monster_overlay_command:
    pha
    lda CX16_RAM_BANK_REG
    pha
    lda #CX16_OVERLAY_DEATH_BANK
    sta CX16_RAM_BANK_REG
    pla
    sta cx16_overlay_saved_bank
    pla
    jsr cx16_overlay_monster_command_entry
    php
    lda cx16_overlay_saved_bank
    sta CX16_RAM_BANK_REG
    plp
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

cx16_call_town_overlay_entry:
    lda CX16_RAM_BANK_REG
    pha
    lda #CX16_OVERLAY_TOWN_BANK
    sta CX16_RAM_BANK_REG
    jsr cx16_overlay_town_entry
    pla
    sta CX16_RAM_BANK_REG
    rts

cx16_overlay_saved_bank: .byte 0

cx16_consume_turn_searchable:
    jsr cx16_consume_turn
    lda zp_game_flags
    and #$01
    bne !done+
    lda player_data + PL_FLAGS
    and #PLF_SEARCHING
    beq !done+
    jsr cx16_call_search_scan_overlay_entry
    jsr cx16_consume_turn
!done:
    rts

cx16_consume_turn:
    jsr turn_post_action
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    bne !death_check+
    lda zp_game_flags
    and #$01
    bne !death_check+
    jsr cx16_monster_adjacent_attack
!death_check:
    lda zp_game_flags
    and #$01
    beq !done+
    jmp cx16_enter_death_flow
!done:
    rts

cx16_auto_rest_check_recovered:
    lda zp_player_hp_hi
    cmp zp_player_mhp_hi
    bne !not_recovered+
    lda zp_player_hp_lo
    cmp zp_player_mhp_lo
    bne !not_recovered+
    lda zp_player_mp
    cmp zp_player_mmp
    bne !not_recovered+
    sec
    rts
!not_recovered:
    clc
    rts

cx16_call_search_scan_overlay_entry:
    lda CX16_RAM_BANK_REG
    pha
    lda #CX16_OVERLAY_DISARM_BANK
    sta CX16_RAM_BANK_REG
    jsr cx16_overlay_search_scan_entry
    pla
    sta CX16_RAM_BANK_REG
    rts

cx16_after_item_turn:
    jsr cx16_consume_turn_searchable
    jsr cx16_sync_local_player_position
    jsr cx16_save_old_player
    jsr update_visibility
    jsr cx16_update_dungeon_view
    jsr cx16_render_dungeon_local_area
    jmp cx16_draw_dungeon_ui

cx16_after_feature_turn:
    jsr cx16_consume_turn_searchable
    jsr cx16_sync_shared_player_position
    jsr cx16_sync_local_player_position
    jsr cx16_save_old_player
    jsr update_visibility
    jsr cx16_update_dungeon_view
    jsr cx16_render_dungeon_local_area
    jmp cx16_draw_dungeon_ui

cx16_after_shared_move_turn:
    jsr cx16_consume_turn_searchable
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
    jmp cx16_enter_town_recovery
!done:
    rts

cx16_try_stairs_down:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !dungeon+
    jsr town_basic_check_stairs_at_player
    cmp #9
    beq !descend+
    jmp cx16_show_no_stairs
!descend:
    lda #0
    sta level_entry_dir
    lda #1
    jmp cx16_enter_dungeon_level
!dungeon:
    jsr cx16_current_tile_type
    cmp #9
    beq !deeper+
    jmp cx16_show_no_stairs
!deeper:
    lda zp_player_dlvl
    cmp #$ff
    beq !at_bottom+
    clc
    adc #1
    cmp player_data + PL_MAX_DLVL
    bcc !depth_known+
    beq !depth_known+
    sta player_data + PL_MAX_DLVL
!depth_known:
    pha
    lda #0
    sta level_entry_dir
    pla
    jmp cx16_enter_dungeon_level
!at_bottom:
    jmp cx16_show_no_stairs

cx16_try_stairs_up:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !dungeon+
    jsr town_basic_check_stairs_at_player
    cmp #10
    beq !ascend+
    jmp cx16_show_no_stairs
!ascend:
    jmp cx16_show_no_stairs
!dungeon:
    jsr cx16_current_tile_type
    cmp #10
    beq !ascend_town+
    jmp cx16_show_no_stairs
!ascend_town:
    lda zp_player_dlvl
    cmp #1
    beq !town+
    sec
    sbc #1
    pha
    lda #1
    sta level_entry_dir
    pla
    jmp cx16_enter_dungeon_level
!town:
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

cx16_depth_to_tier:
    cmp #TIER1_MAX_DLVL + 1
    bcc !tier1+
    cmp #TIER2_MAX_DLVL + 1
    bcc !tier2+
    cmp #TIER3_MAX_DLVL + 1
    bcc !tier3+
    lda #4
    rts
!tier3:
    lda #3
    rts
!tier2:
    lda #2
    rts
!tier1:
    lda #1
    rts

cx16_seed_starting_player_state:
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
    lda #'C'
    sta player_data + PL_NAME
    lda #'X'
    sta player_data + PL_NAME + 1
    lda #$31
    sta player_data + PL_NAME + 2
    lda #$36
    sta player_data + PL_NAME + 3
    lda #0
    sta player_data + PL_NAME + 4
    lda #PLF_MALE
    sta player_data + PL_FLAGS
    lda #50
    sta player_data + PL_SOCIAL_CLASS

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

cx16_enter_town_recovery:
    jsr cx16_call_town_overlay_entry
    lda #<town_recovery_str
    sta zp_ptr0
    lda #>town_recovery_str
    sta zp_ptr0_hi
    jmp msg_print

cx16_seed_survival_loot:
    lda #CX16_ITEM_CMD_SEED_SURVIVAL_LOOT
    jmp cx16_call_items_overlay_command

cx16_enter_dungeon:
    lda #0
    sta level_entry_dir
    lda #1

cx16_enter_dungeon_level:
    pha
    jsr msg_clear
    pla
    pha
    jsr cx16_generate_dungeon_level
    bcc !module_ok+
    pla
    lda #<cx16_dungeon_module_failed_text
    sta zp_ptr0
    lda #>cx16_dungeon_module_failed_text
    sta zp_ptr0_hi
    jmp msg_print
!module_ok:
    pla
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    lda zp_player_dlvl
    jsr cx16_depth_to_tier
    sta cx16_loaded_tier
    clc
    adc #(CX16_TIER_BANK_BASE - 1)
    sta cx16_loaded_tier_bank
    jsr cx16_spawn_level_monsters
    jsr item_spawn_level
    jsr cx16_seed_survival_loot
    lda #CX16_DUNGEON_LIGHT_RADIUS
    sta zp_light_radius
    sta player_data + PL_LIGHT_RAD
    jsr update_visibility
    lda #CX16_STATE_DUNGEON
    sta cx16_state
    jsr cx16_draw_dungeon
    jmp cx16_print_dungeon_ready_message

cx16_print_dungeon_ready_message:
    lda #<dungeon_ready_prefix_str
    sta zp_ptr0
    lda #>dungeon_ready_prefix_str
    sta zp_ptr0_hi
    jsr msg_print
    lda zp_player_dlvl
    jsr screen_put_decimal
    lda #<dungeon_ready_suffix_str
    sta zp_ptr0
    lda #>dungeon_ready_suffix_str
    sta zp_ptr0_hi
    jmp screen_put_string

cx16_draw_dungeon:
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

cx16_enter_death_flow:
    lda #CX16_STATE_DEAD
    sta cx16_state
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr msg_clear
    lda #<death_terminal_str
    sta zp_ptr0
    lda #>death_terminal_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp cx16_draw_dungeon_ui

cx16_spawn_level_monsters:
    lda #CX16_MON_CMD_SPAWN_LEVEL
    jmp cx16_call_monster_overlay_command

cx16_player_attack_target:
    lda #CX16_MON_CMD_PLAYER_ATTACK
    jmp cx16_call_monster_overlay_command

cx16_monster_adjacent_attack:
    lda #CX16_MON_CMD_ADJACENT_ATTACK
    jmp cx16_call_monster_overlay_command

cx16_show_no_stairs:
    lda #<no_stairs_str
    sta zp_ptr0
    lda #>no_stairs_str
    sta zp_ptr0_hi
    jmp msg_print

cx16_show_help:
    jsr cx16_draw_help_view
    jsr input_get_modal_dismiss_key
    jmp cx16_restore_current_view

cx16_draw_help_view:
    lda #CX16_UI_CMD_HELP
    jmp cx16_call_ui_overlay_command

cx16_show_version:
    jsr cx16_draw_version_view
    jsr input_get_modal_dismiss_key
    jmp cx16_restore_current_view

cx16_draw_version_view:
    lda #CX16_UI_CMD_VERSION
    jmp cx16_call_ui_overlay_command

cx16_show_character_info:
    jsr cx16_draw_character_view
    jsr input_get_modal_dismiss_key
    jmp cx16_restore_current_view

cx16_draw_character_view:
    lda #CX16_UI_CMD_CHARACTER
    jmp cx16_call_ui_overlay_command

cx16_show_dungeon_only_message:
    lda #<dungeon_only_str
    sta zp_ptr0
    lda #>dungeon_only_str
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
    cmp #CX16_STATE_DUNGEON
    beq !dungeon+
    cmp #CX16_STATE_NEW_GAME
    beq !town+
    jmp cx16_title_enter_menu
!dungeon:
    jmp cx16_draw_dungeon
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
    .if (c >= 97 && c <= 122) {
        .byte c - 96
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
    :ScreenText("N)EW")
    .byte 0

cx16_town_title_text:
    :ScreenText("Town")
    .byte 0

cx16_game_help_text:
    :ScreenText("Move: HJKL/YUBN or numbers. Shift-Q title.")
    .byte 0

cx16_dungeon_module_failed_text:
    :ScreenText("Dungeon module load failed.")
    .byte 0

cx16_dungeon_help_text:
    :ScreenText("Move: HJKL/YUBN or numbers. <: town. Shift-Q title.")
    .byte 0

#if !CX16_IMPORT_SHARED_GAME_LOOP
#define GAME_LOOP_STAIR_MOVE_STRINGS_EXTERNAL
#import "../../core/gameplay_messages.s"
#undef GAME_LOOP_STAIR_MOVE_STRINGS_EXTERNAL
#endif

cx16_memory_fail_text:
    :ScreenText("CX16 RAM bank test failed")
    .byte 0

cx16_asset_load_failed_text:
    :ScreenText("Asset load failed")
    .byte 0

#if !CX16_IMPORT_SHARED_GAME_LOOP
press_key_str:
    :ScreenText("Press any key")
    .byte 0
#endif

cx16_loading_header_text:
    :ScreenText("Loading:")
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
cx16_spawn_count: .byte 0
cx16_mon_scan_x: .byte 0
cx16_mon_scan_y: .byte 0
cx16_mon_scan_cols: .byte 0
cx16_mon_scan_rows: .byte 0
cx16_mon_spawn_x: .byte 0
cx16_mon_spawn_y: .byte 0
cx16_mon_slot: .byte 0
cx16_mon_attack_x: .byte 0
cx16_mon_attack_y: .byte 0

.segment Cx16DungeonGenModule
cx16_dungeon_module_entry:
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
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
    jsr cx16_overlay_town_recover
    jsr cx16_overlay_town_charge_recovery
    lda #15
    jsr cx16_overlay_town_add_capped_item
    lda #17
    jmp cx16_overlay_town_add_capped_item

cx16_overlay_town_recover:
    lda player_data + PL_MHP_LO
    sta player_data + PL_HP_LO
    sta zp_player_hp_lo
    lda player_data + PL_MHP_HI
    sta player_data + PL_HP_HI
    sta zp_player_hp_hi
    lda player_data + PL_MAX_MANA
    sta player_data + PL_MANA
    sta zp_player_mp
    lda #<2000
    sta player_data + PL_FOOD_LO
    sta zp_player_food
    lda #>2000
    sta player_data + PL_FOOD_HI
    sta zp_player_food_hi
    rts

cx16_overlay_town_charge_recovery:
    lda player_data + PL_GOLD_1
    ora player_data + PL_GOLD_2
    bne !charge+
    lda player_data + PL_GOLD_0
    cmp #10
    bcc !done+
!charge:
    lda player_data + PL_GOLD_0
    sec
    sbc #10
    sta player_data + PL_GOLD_0
    lda player_data + PL_GOLD_1
    sbc #0
    sta player_data + PL_GOLD_1
    lda player_data + PL_GOLD_2
    sbc #0
    sta player_data + PL_GOLD_2
!done:
    rts

cx16_overlay_town_add_capped_item:
    sta cx16_town_item_id
    jsr cx16_overlay_town_count_carried_item
    cmp #2
    bcc !add+
    rts
!add:
    lda cx16_town_item_id
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    sta fi_add_to_hit
    sta fi_add_to_dam
    sta fi_add_to_ac
    sta fi_add_flags
    sta fi_add_ego
    jsr inv_add_item
    rts

cx16_overlay_town_count_carried_item:
    lda #0
    sta cx16_town_item_count
    ldx #0
!loop:
    lda inv_item_id,x
    cmp cx16_town_item_id
    bne !next+
    inc cx16_town_item_count
!next:
    inx
    cpx #MAX_INV_SLOTS
    bcc !loop-
    lda cx16_town_item_count
    rts

cx16_town_item_id: .byte 0
cx16_town_item_count: .byte 0
    :Cx16OverlayMarker(2)
cx16_overlay_town_end:
.print "CX16 TOWN overlay: " + (cx16_overlay_town_end - $a000) + " bytes at $A000-$" + toHexString(cx16_overlay_town_end)
.assert "CX16 TOWN overlay fits banked window", cx16_overlay_town_end <= CX16_BANKED_RAM_END + 1, true

.segment Cx16DeathOverlay
#import "../../core/monster_active.s"

cx16_overlay_death_entry:
cx16_overlay_monster_command_entry:
    cmp #CX16_MON_CMD_SPAWN_LEVEL
    bne !not_spawn+
    jmp cx16_overlay_spawn_level_monsters
!not_spawn:
    cmp #CX16_MON_CMD_PLAYER_ATTACK
    bne !not_attack+
    jmp cx16_overlay_player_attack_target
!not_attack:
    cmp #CX16_MON_CMD_ADJACENT_ATTACK
    bne !done+
    jmp cx16_overlay_monster_adjacent_attack
!done:
    rts

cx16_overlay_spawn_level_monsters:
    jsr monster_init_table
    lda #3
    sta cx16_spawn_count
!loop:
    jsr cx16_overlay_find_monster_floor
    bcc !done+
    jsr cx16_overlay_spawn_basic_monster
    dec cx16_spawn_count
    bne !loop-
!done:
    rts

cx16_overlay_find_monster_floor:
    lda zp_player_y
    clc
    adc #4
    cmp #MAP_ROWS - 1
    bcc !y_ok+
    lda #1
!y_ok:
    sta cx16_mon_scan_y
    lda zp_player_x
    clc
    adc #8
    cmp #MAP_COLS - 1
    bcc !x_ok+
    lda #1
!x_ok:
    sta cx16_mon_scan_x
    lda #MAP_ROWS - 2
    sta cx16_mon_scan_rows
!row:
    lda #MAP_COLS - 2
    sta cx16_mon_scan_cols
!col:
    ldx cx16_mon_scan_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy cx16_mon_scan_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK | FLAG_OCCUPIED
    bne !next_col+
    lda cx16_mon_scan_x
    cmp zp_player_x
    bne !found+
    lda cx16_mon_scan_y
    cmp zp_player_y
    bne !found+
    jmp !next_col+
!found:
    lda cx16_mon_scan_x
    sta cx16_mon_spawn_x
    lda cx16_mon_scan_y
    sta cx16_mon_spawn_y
    sec
    rts
!next_col:
    inc cx16_mon_scan_x
    lda cx16_mon_scan_x
    cmp #MAP_COLS - 1
    bcc !col_next_ok+
    lda #1
    sta cx16_mon_scan_x
!col_next_ok:
    dec cx16_mon_scan_cols
    bne !col-
    inc cx16_mon_scan_y
    lda cx16_mon_scan_y
    cmp #MAP_ROWS - 1
    bcc !row_next_ok+
    lda #1
    sta cx16_mon_scan_y
!row_next_ok:
    dec cx16_mon_scan_rows
    bne !row-
    clc
    rts

cx16_overlay_spawn_basic_monster:
    jsr monster_find_free_slot
    bcc !done+
    stx cx16_mon_slot
    jsr cx16_overlay_pick_monster_type
    ldy #MX_X
    lda cx16_mon_spawn_x
    sta (zp_ptr0),y
    ldy #MX_Y
    lda cx16_mon_spawn_y
    sta (zp_ptr0),y
    ldy #MX_TYPE
    lda cx16_mon_type
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    jsr cx16_overlay_monster_start_hp
    pha
    ldx cx16_mon_slot
    jsr monster_get_ptr
    ldy #MX_HP_LO
    pla
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_SPEED_CNT
    lda #0
!clear_tail:
    sta (zp_ptr0),y
    iny
    cpy #MONSTER_ENTRY_SIZE
    bne !clear_tail-
    ldx cx16_mon_spawn_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy cx16_mon_spawn_x
    :MapRead_ptr0_y()
    ora #FLAG_OCCUPIED
    :MapWrite_ptr0_y()
    inc zp_mon_count
!done:
    rts

cx16_overlay_player_attack_target:
    lda zp_temp3
    ldy zp_temp4
    jsr monster_find_at
    bcc !miss+
    stx cx16_mon_slot
    jsr cx16_overlay_player_attack_hits
    bcc !miss_msg+
    jsr cx16_overlay_player_melee_damage
    ldx cx16_mon_slot
    jsr cx16_overlay_apply_player_damage_to_monster
    bcs !dead+
!hit:
    jsr cx16_overlay_print_monster_hit
    sec
    rts
!dead:
    jsr cx16_overlay_finish_monster_kill
    sec
    rts
!miss_msg:
    jsr cx16_overlay_print_player_miss
    sec
    rts
!miss:
    clc
    rts

cx16_overlay_player_attack_hits:
    jsr cx16_overlay_load_monster_type
    lda #20
    jsr rng_range
    clc
    adc #1
    cmp #1
    beq !miss+
    cmp #20
    beq !hit+
    lda player_data + PL_TOHIT
    bmi !zero_tohit+
    clc
    adc #60
    bcc !store_tohit+
    lda #255
    bne !store_tohit+
!zero_tohit:
    lda #0
!store_tohit:
    sta cx16_player_tohit
    cmp #2
    bcc !miss+
    jsr rng_range
    sta cx16_player_roll
    lda #CX16_TIER_FIELD_AC
    jsr cx16_overlay_read_tier_field
    sta cx16_mon_ac
    lda cx16_player_roll
    cmp cx16_mon_ac
    bcs !hit+
!miss:
    clc
    rts
!hit:
    sec
    rts

cx16_overlay_apply_player_damage_to_monster:
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    sec
    sbc cx16_mon_damage
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    sbc #0
    sta (zp_ptr0),y
    bmi !dead+
    bne !alive+
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    beq !dead+
!alive:
    clc
    rts
!dead:
    sec
    rts

cx16_overlay_player_melee_damage:
    ldx #EQUIP_WEAPON
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !unarmed+
    tax
    jsr item_load_dmg_dice_x
    beq !unarmed+
    pha
    jsr item_load_dmg_sides_x
    tax
    pla
    cpx #0
    beq !unarmed+
    ldy #0
    jsr math_dice
    jmp !add_bonus+
!unarmed:
    lda #1
    ldx #2
    ldy #0
    jsr math_dice
!add_bonus:
    lda player_data + PL_TODMG
    bmi !negative_bonus+
    clc
    adc zp_math_a
    bcc !store+
    lda #255
    bne !store+
!negative_bonus:
    clc
    adc zp_math_a
    bpl !store+
    lda #0
!store:
    sta cx16_mon_damage
    rts

cx16_overlay_finish_monster_kill:
    ldx cx16_mon_slot
    jsr cx16_overlay_load_monster_type
    jsr cx16_overlay_award_monster_xp
    jsr cx16_overlay_note_kill
    jsr cx16_overlay_print_monster_kill
    ldx cx16_mon_slot
    jsr monster_remove
    inc zp_dirty_count
    rts

cx16_overlay_note_kill:
    lda cx16_loaded_tier
    cmp #CREATURE_BALROG_TIER
    bne !done+
    lda cx16_mon_type
    cmp #CREATURE_BALROG
    bne !done+
    lda zp_game_flags
    ora #GAME_FLAG_WINNER
    sta zp_game_flags
!done:
    rts

cx16_overlay_award_monster_xp:
    jsr cx16_overlay_read_monster_xp_lo
    sta zp_temp0
    jsr cx16_overlay_read_monster_xp_hi
    sta zp_temp1
    lda #CX16_TIER_FIELD_LEVEL
    jsr cx16_overlay_read_tier_field
    tax
    jsr math_mul_16x8
    lda mul_result_0
    sta cx16_levelup_adj_0
    lda mul_result_1
    sta cx16_levelup_adj_1
    lda mul_result_2
    sta cx16_levelup_adj_2
    lda zp_player_lvl
    bne !have_level+
    lda #1
!have_level:
    sta cx16_levelup_divisor
    jsr cx16_overlay_div_levelup_adj_24x8
    lda zp_temp0
    sta cx16_levelup_remainder

    lda player_data + PL_XP_0
    clc
    adc cx16_levelup_adj_0
    sta player_data + PL_XP_0
    lda player_data + PL_XP_1
    adc cx16_levelup_adj_1
    sta player_data + PL_XP_1
    lda player_data + PL_XP_2
    adc cx16_levelup_adj_2
    sta player_data + PL_XP_2

    lda cx16_levelup_remainder
    beq !check_level+
    lda #0
    sta cx16_levelup_adj_0
    sta cx16_levelup_adj_1
    lda cx16_levelup_remainder
    sta cx16_levelup_adj_2
    jsr cx16_overlay_div_levelup_adj_24x8
    lda player_data + PL_XP_FRAC_LO
    clc
    adc cx16_levelup_adj_0
    sta player_data + PL_XP_FRAC_LO
    lda player_data + PL_XP_FRAC_HI
    adc cx16_levelup_adj_1
    sta player_data + PL_XP_FRAC_HI
    bcc !check_level+
    inc player_data + PL_XP_0
    bne !check_level+
    inc player_data + PL_XP_1
    bne !check_level+
    inc player_data + PL_XP_2
!check_level:
    jsr cx16_overlay_check_basic_levelup
    rts

cx16_overlay_check_basic_levelup:
!loop:
    lda player_data + PL_LEVEL
    cmp #1
    bcs !level_ok+
    rts
!level_ok:
    cmp #40
    bcc !can_gain+
    rts
!can_gain:
    cmp #29
    bcc !early_level+
    sec
    sbc #29
    tax
    lda xp_level_late_div100_lo,x
    sta zp_temp0
    lda xp_level_late_div100_hi,x
    sta zp_temp1
    ldx player_data + PL_EXPFACT
    jsr math_mul_16x8
    lda mul_result_0
    sta cx16_levelup_adj_0
    lda mul_result_1
    sta cx16_levelup_adj_1
    lda mul_result_2
    sta cx16_levelup_adj_2
    jmp !compare+
!early_level:
    sec
    sbc #1
    tax
    lda xp_level_lo,x
    sta zp_temp0
    lda xp_level_hi,x
    sta zp_temp1
    ldx player_data + PL_EXPFACT
    jsr math_mul_16x8
    lda mul_result_0
    sta cx16_levelup_adj_0
    lda mul_result_1
    sta cx16_levelup_adj_1
    lda mul_result_2
    sta cx16_levelup_adj_2
    lda #100
    sta cx16_levelup_divisor
    jsr cx16_overlay_div_levelup_adj_24x8

!compare:
    lda player_data + PL_XP_2
    cmp cx16_levelup_adj_2
    bcc !done+
    bne !gain+
    lda player_data + PL_XP_1
    cmp cx16_levelup_adj_1
    bcc !done+
    bne !gain+
    lda player_data + PL_XP_0
    cmp cx16_levelup_adj_0
    bcc !done+
!gain:
    inc player_data + PL_LEVEL
    lda player_data + PL_LEVEL
    sta zp_player_lvl
    jsr cx16_overlay_halve_levelup_excess
    jsr cx16_overlay_recalc_level_hp
    lda zp_ui_dirty
    ora #$01
    sta zp_ui_dirty
    jmp !loop-
!done:
    rts

cx16_overlay_halve_levelup_excess:
    lda player_data + PL_XP_0
    sec
    sbc cx16_levelup_adj_0
    sta zp_temp0
    lda player_data + PL_XP_1
    sbc cx16_levelup_adj_1
    sta zp_temp1
    lda player_data + PL_XP_2
    sbc cx16_levelup_adj_2
    sta zp_temp2
    lda player_data + PL_XP_FRAC_LO
    sta zp_temp3
    lda player_data + PL_XP_FRAC_HI
    sta zp_temp4

    lda zp_temp2
    lsr
    sta zp_temp2
    lda zp_temp1
    ror
    sta zp_temp1
    lda zp_temp0
    ror
    sta zp_temp0
    lda zp_temp4
    ror
    sta zp_temp4
    lda zp_temp3
    ror
    sta zp_temp3

    lda zp_temp0
    clc
    adc cx16_levelup_adj_0
    sta player_data + PL_XP_0
    lda zp_temp1
    adc cx16_levelup_adj_1
    sta player_data + PL_XP_1
    lda zp_temp2
    adc cx16_levelup_adj_2
    sta player_data + PL_XP_2
    lda zp_temp3
    sta player_data + PL_XP_FRAC_LO
    lda zp_temp4
    sta player_data + PL_XP_FRAC_HI
    rts

cx16_overlay_recalc_level_hp:
    lda player_data + PL_CLASS
    tax
    lda #CLASS_PROP_SIZE
    jsr cx16_overlay_mul_x_by_a
    tax
    lda class_properties,x
    sta zp_temp0

    lda player_data + PL_RACE
    tax
    lda #RACE_PROP_SIZE
    jsr cx16_overlay_mul_x_by_a
    tax
    lda race_properties,x
    clc
    adc zp_temp0
    sta zp_temp0

    lda player_data + PL_CON_CUR
    jsr cx16_overlay_con_hp_adj
    sta zp_temp1

    lda zp_temp0
    lsr
    clc
    adc zp_temp1
    bpl !min_check+
    lda #1
!min_check:
    cmp #1
    bcs !hp_per_level_ok+
    lda #1
!hp_per_level_ok:
    sta zp_temp1

    lda player_data + PL_LEVEL
    sec
    sbc #1
    tax
    lda zp_temp1
    jsr math_multiply
    lda zp_math_a
    clc
    adc zp_temp0
    sta player_data + PL_MHP_LO
    sta player_data + PL_HP_LO
    sta zp_player_mhp_lo
    sta zp_player_hp_lo
    lda zp_math_b
    adc #0
    sta player_data + PL_MHP_HI
    sta player_data + PL_HP_HI
    sta zp_player_mhp_hi
    sta zp_player_hp_hi
    rts

cx16_overlay_mul_x_by_a:
    sta zp_temp3
    txa
    ldx zp_temp3
    jsr math_multiply
    lda zp_math_a
    rts

cx16_overlay_con_hp_adj:
    cmp #7
    bcs !check17+
    sec
    sbc #7
    rts
!check17:
    cmp #17
    bcc !zero+
    cmp #18
    bcc !one+
    cmp #94
    bcc !two+
    cmp #117
    bcc !three+
    lda #4
    rts
!zero:
    lda #0
    rts
!one:
    lda #1
    rts
!two:
    lda #2
    rts
!three:
    lda #3
    rts

cx16_overlay_div_levelup_adj_24x8:
    lda #0
    sta zp_temp0
    ldx #24
!loop:
    asl cx16_levelup_adj_0
    rol cx16_levelup_adj_1
    rol cx16_levelup_adj_2
    rol zp_temp0
    lda zp_temp0
    cmp cx16_levelup_divisor
    bcc !no_sub+
    sbc cx16_levelup_divisor
    sta zp_temp0
    inc cx16_levelup_adj_0
!no_sub:
    dex
    bne !loop-
    rts

cx16_levelup_adj_0: .byte 0
cx16_levelup_adj_1: .byte 0
cx16_levelup_adj_2: .byte 0
cx16_levelup_divisor: .byte 0
cx16_levelup_remainder: .byte 0

cx16_overlay_pick_monster_type:
    jsr cx16_overlay_current_tier_count
    sta cx16_mon_tier_count
    lda cx16_mon_slot
!wrap:
    cmp cx16_mon_tier_count
    bcc !picked+
    sec
    sbc cx16_mon_tier_count
    jmp !wrap-
!picked:
    sta cx16_mon_type
    rts

cx16_overlay_current_tier_count:
    lda cx16_loaded_tier
    cmp #2
    bne !not_tier2+
    lda #TIER2_COUNT
    rts
!not_tier2:
    cmp #3
    bne !not_tier3+
    lda #TIER3_COUNT
    rts
!not_tier3:
    cmp #4
    bne !tier1+
    lda #TIER4_COUNT
    rts
!tier1:
    lda #TIER1_COUNT
    rts

cx16_overlay_monster_start_hp:
    lda #CX16_TIER_FIELD_HD_NUM
    jsr cx16_overlay_read_tier_field
    sta cx16_mon_hp_tmp
    lda #CX16_TIER_FIELD_HD_SIDES
    jsr cx16_overlay_read_tier_field
    clc
    adc cx16_mon_hp_tmp
    bne !done+
    lda #1
!done:
    rts

cx16_overlay_read_monster_xp_lo:
    ldx cx16_mon_slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cx16_mon_type
    lda #CX16_TIER_FIELD_XP_LO
    jmp cx16_overlay_read_tier_field

cx16_overlay_read_monster_xp_hi:
    lda #CX16_TIER_FIELD_XP_HI
    jmp cx16_overlay_read_tier_field

cx16_overlay_read_tier_field:
    sta cx16_mon_field_idx
    jsr cx16_overlay_current_tier_count
    sta cx16_mon_tier_count
    lda #<CX16_TIER_LOAD_BASE
    sta zp_ptr0
    lda #>CX16_TIER_LOAD_BASE
    sta zp_ptr0_hi
    lda cx16_mon_field_idx
    beq !add_type+
!field_loop:
    clc
    lda zp_ptr0
    adc cx16_mon_tier_count
    sta zp_ptr0
    lda zp_ptr0_hi
    adc #0
    sta zp_ptr0_hi
    dec cx16_mon_field_idx
    bne !field_loop-
!add_type:
    clc
    lda zp_ptr0
    adc cx16_mon_type
    sta zp_ptr0
    lda zp_ptr0_hi
    adc #0
    sta zp_ptr0_hi
    ldy #0
    lda cx16_loaded_tier_bank
    jmp cx16_read_byte_from_bank_a000

cx16_overlay_monster_adjacent_attack:
    ldx #0
!loop:
    cpx #MAX_MONSTERS
    bcs !done+
    stx cx16_mon_slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !next+
    ldy #MX_X
    lda (zp_ptr0),y
    sta cx16_mon_attack_x
    ldy #MX_Y
    lda (zp_ptr0),y
    sta cx16_mon_attack_y
    jsr cx16_overlay_monster_is_adjacent
    bcc !next+
    jsr cx16_overlay_monster_damage_player
    sec
    rts
!next:
    ldx cx16_mon_slot
    inx
    jmp !loop-
!done:
    clc
    rts

cx16_overlay_monster_is_adjacent:
    lda cx16_mon_attack_x
    sec
    sbc zp_player_x
    bcs !dx_pos+
    eor #$ff
    clc
    adc #1
!dx_pos:
    cmp #2
    bcs !far+
    lda cx16_mon_attack_y
    sec
    sbc zp_player_y
    bcs !dy_pos+
    eor #$ff
    clc
    adc #1
!dy_pos:
    cmp #2
    bcs !far+
    sec
    rts
!far:
    clc
    rts

cx16_overlay_monster_damage_player:
    jsr cx16_overlay_monster_attack_damage
    lda cx16_mon_damage
    beq !miss+
    lda zp_player_hp_lo
    sec
    sbc cx16_mon_damage
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sbc #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    jsr cx16_overlay_print_monster_attack
    lda zp_player_hp_hi
    bmi !dead+
    ora zp_player_hp_lo
    bne !alive+
!dead:
    jsr cx16_overlay_mark_player_killed_by_monster
!alive:
    rts
!miss:
    jmp cx16_overlay_print_monster_miss

cx16_overlay_mark_player_killed_by_monster:
    lda cx16_mon_type
    sta zp_death_source
    jmp player_death_check

cx16_overlay_monster_attack_damage:
    jsr cx16_overlay_load_monster_type
    lda #CX16_TIER_FIELD_ATK0_TYPE
    jsr cx16_overlay_read_tier_field
    sta cx16_mon_attack_type
    jsr cx16_overlay_monster_attack_hits
    bcc !no_damage+
    lda #CX16_TIER_FIELD_ATK0_DICE
    jsr cx16_overlay_read_tier_field
    beq !no_damage+
    sta cx16_mon_hp_tmp
    lda #CX16_TIER_FIELD_ATK0_SIDES
    jsr cx16_overlay_read_tier_field
    tax
    beq !no_damage+
    lda cx16_mon_hp_tmp
    ldy #0
    jsr math_dice
    lda zp_math_a
    sta cx16_mon_damage
    lda cx16_mon_attack_type
    cmp #CX16_ATK_NORMAL
    bne !done+
    jsr cx16_overlay_reduce_damage_by_ac
!done:
    rts
!no_damage:
    lda #0
    sta cx16_mon_damage
    rts

cx16_overlay_monster_attack_hits:
    ldx cx16_mon_attack_type
    cpx #CX16_MON_ATTACK_BASE_TOHIT_COUNT
    bcs !miss+
    lda cx16_mon_base_tohit,x
    sta cx16_mon_tohit
    lda #CX16_TIER_FIELD_LEVEL
    jsr cx16_overlay_read_tier_field
    sta cx16_mon_level
    asl
    clc
    adc cx16_mon_level
    clc
    adc cx16_mon_tohit
    bcc !tohit_ok+
    lda #255
!tohit_ok:
    sta cx16_mon_tohit
    lda #20
    jsr rng_range
    clc
    adc #1
    cmp #1
    beq !miss+
    cmp #20
    beq !hit+
    lda cx16_mon_tohit
    cmp #2
    bcc !miss+
    jsr rng_range
    pha
    jsr cx16_overlay_monster_effective_ac
    sta cx16_mon_roll
    pla
    cmp cx16_mon_roll
    bcs !hit+
!miss:
    clc
    rts
!hit:
    sec
    rts

cx16_overlay_monster_effective_ac:
    lda player_data + PL_AC
    ldx zp_eff_bless
    beq !done+
    clc
    adc #2
    bcc !done+
    lda #255
!done:
    rts

cx16_overlay_reduce_damage_by_ac:
    jsr cx16_overlay_monster_effective_ac
    beq !done+
    ldx cx16_mon_damage
    beq !done+
    jsr math_multiply
    ldx #200
    jsr math_div_16x8
    lda cx16_mon_damage
    sec
    sbc zp_math_a
    bcs !store+
    lda #0
!store:
    sta cx16_mon_damage
!done:
    rts

cx16_overlay_print_monster_hit:
    lda #0
    sta cmb_buf_idx
    lda #<cmb_you_str
    ldy #>cmb_you_str
    jsr combat_append_str
    lda #<cmb_hit_str
    ldy #>cmb_hit_str
    jsr combat_append_str
    lda #<cmb_the_str
    ldy #>cmb_the_str
    jsr combat_append_str
    jsr cx16_overlay_append_monster_name
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
    jmp cmb_term_and_print

cx16_overlay_print_player_miss:
    lda #0
    sta cmb_buf_idx
    lda #<cmb_you_str
    ldy #>cmb_you_str
    jsr combat_append_str
    lda #<cmb_miss_str
    ldy #>cmb_miss_str
    jsr combat_append_str
    lda #<cmb_the_str
    ldy #>cmb_the_str
    jsr combat_append_str
    jsr cx16_overlay_append_monster_name
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
    jmp cmb_term_and_print

cx16_overlay_print_monster_kill:
    lda #0
    sta cmb_buf_idx
    lda #<cmb_you_str
    ldy #>cmb_you_str
    jsr combat_append_str
    lda #<cmb_kill_str
    ldy #>cmb_kill_str
    jsr combat_append_str
    lda #<cmb_the_str
    ldy #>cmb_the_str
    jsr combat_append_str
    jsr cx16_overlay_append_monster_name
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
    jmp cmb_term_and_print

cx16_overlay_print_monster_attack:
    lda #0
    sta cmb_buf_idx
    lda #<cmb_the_cap_str
    ldy #>cmb_the_cap_str
    jsr combat_append_str
    jsr cx16_overlay_append_monster_name
    lda #<cmb_hits_you_str
    ldy #>cmb_hits_you_str
    jsr combat_append_str
    jmp cmb_term_and_print

cx16_overlay_print_monster_miss:
    lda #0
    sta cmb_buf_idx
    lda #<cmb_the_cap_str
    ldy #>cmb_the_cap_str
    jsr combat_append_str
    jsr cx16_overlay_append_monster_name
    lda #<cmb_misses_you_str
    ldy #>cmb_misses_you_str
    jsr combat_append_str
    jmp cmb_term_and_print

cx16_overlay_append_monster_name:
    jsr cx16_overlay_load_monster_type
    lda #CX16_TIER_FIELD_NAME_LO
    jsr cx16_overlay_read_tier_field
    sta cx16_mon_name_lo
    lda #CX16_TIER_FIELD_NAME_HI
    jsr cx16_overlay_read_tier_field
    sta cx16_mon_name_hi
    lda #31
    sta cx16_mon_name_count
!loop:
    lda cx16_mon_name_lo
    sta zp_ptr0
    lda cx16_mon_name_hi
    sta zp_ptr0_hi
    ldy #0
    lda cx16_loaded_tier_bank
    jsr cx16_read_byte_from_bank_a000
    beq !done+
    jsr combat_append_char
    inc cx16_mon_name_lo
    bne !ptr_ok+
    inc cx16_mon_name_hi
!ptr_ok:
    dec cx16_mon_name_count
    bne !loop-
!done:
    rts

cx16_overlay_load_monster_type:
    ldx cx16_mon_slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cx16_mon_type
    rts


cx16_mon_type: .byte 0
cx16_mon_tier_count: .byte 0
cx16_mon_field_idx: .byte 0
cx16_mon_hp_tmp: .byte 0
cx16_mon_xp_lo: .byte 0
cx16_mon_xp_hi: .byte 0
cx16_mon_damage: .byte 0
cx16_mon_attack_type: .byte 0
cx16_mon_level: .byte 0
cx16_mon_tohit: .byte 0
cx16_mon_roll: .byte 0
cx16_mon_ac: .byte 0
cx16_player_tohit: .byte 0
cx16_player_roll: .byte 0
cx16_mon_name_lo: .byte 0
cx16_mon_name_hi: .byte 0
cx16_mon_name_count: .byte 0

cx16_mon_base_tohit:
    .byte 0, 60, 0, 10, 10, 0, 0, 0, 0, 0, 0
    .byte 2, 0, 0, 5, 0, 0, 0, 0, 0, 0

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
    cmp #CX16_UI_CMD_HELP
    bne !not_help+
    jmp cx16_overlay_draw_help_view
!not_help:
    cmp #CX16_UI_CMD_VERSION
    bne !not_version+
    jmp cx16_overlay_draw_version_view
!not_version:
    cmp #CX16_UI_CMD_CHARACTER
    bne !done+
    jmp cx16_overlay_draw_character_view
!done:
    rts

cx16_overlay_draw_help_view:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr screen_clear
    :Cx16PrintAt(3, 35, cx16_help_title_text)
    :Cx16PrintAt(7, 14, cx16_help_move_text)
    :Cx16PrintAt(9, 14, cx16_help_run_text)
    :Cx16PrintAt(11, 14, cx16_help_feature_text)
    :Cx16PrintAt(13, 14, cx16_help_more_text)
    :Cx16PrintAt(15, 14, cx16_help_item_text)
    :Cx16PrintAt(17, 14, cx16_help_use_text)
    :Cx16PrintAt(19, 14, cx16_help_tools_text)
    :Cx16PrintAt(21, 14, cx16_help_views_text)
    :Cx16PrintAt(23, 14, cx16_help_system_text)
    :Cx16PrintAt(26, 33, cx16_press_key_text)
    rts

cx16_overlay_draw_version_view:
    lda #CX16_TEXT_COLOR
    jsr screen_set_color
    jsr screen_clear
    :Cx16PrintAt(7, 33, cx16_version_title_text)
    :Cx16PrintAt(10, 24, cx16_version_text)
    :Cx16PrintAt(13, 24, cx16_version_policy_text)
    :Cx16PrintAt(20, 33, cx16_press_key_text)
    rts

cx16_overlay_draw_character_view:
    jmp ui_char_display

cx16_press_key_text:
    :ScreenText("Press any key")
    .byte 0

cx16_help_title_text:
    :ScreenText("Commands")
    .byte 0

cx16_help_move_text:
    :ScreenText("Move: HJKL/YUBN or 12346789")
    .byte 0

cx16_help_run_text:
    :ScreenText("Run: shifted direction keys or . direction")
    .byte 0

cx16_help_feature_text:
    :ScreenText("Features: O)pen C)lose S)earch X)look R)est")
    .byte 0

cx16_help_more_text:
    :ScreenText("More: Ctrl-B bash +)tunnel Shift-D disarm #)search")
    .byte 0

cx16_help_item_text:
    :ScreenText("Items: G)et D)rop I)nventory E)quipment")
    .byte 0

cx16_help_use_text:
    :ScreenText("Use: W)ear T)akeoff Shift-E eat Q)uaff R)ead")
    .byte 0

cx16_help_tools_text:
    :ScreenText("Tools: A)im Z)use Shift-R refuel")
    .byte 0

cx16_help_views_text:
    :ScreenText("Views: ?)help Shift-C character V)version")
    .byte 0

cx16_help_system_text:
    :ScreenText("System: Shift-Q title")
    .byte 0

cx16_version_title_text:
    :ScreenText("Moria8")
    .byte 0

cx16_version_text:
    :ScreenText("Moria8 CX16 Port ")
    :EmitTitleVersionScreen()
    .byte 0

cx16_version_policy_text:
    :ScreenText("CX16 port in progress")
    .byte 0

#if !CX16_IMPORT_SHARED_GAME_LOOP
cx16_char_sex_label:
    :ScreenText("Sex: ")
    .byte 0

cx16_char_sex_male:
    :ScreenText("Male")
    .byte 0

cx16_char_sex_female:
    :ScreenText("Female")
    .byte 0

cx16_char_sc_label:
    :ScreenText("  SC: ")
    .byte 0

ui_char_draw_background:
    lda #12
    sta zp_cursor_row
    lda #hal_layout_character_background_col
    sta zp_cursor_col
    lda #COL_LGREY
    sta zp_text_color
    lda #<cx16_char_sex_label
    sta zp_ptr0
    lda #>cx16_char_sex_label
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_FLAGS
    and #PLF_MALE
    beq !female+
    lda #<cx16_char_sex_male
    sta zp_ptr0
    lda #>cx16_char_sex_male
    sta zp_ptr0_hi
    jmp !print_sex+
!female:
    lda #<cx16_char_sex_female
    sta zp_ptr0
    lda #>cx16_char_sex_female
    sta zp_ptr0_hi
!print_sex:
    jsr hal_screen_put_string
    lda #COL_LGREY
    sta zp_text_color
    lda #<cx16_char_sc_label
    sta zp_ptr0
    lda #>cx16_char_sc_label
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_SOCIAL_CLASS
    jmp screen_put_decimal
#endif

    #import "../../core/spell_data.s"
    #import "../../core/ui_character.s"
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
    cmp #CX16_ITEM_CMD_SEED_SURVIVAL_LOOT
    bne !not_seed_survival_loot+
    jmp !seed_survival_loot+
!not_seed_survival_loot:
    rts

!pickup:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !pickup_dungeon+
    jmp cx16_show_dungeon_only_message
!pickup_dungeon:
    jsr msg_clear
    jsr item_pickup
    bcc !pickup_done+
    jmp cx16_after_item_turn
!pickup_done:
    rts

!drop:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !drop_dungeon+
    jmp cx16_show_dungeon_only_message
!drop_dungeon:
    jsr msg_clear
    jsr item_drop
    bcc !drop_done+
    jmp cx16_after_item_turn
!drop_done:
    rts

!inventory:
    lda #$ff
    sta piw_filter
    jmp ui_inv_display

!equipment:
    jmp ui_equip_display

!wear:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !wear_dungeon+
    jmp cx16_show_dungeon_only_message
!wear_dungeon:
    jsr msg_clear
    jsr item_wear
    bcc !wear_done+
    jmp cx16_after_item_turn
!wear_done:
    rts

!takeoff:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !takeoff_dungeon+
    jmp cx16_show_dungeon_only_message
!takeoff_dungeon:
    jsr msg_clear
    jsr item_takeoff
    bcc !takeoff_done+
    jmp cx16_after_item_turn
!takeoff_done:
    rts

!eat:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !eat_dungeon+
    jmp cx16_show_dungeon_only_message
!eat_dungeon:
    jsr msg_clear
    jsr item_eat
    bcc !eat_done+
    jmp cx16_after_item_turn
!eat_done:
    rts

!quaff:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !quaff_dungeon+
    jmp cx16_show_dungeon_only_message
!quaff_dungeon:
    jsr msg_clear
    jsr item_quaff
    bcc !quaff_done+
    jmp cx16_after_item_turn
!quaff_done:
    rts

!refuel:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !refuel_dungeon+
    jmp cx16_show_dungeon_only_message
!refuel_dungeon:
    jsr msg_clear
    jsr item_refuel
    bcc !refuel_done+
    jmp cx16_after_item_turn
!refuel_done:
    rts

!read:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !read_dungeon+
    jmp cx16_show_dungeon_only_message
!read_dungeon:
    jsr msg_clear
    jsr item_read_scroll
    bcc !read_done+
    jmp cx16_after_item_turn
!read_done:
    rts

!aim:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !aim_dungeon+
    jmp cx16_show_dungeon_only_message
!aim_dungeon:
    jsr msg_clear
    jsr item_aim_wand
    bcc !aim_done+
    jmp cx16_after_item_turn
!aim_done:
    rts

!use:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !use_dungeon+
    jmp cx16_show_dungeon_only_message
!use_dungeon:
    jsr msg_clear
    jsr item_use_staff
    bcc !use_done+
    jmp cx16_after_item_turn
!use_done:
    rts

!seed_survival_loot:
    lda #15
    jsr cx16_overlay_add_random_floor_item
    lda #17
    jsr cx16_overlay_add_random_floor_item
    lda #7
    jsr cx16_overlay_add_random_floor_item
    lda #61

cx16_overlay_add_random_floor_item:
    pha
    jsr find_random_floor
    bcs !floor+
    pla
    rts
!floor:
    lda df_target_x
    sta fi_add_x
    lda df_target_y
    sta fi_add_y
    pla
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    sta fi_add_to_hit
    sta fi_add_to_dam
    sta fi_add_to_ac
    sta fi_add_flags
    sta fi_add_ego
    lda fi_add_id
    cmp #ITEM_FLASK_OIL
    bne !plain+
    lda #20
    sta fi_add_p1
!plain:
    jsr floor_item_add
    rts
#else
    rts
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
    cmp #CX16_FEATURE_CMD_LOOK
    bne !not_look+
    jmp !look+
!not_look:
    cmp #CX16_FEATURE_CMD_SEARCH_MODE
    bne !not_search_mode+
    jmp !search_mode+
!not_search_mode:
    cmp #CX16_FEATURE_CMD_AUTOREST
    bne !not_autorest+
    jmp !autorest+
!not_autorest:
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
    cmp #CX16_STATE_DUNGEON
    beq !open_dungeon+
    jmp cx16_show_dungeon_only_message
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
    cmp #CX16_STATE_DUNGEON
    beq !close_dungeon+
    jmp cx16_show_dungeon_only_message
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
    cmp #CX16_STATE_DUNGEON
    beq !search_dungeon+
    jmp cx16_show_dungeon_only_message
!search_dungeon:
    jsr msg_clear
    jsr do_search
    jmp cx16_after_feature_turn

!rest:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !rest_dungeon+
    jmp cx16_show_dungeon_only_message
!rest_dungeon:
    jsr msg_clear
    jmp cx16_after_feature_turn

!look:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !look_dungeon+
    jmp cx16_show_dungeon_only_message
!look_dungeon:
    jsr msg_clear
    jsr cx16_do_look
    jsr cx16_render_dungeon_local_area
    jmp cx16_draw_dungeon_ui

!search_mode:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !search_mode_dungeon+
    jmp cx16_show_dungeon_only_message
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
    jsr cx16_render_dungeon_local_area
    jmp cx16_draw_dungeon_ui

!autorest:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !autorest_dungeon+
    jmp cx16_show_dungeon_only_message
!autorest_dungeon:
    jsr msg_clear
    jsr player_search_mode_off
    lda #$ff
    sta zp_run_dir
    jsr input_run_cancel_reset
    jsr cx16_auto_rest_check_recovered
    bcc !autorest_turn+
    jsr cx16_render_dungeon_local_area
    jmp cx16_draw_dungeon_ui
!autorest_turn:
    jmp cx16_after_feature_turn

!bash:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !bash_dungeon+
    jmp cx16_show_dungeon_only_message
!bash_dungeon:
    jsr msg_clear
    jsr bash_command
    bcc !bash_done+
    jmp cx16_after_feature_turn
!bash_done:
    rts

!tunnel:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !tunnel_dungeon+
    jmp cx16_show_dungeon_only_message
!tunnel_dungeon:
    jsr msg_clear
    jsr player_tunnel
    bcc !tunnel_done+
    jmp cx16_after_feature_turn
!tunnel_done:
    rts

!disarm:
    lda cx16_state
    cmp #CX16_STATE_DUNGEON
    beq !disarm_dungeon+
    jmp cx16_show_dungeon_only_message
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

cx16_overlay_search_scan_entry:
    jmp search_scan_effective_silent

#if !CX16_IMPORT_SHARED_GAME_LOOP
search_mode_on_str:
    .text "Search mode on." ; .byte 0

search_mode_off_str:
    .text "Search mode off." ; .byte 0
#endif

cx16_do_look:
    jsr get_direction_target
    bcs !valid+
    clc
    rts
!valid:
    lda df_target_x
    sec
    sbc zp_player_x
    sta cx16_look_dx
    lda df_target_y
    sec
    sbc zp_player_y
    sta cx16_look_dy

!scan:
    lda df_target_x
    cmp #MAP_COLS
    bcc !x_ok+
    jmp !nothing+
!x_ok:
    lda df_target_y
    cmp #MAP_ROWS
    bcc !y_ok+
    jmp !nothing+
!y_ok:
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    sta cx16_look_tile

    ldx df_target_x
    ldy df_target_y
    jsr los_is_visible
    bcs !visible+
    jmp !nothing+
!visible:
    lda cx16_look_tile
    and #FLAG_OCCUPIED
    beq !not_monster+
    lda df_target_x
    ldy df_target_y
    jsr cx16_look_find_monster_at
    bcs !monster_found+
    jmp !nothing+
!monster_found:
    stx cx16_look_mon_slot
    jsr cx16_look_print_monster
    clc
    rts

!not_monster:
    lda cx16_look_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    bne !not_open+
    ldx #HSTR_DL_OPEN_DOOR
    jmp !print_tile+
!not_open:
    cmp #TILE_DOOR_CLOSED
    bne !not_closed+
    ldx #HSTR_DL_CLOSED_DOOR
    jmp !print_tile+
!not_closed:
    cmp #TILE_STAIRS_DN
    bne !not_sdn+
    ldx #HSTR_DL_STAIRS_DN
    jmp !print_tile+
!not_sdn:
    cmp #TILE_STAIRS_UP
    bne !not_sup+
    ldx #HSTR_DL_STAIRS_UP
    jmp !print_tile+
!not_sup:
    cmp #TILE_TRAP
    bne !not_trap+
    ldx #HSTR_DL_TRAP
    jmp !print_tile+
!not_trap:
    cmp #TILE_RUBBLE
    bne !not_rubble+
    ldx #HSTR_DL_RUBBLE
    jmp !print_tile+
!not_rubble:
    cmp #TILE_FLOOR
    beq !floor+
    ldx #HSTR_DL_WALL
    jmp !print_tile+

!floor:
    lda df_target_x
    ldy df_target_y
    jsr floor_item_find_at
    bcs !item+
    jsr glyph_find_at_stashed
    bcc !step+
    ldx #HSTR_PMU_GLYPH_OK
    jmp !print_tile+
!item:
    lda fi_item_id,x
    jsr cx16_look_print_item
    clc
    rts

!step:
    lda df_target_x
    clc
    adc cx16_look_dx
    sta df_target_x
    lda df_target_y
    clc
    adc cx16_look_dy
    sta df_target_y
    jmp !scan-

!nothing:
    ldx #HSTR_DL_NOTHING
!print_tile:
    jsr huff_print_msg
    clc
    rts

cx16_look_print_item:
    sta cx16_look_item_id
    lda #0
    sta cmb_buf_idx
    ldx #HSTR_DL_YOU_SEE
    jsr huff_append_combat
    lda cx16_look_item_id
    jsr item_get_name_ptr
    lda zp_ptr0
    ldy zp_ptr0_hi
    jsr combat_append_str
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
    jmp cmb_term_and_print

cx16_look_print_monster:
    lda #0
    sta cmb_buf_idx
    ldx #HSTR_DL_YOU_SEE
    jsr huff_append_combat
    jsr cx16_look_append_monster_name
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
    jmp cmb_term_and_print

cx16_look_find_monster_at:
    sta cx16_look_find_x
    sty cx16_look_find_y
    lda #<CREATURE_BASE
    sta zp_ptr0
    lda #>CREATURE_BASE
    sta zp_ptr0_hi
    ldx #0
!loop:
    cpx #MAX_MONSTERS
    bcs !miss+
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !next+
    ldy #MX_X
    lda (zp_ptr0),y
    cmp cx16_look_find_x
    bne !next+
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp cx16_look_find_y
    bne !next+
    sec
    rts
!next:
    clc
    lda zp_ptr0
    adc #MONSTER_ENTRY_SIZE
    sta zp_ptr0
    lda zp_ptr0_hi
    adc #0
    sta zp_ptr0_hi
    inx
    jmp !loop-
!miss:
    clc
    rts

cx16_look_append_monster_name:
    jsr cx16_look_load_monster_type
    lda #CX16_TIER_FIELD_NAME_LO
    jsr cx16_look_read_tier_field
    sta cx16_look_name_lo
    lda #CX16_TIER_FIELD_NAME_HI
    jsr cx16_look_read_tier_field
    sta cx16_look_name_hi
    lda #31
    sta cx16_look_name_count
!loop:
    lda cx16_look_name_lo
    sta zp_ptr0
    lda cx16_look_name_hi
    sta zp_ptr0_hi
    ldy #0
    lda cx16_loaded_tier_bank
    jsr cx16_read_byte_from_bank_a000
    beq !done+
    jsr combat_append_char
    inc cx16_look_name_lo
    bne !ptr_ok+
    inc cx16_look_name_hi
!ptr_ok:
    dec cx16_look_name_count
    bne !loop-
!done:
    rts

cx16_look_load_monster_type:
    lda #<CREATURE_BASE
    sta zp_ptr0
    lda #>CREATURE_BASE
    sta zp_ptr0_hi
    ldx cx16_look_mon_slot
!slot_loop:
    beq !slot_done+
    clc
    lda zp_ptr0
    adc #MONSTER_ENTRY_SIZE
    sta zp_ptr0
    lda zp_ptr0_hi
    adc #0
    sta zp_ptr0_hi
    dex
    jmp !slot_loop-
!slot_done:
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cx16_look_mon_type
    rts

cx16_look_read_tier_field:
    sta cx16_look_field_idx
    jsr cx16_look_current_tier_count
    sta cx16_look_tier_count
    lda #<CX16_TIER_LOAD_BASE
    sta zp_ptr0
    lda #>CX16_TIER_LOAD_BASE
    sta zp_ptr0_hi
    lda cx16_look_field_idx
    beq !add_type+
!field_loop:
    clc
    lda zp_ptr0
    adc cx16_look_tier_count
    sta zp_ptr0
    lda zp_ptr0_hi
    adc #0
    sta zp_ptr0_hi
    dec cx16_look_field_idx
    bne !field_loop-
!add_type:
    clc
    lda zp_ptr0
    adc cx16_look_mon_type
    sta zp_ptr0
    lda zp_ptr0_hi
    adc #0
    sta zp_ptr0_hi
    ldy #0
    lda cx16_loaded_tier_bank
    jmp cx16_read_byte_from_bank_a000

cx16_look_current_tier_count:
    lda cx16_loaded_tier
    cmp #2
    bne !not_tier2+
    lda #TIER2_COUNT
    rts
!not_tier2:
    cmp #3
    bne !not_tier3+
    lda #TIER3_COUNT
    rts
!not_tier3:
    cmp #4
    bne !tier1+
    lda #TIER4_COUNT
    rts
!tier1:
    lda #TIER1_COUNT
    rts

cx16_look_tile: .byte 0
cx16_look_dx: .byte 0
cx16_look_dy: .byte 0
cx16_look_item_id: .byte 0
cx16_look_find_x: .byte 0
cx16_look_find_y: .byte 0
cx16_look_mon_slot: .byte 0
cx16_look_mon_type: .byte 0
cx16_look_tier_count: .byte 0
cx16_look_field_idx: .byte 0
cx16_look_name_lo: .byte 0
cx16_look_name_hi: .byte 0
cx16_look_name_count: .byte 0


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
