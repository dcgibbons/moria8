// main.s — Acorn BBC Master 128 moria8 linker script + entry
//
// Assemble from platforms/bbcmaster with:
//   -libdir ../../core -libdir . -libdir hal -libdir ../commodore/common -define BBCMASTER
//
// Memory authority: docs/BBCMASTER_MEMORY_CONTRACT.md.
//   Default (resident): $0E00-$7FFF (low helpers < $3000, resident <= $8000)
//   BeebPlaySlot:       Bank 4 ($04) $8000-$A3FF (play payload, boot-preloaded)
//   Tier-name pool:     Bank 4 ($04) $A400-$A7FF
//   Overlay window:     Bank 4 ($04) $A800-$BFFF (6,144 B)
//   Live 198x66 Map:    Bank 5 ($05) $8000-$B30B + cached OVL.UI ($B400-$BDFF)
//   BeebAuxData:        Bank 6 ($06) $8000-$96FF (virt $6000-$76FF) + cached TOWN/MODAL
//   Hot Cache Bank 7:   Bank 7 ($07) cached SPELL/ITEMS/GEN
//   BeebHuffData:       ANDY ($84) $8000-$8D93 (4 KB private RAM)
//   LYNNE Shadow RAM:   ACCCON=$05 $3000-$7FFF (1KB font, 1KB gen scratch, char shadow, Mode 0)

.cpu _65c02

#define BBCMASTER
#define BBCMASTER_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_PRODUCT_OVERLAY_RUNTIME
#define BBCMASTER_PRODUCT_IRQ_VECTOR_RUNTIME
#define PLATFORM_PRODUCT_IRQ_VECTOR_RUNTIME
.if (!cmdLineVars.containsKey("OVL_OUT")) {
    .error "OVL_OUT is required; generated files belong under build/"
}
.eval var OVL_OUT = cmdLineVars.get("OVL_OUT")

// ============================================================
// Segment definitions
// ============================================================
.segmentdef StartupOverlay     [outPrg=OVL_OUT + "/ovl.start",    start=$a800, min=$a800, max=$bfff]
.segmentdef TownOverlay        [outPrg=OVL_OUT + "/ovl.town",     start=$a800, min=$a800, max=$bfff]
.segmentdef DeathOverlay       [outPrg=OVL_OUT + "/ovl.death",    start=$a800, min=$a800, max=$bfff]
.segmentdef ModalMiscOverlay   [outPrg=OVL_OUT + "/ovl.modal",    start=$a800, min=$a800, max=$bfff]
.segmentdef HelpOverlay        [outPrg=OVL_OUT + "/ovl.help",     start=$a800, min=$a800, max=$bfff]
.segmentdef UiOverlay          [outPrg=OVL_OUT + "/ovl.ui",       start=$a800, min=$a800, max=$bfff]
.segmentdef ItemActionsOverlay [outPrg=OVL_OUT + "/ovl.items",    start=$a800, min=$a800, max=$bfff]
.segmentdef SpellOverlay       [outPrg=OVL_OUT + "/ovl.spell",    start=$a800, min=$a800, max=$bfff]
.segmentdef DungeonGenOverlay  [outPrg=OVL_OUT + "/ovl.gen",      start=$a800, min=$a800, max=$bfff]
.segmentdef StorageOverlay     [outPrg=OVL_OUT + "/ovl.storage",  start=$a800, min=$a800, max=$bfff]
.segmentdef TitleOverlay       [outPrg=OVL_OUT + "/ovl.title",    start=$a800, min=$a800, max=$bfff]
.segmentdef ChestOverlay       [outPrg=OVL_OUT + "/ovl.chest",    start=$a800, min=$a800, max=$bfff]
.segmentdef BeebPlaySlot       [outPrg=OVL_OUT + "/beeb.play",    start=$8000, min=$8000, max=$a3ff]
.segmentdef BeebAuxData        [outPrg=OVL_OUT + "/beeb.auxdata", start=$6000, min=$6000, max=$76ff]
.segmentdef BeebHuffData       [outPrg=OVL_OUT + "/beeb.huffdata",start=$8000, min=$8000, max=$8fff]

// Segment placement macros
.macro HuffmanDataSegment() {
    .segment BeebHuffData
}
.macro AuxDataSegment() {
    .segment BeebAuxData
}
.macro ItemNameStreamsSegment() {
    .segment BeebAuxData
}
.macro ItemNameStreamsRestoreSegment() {
    .segment Default
}
.macro ResidentItemsSegment() {
    .segment Default
}
.macro ResidentItemNamesSegment() {
    .segment Default
}
.macro ResidentWorldSegment() {
    .segment Default
}
.macro ResidentPlaySegment() {
    .segment BeebPlaySlot
}

// Open BeebPlaySlot ($8000) with its 3-byte "M8P" signature so any early
// BeebPlaySlot contributions land after the signature.
.segment BeebPlaySlot
beeb_play_start:
    .byte $4d, $38, $50     // "M8P"
beeb_play_body:
.segment Default

// ============================================================
// Low Always-Resident Region ($0E00-$2FFF)
// ============================================================
// All code that switches ACCCON ($3000-$7FFF LYNNE) or calls MOS/DFS ($8000-$BFFF
// Sideways ROMs) must reside below $3000.
.pc = $0e00 "Resident"
entry_bootstrap:
    jmp entry_main

// tramp_dig_ability — pinned jump for tunnel code (resident).
tramp_dig_ability:
    jmp calc_dig_ability

tsi_krev_cached: .byte 0

#import "hal/hal_contract.s"
#import "hal/storage_policy.s"
#import "save_slot_policy.s"
#import "vic_palette_consts.s"
#import "../../core/zeropage.s"
#import "hal/layout.s"
#import "memory.s"
#import "hal/lifecycle_policy.s"
#import "overlay.s"
.const OVL_STORAGE = 11
.const OVL_TITLE   = 12
#define SAVE_SLOT_INDEX_EXTERNAL
#import "reu_stub.s"
#import "memory_bank.s"
#import "mmu_macros.s"
#import "screen.s"
#import "config.s"
#import "sound.s"
#import "input.s"
#import "../../core/storage_status.s"
#import "overlay_storage.s"
#import "storage.s"
#import "save_stream.s"
#import "services.s"

low_helpers_end:
.print "BBC Master low helpers end: $" + toHexString(low_helpers_end)
.assert "Low helpers stay below $3000", low_helpers_end <= $3000, true

// ============================================================
// Resident Core Gameplay Modules ($1E00-$7FFF)
// ============================================================
#import "../../core/color.s"
#import "../../core/rng.s"
#import "../../core/math.s"
#import "../../core/tables.s"
#import "../../core/item_defs.s"
#import "../../core/player.s"

// The message-history ring buffer lives in BeebAuxData (Bank 6); writes go
// through mmu_safe_map_write_ptr1.
#define MSG_HISTORY_IN_AUX
.macro MsgHistorySegment() {
    .segment BeebAuxData
}
.macro MsgHistoryRestoreSegment() {
    .segment Default
}
#import "../../core/ui_messages.s"
#import "../../core/ui_status.s"
#import "../../core/runtime_ui_strings.s"
#import "../../core/generation_busy.s"
#define SMALL_PLAY_EXTERNAL
#import "../../core/stat_display.s"
#import "../../core/huffman.s"
.segment BeebHuffData
ovl_huffdata_end:
.segment Default
#import "../../core/dungeon_data.s"
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
#define PLACE_SECRETS_EXTERNAL
.macro ChestSearchSegment() {
    .segment BeebPlaySlot
}
.macro ChestSearchRestoreSegment() {
    .segment Default
}
#define CHEST_ROUTING_ENABLED
#define CMD_JAM_SEGMENT_CUSTOM
#define CMD_JAM_WRAPPER_CUSTOM
#define CMD_JAM_EXTERNAL
.macro CmdJamSegment() {
    .segment ChestOverlay
}
.macro CmdJamRestoreSegment() {
    .segment Default
}
#define DOOR_PICK_EXTERNAL
.macro DoorPickSegment() {
    .segment ChestOverlay
}
.macro DoorPickRestoreSegment() {
    .segment Default
}
.macro CmdJamWrapperSegment() {
    .segment Default
}
.macro CmdJamWrapperRestoreSegment() {
    .segment BeebPlaySlot
}
#import "../../core/dungeon_features.s"
#import "../../core/chest_search.s"
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
#import "../../core/monster.s"

combat_msg_monster_in_way:
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cmb_type
    lda #<cmb_in_way_str
    ldy #>cmb_in_way_str
    jmp combat_msg_monster_suffix
cmb_in_way_str:
    .text " is in your way!" ; .byte 0

#import "../../core/tier_manager.s"
#import "../../core/monster_ai.s"
#import "../../core/scene_dirty.s"
#import "../../core/scene_force.s"
#import "../../core/monster_magic.s"
.macro ChestSummonsSegment() {
    .segment BeebPlaySlot
}
.macro ChestSummonsRestoreSegment() {
    .segment BeebPlaySlot
}
// item_spawn_level runs from OVL.GEN behind the resident trampoline below:
// the resident image had no room once items started to stack.
#define ITEM_SPAWN_IN_GEN_OVERLAY
.macro ItemSpawnSegment() {
    .segment DungeonGenOverlay
}
.macro ItemSpawnRestoreSegment() {
    .segment Default
}
#import "../../core/item.s"
// The acid attack's armour damage (MON-015) is resident (Default): the play
// payload has no room for it.
#define MON_ATK_ACID_EXTERNAL
#import "../../core/monster_acid.s"
.macro ChestLootSegment() {
    .segment DungeonGenOverlay
}
.macro ChestLootRestoreSegment() {
    .segment Default
}
#import "../../core/chest_loot.s"
// The look flash rides resident RAM: the play payload has no headroom since
// monster drops (MON-014) added their hooks there.
#import "../../core/look_flash_target.s"
#define ITEM_ACTIONS_OVERLAY_EXTERNAL
#define PLAYER_ITEM_COMMANDS_EXTERNAL
#define PLAYER_ITEM_SELECT_EXTERNAL
#import "../../core/player_items.s"
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../core/spell_effects.s"
#import "../../core/spell_effects_overlay.s"
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY

#import "../../core/store_data_defs.s"
#import "../../core/recall_defs.s"
#import "../../core/spell_data_defs.s"

#import "../../core/player_magic_state.s"
#import "../../core/player_magic_state_ops.s"
#import "../../core/player_magic.s"
#import "dungeon_render.s"
#import "../../core/item_desc_banked.s"
#import "../../core/projectile.s"

// ============================================================
// entry_main — jumped to via entry_bootstrap ($0E00) after MORIA8P preload
// ============================================================
entry_main:
    cld
    jsr hal_platform_init_early
    jsr beeb_reset_session_state
    jsr generation_busy_install
    jsr platform_services_install_beeb
    jsr platform_services_assert_installed

restart_entry:
    jsr detect_machine
    jsr reu_detect
    jsr tier_init
    jsr hal_sound_init
    jsr rng_seed

title_enter_menu:
    lda #$ff
    sta save_slot_index
    lda #COL_LGREY
    sta zp_text_color

    lda #OVL_TITLE
    jsr overlay_load
    jsr title_clear_full_screen
    jsr title_load_and_draw
    jsr title_clear_below_menu

    jsr msg_init
    jsr title_show_sysinfo
    jsr title_draw_menu

title_menu_loop:
    jsr input_get_key
    cmp #$4e                // 'N' — new game
    bne !not_n+
!new_game:
    jsr beeb_require_play
    jmp game_new_start
!not_n:
    cmp #$4c                // 'L' — load game
    bne !not_l+
    lda disk_setup_done
    bne !load_now+
    jsr tramp_disk_setup
    bcs title_enter_menu
!load_now:
    jmp title_load_game
!not_l:
    cmp #$44                // 'D' — disk setup
    bne title_menu_loop
    jsr tramp_disk_setup
    jmp title_enter_menu

title_draw_menu:
    lda #COL_WHITE
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #28                 // Center 80-col: (80-24)/2 = 28
    sta zp_cursor_col
    lda #<title_menu_str
    sta zp_ptr0
    lda #>title_menu_str
    sta zp_ptr0_hi
    jmp screen_put_string

title_str:
    .text "MORIA 8 (BBC MASTER)"
    .byte 0

beeb_reset_session_state:
    lda #8
    sta program_device
    sta save_device
    sta disk_prompt_device
    lda #1
    sta disk_mode
    lda #0
    sta disk_setup_done
    rts

title_load_game:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr hal_sound_play
#if !BYPASS_SLOT_PROMPT
    jsr save_prepare_slot_prompt
    bcs !title_load_fail+
#endif
    jsr disk_prompt_save
    jsr ui_clear_full_screen_safe
    jsr ui_reset_message_state
#if !BYPASS_SLOT_PROMPT
    jsr save_select_slot_prompt
#endif
    jsr load_game
    bcc !title_load_fail+
    jsr disk_prompt_game
    jsr beeb_require_play
    jsr disk_prompt_game_required
    jmp load_resume_game
!title_load_fail:
    jsr input_get_modal_dismiss_key
    jmp title_enter_menu

title_show_sysinfo:
    lda #OVL_TITLE
    jsr overlay_load
    bcs !done+
    jsr title_show_sysinfo_banked
!done:
    rts

// ============================================================
// Platform services (indirect API slots in core/platform_services_api.s)
// ============================================================
platform_services_install_beeb:
    lda #$4c
    sta platform_main_loop_begin_api
    sta platform_vector_reassert_api
    sta platform_runtime_resync_api

    lda #<beeb_platform_main_loop_begin
    sta platform_main_loop_begin_api + 1
    lda #>beeb_platform_main_loop_begin
    sta platform_main_loop_begin_api + 2

    lda #<beeb_platform_vector_reassert
    sta platform_vector_reassert_api + 1
    lda #>beeb_platform_vector_reassert
    sta platform_vector_reassert_api + 2

    lda #<beeb_platform_runtime_resync
    sta platform_runtime_resync_api + 1
    lda #>beeb_platform_runtime_resync
    sta platform_runtime_resync_api + 2

    jmp platform_services_mark_installed

// ============================================================
// Special rooms trampolines — implementations live in OVL.GEN
// ============================================================
tramp_level_generate:
    jmp level_generate

tramp_assign_special_room:
    lda #<assign_special_room
    ldy #>assign_special_room
    jmp gen_dispatch

tramp_vault_seal_entrance:
    lda #<vault_seal_entrance
    ldy #>vault_seal_entrance
    jmp gen_dispatch

tramp_spawn_special_room_monsters:
    lda #<spawn_special_room_monsters
    ldy #>spawn_special_room_monsters
    jmp gen_dispatch

tramp_spawn_nest_gold:
    lda #<spawn_nest_gold
    ldy #>spawn_nest_gold
    jmp gen_dispatch

item_spawn_level:
    lda #<item_spawn_level_gen
    ldy #>item_spawn_level_gen
    jmp gen_dispatch

tramp_find_special_room:
    lda #<find_special_room
    ldy #>find_special_room
gen_dispatch:
    sta gen_disp_jmp+1
    sty gen_disp_jmp+2
    lda #OVL_DUNGEON_GEN
    jsr overlay_load
    bcs !done+
gen_disp_jmp:
    jmp $0000
!done:
    rts

tramp_sr_epilogue:
    php
    jsr beeb_platform_runtime_resync
    plp
    rts

#if !BYPASS_SLOT_PROMPT
save_prepare_slot_prompt:
    lda #OVL_STORAGE
    jmp overlay_load

save_select_slot_prompt:
    jmp save_select_slot_prompt_impl
#endif

// ============================================================
// UI / item / store / spell trampolines
// ============================================================
overlay_load_no_kernal:
    jmp overlay_load

run_initialize:
    jmp run_initialize_impl

tramp_ui_help_display:
    lda #OVL_HELP
    jsr overlay_load
    bcs !done+
    lda #<help_pages
    sta help_pages_src_lo
    lda #>help_pages
    sta help_pages_src_hi
    jsr ui_help_display
!done:
    rts

tramp_ui_char_display:
    lda #OVL_UI
    jsr overlay_load
    bcs !done+
    jsr ui_char_display
!done:
    rts

tramp_ui_inv_display:
    lda #<ui_inv_display
    ldy #>ui_inv_display
    jmp ui_dispatch

tramp_ui_inv_select_display:
    lda #<ui_inv_select_display
    ldy #>ui_inv_select_display
    jmp ui_dispatch

tramp_ui_equip_display:
    lda #<ui_equip_display
    ldy #>ui_equip_display
    jmp ui_dispatch

tramp_ui_equip_select_display:
    lda #<ui_equip_select_display
    ldy #>ui_equip_select_display
ui_dispatch:
    sta ui_disp_jmp+1
    sty ui_disp_jmp+2
    lda #OVL_UI
    jsr overlay_load
    bcs !done+
ui_disp_jmp:
    jmp $0000
!done:
    rts

tramp_ui_recall:
    lda #OVL_MODAL_MISC
    jsr overlay_load
    bcs !done+
    jsr ui_recall_display
!done:
    rts

tramp_item_gain_spell:
    lda #<item_gain_spell
    ldy #>item_gain_spell
    jmp spell_dispatch

tramp_item_read_scroll:
    lda #<item_read_scroll
    ldy #>item_read_scroll
    jmp tramp_items_dispatch

tramp_item_aim_wand:
    lda #<item_aim_wand
    ldy #>item_aim_wand
    jmp tramp_items_dispatch

tramp_item_use_staff:
    lda #<item_use_staff
    ldy #>item_use_staff
    jmp tramp_items_dispatch

tramp_eff_earthquake:
    lda #OVL_DEATH
    jsr overlay_load
    bcs !load_failed+
    jsr eff_earthquake
    jmp tramp_restore_spell_overlay
!load_failed:
    rts

tramp_eff_map_area:
    lda #OVL_DEATH
    jsr overlay_load
    bcs !load_failed+
    jsr eff_map_area
    jmp tramp_restore_spell_overlay
!load_failed:
    rts

tramp_item_refuel:
    lda #<item_refuel
    ldy #>item_refuel
    jmp tramp_items_dispatch

tramp_ranged_fire:
    lda #<ranged_fire
    ldy #>ranged_fire
    jmp tramp_items_dispatch

tramp_throw_item:
    lda #<throw_item
    ldy #>throw_item
    jmp tramp_items_dispatch

tramp_bash_command:
    lda #<bash_command
    ldy #>bash_command
    jmp tramp_items_dispatch

tramp_disarm_command:
    lda #<disarm_command
    ldy #>disarm_command
    jmp tramp_items_dispatch

tramp_chest_open:
    lda #<chest_open_command
    ldy #>chest_open_command
    jmp chest_dispatch

chest_dispatch:
    sta chest_disp_jmp+1
    sty chest_disp_jmp+2
    lda #OVL_CHEST
    jsr overlay_load
    bcs !done+
chest_disp_jmp:
    jmp $0000
!done:
    rts

tramp_player_tunnel:
    lda #<player_tunnel
    ldy #>player_tunnel
    jmp tramp_items_dispatch

tramp_spell_list_display:
    lda #<spell_list_display
    ldy #>spell_list_display
    jmp spell_dispatch

tramp_spell_execute_selected:
    lda #<spell_execute_selected
    ldy #>spell_execute_selected
    jmp spell_dispatch

tramp_reveal_floorplan:
    lda #<eff_reveal_floorplan
    ldy #>eff_reveal_floorplan
    jmp spell_dispatch

tramp_cmd_jam:
    lda #<door_jam_command
    ldy #>door_jam_command
    jmp chest_dispatch

tramp_door_pick_roll:
    lda #OVL_CHEST
    jsr overlay_load
    bcs !load_failed+
    jsr door_pick_roll
    rts
!load_failed:
    clc
    rts

tramp_magic_recalc_mana:
    lda #<magic_recalc_mana
    ldy #>magic_recalc_mana
    jmp spell_dispatch

tramp_magic_check_new_spells:
    lda #<magic_check_new_spells
    ldy #>magic_check_new_spells
    jmp spell_dispatch

tramp_calc_spell_failure:
    lda #<calc_spell_failure
    ldy #>calc_spell_failure
    jmp spell_dispatch

tramp_player_cast_spell:
    lda #<player_cast_spell
    ldy #>player_cast_spell
    jmp spell_dispatch

tramp_player_pray:
    lda #<player_pray
    ldy #>player_pray
spell_dispatch:
    sta spell_disp_jmp+1
    sty spell_disp_jmp+2
    lda #OVL_SPELL
    jsr overlay_load
    bcs !done+
spell_disp_jmp:
    jmp $0000
!done:
    rts

tramp_item_wear:
    lda #<item_wear
    ldy #>item_wear
    jmp tramp_items_dispatch

tramp_item_takeoff:
    lda #<item_takeoff
    ldy #>item_takeoff
    jmp tramp_items_dispatch

tramp_item_eat:
    lda #<item_eat
    ldy #>item_eat
    jmp tramp_items_dispatch

tramp_item_quaff:
    lda #<item_quaff
    ldy #>item_quaff
    jmp tramp_items_dispatch

tramp_item_recalc:
    lda #<player_recalc_equipment
    ldy #>player_recalc_equipment
    jmp tramp_items_dispatch

tramp_select_filtered_inv:
    pha
    txa
    pha
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !load_failed+
    lda #OVL_ITEMS
    sta piw_return_overlay
    pla
    tax
    pla
    jsr piw_select_filtered_inv
    jmp tramp_restore_spell_overlay
!load_failed:
    pla
    pla
    clc
    rts

tramp_eff_destroy_area:
    lda #OVL_DEATH
    jsr overlay_load
    bcs !load_failed+
    jsr da_devastate
    jmp tramp_restore_spell_overlay
!load_failed:
    rts

tramp_restore_spell_overlay:
    php
    pha
    lda #OVL_NONE
    sta piw_return_overlay
    lda #OVL_SPELL
    jsr overlay_load
    bcc !restored+
    brk
!restored:
    pla
    plp
    rts

tramp_select_filtered_inv_key_spell:
    pha
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !load_failed+
    lda #OVL_ITEMS
    sta piw_return_overlay
    pla
    jsr piw_select_filtered_inv_key
    jmp tramp_restore_spell_overlay
!load_failed:
    pla
    clc
    rts

tramp_ui_identify:
    lda #OVL_HELP
    jsr overlay_load
    bcs !done+
    jsr ui_identify_print
    jsr tier_restore_after_overlay
!done:
    rts

tramp_ui_wizard_display:
    lda #OVL_MODAL_MISC
    jsr overlay_load
    bcs !done+
    jsr ui_wizard_display
!done:
    rts

tramp_item_init_identification:
    lda #OVL_STARTUP
    jsr overlay_load
    bcs !done+
    jsr item_init_identification
!done:
    rts

tramp_disk_setup:
    lda #OVL_STORAGE
    jsr overlay_load
    bcs !done+
    jsr beeb_disk_setup_run
!done:
    rts

tramp_disk_prepare_selected:
    lda #OVL_STORAGE
    jsr overlay_load
    bcs !done+
    jsr beeb_disk_prepare_selected
!done:
    rts

tramp_store_init_all:
    lda #<store_init_all
    ldy #>store_init_all
    jmp chest_dispatch

tramp_store_restock_all:
    lda #<store_restock_all
    ldy #>store_restock_all
    jmp chest_dispatch

tramp_store_enter:
    lda #OVL_TOWN
    jsr overlay_load
    bcs !done+
    jsr store_enter
!done:
    rts

tramp_player_create:
    lda #OVL_STARTUP
    jsr overlay_load
    bcs !done+
    jsr player_create
!done:
    rts

// ============================================================
// Media prompts (1-drive swap mode only)
// ============================================================
disk_prompt_save:
    lda disk_mode
    cmp #1                      // 1-drive swap mode
    beq !dps_load+
    clc
    rts
!dps_load:
    lda #OVL_STORAGE
    jsr overlay_load
    bcs !done+
    jsr disk_prompt_save_impl
!done:
    rts

disk_prompt_game:
    lda disk_mode
    cmp #1                      // 1-drive swap mode
    beq !dpg_load+
    clc
    rts
!dpg_load:
    lda #OVL_STORAGE
    jsr overlay_load
    bcs !dpg_done+
    jsr disk_prompt_game_impl
!dpg_done:
    rts

// ============================================================
// Death orchestration
// ============================================================
tramp_game_over_disk_setup:
    jsr tramp_disk_setup
    bcs !done+
    lda #1
    sta disk_setup_done
    jsr tramp_game_over_prepare
    clc
!done:
    rts

tramp_game_over_disk_setup_failed:
    clc
    rts

tramp_game_over_prepare:
    lda death_source_saved
    sta zp_death_source

    lda zp_game_flags
    and #GAME_FLAG_WINNER
    bne !tgo_load_overlay+
    lda zp_death_source
    cmp #DEATH_ALIVE
    beq !tgo_load_overlay+
    cmp #DEATH_CHEST_NEEDLE
    bcs !tgo_load_overlay+
    tax
    jsr creature_get_name

!tgo_load_overlay:
    lda #OVL_DEATH
    jmp overlay_load

tramp_game_over:
    jsr tramp_game_over_prepare
    bcs !done+
    jmp tramp_game_over_run
!done:
    rts

tramp_winner_royal:
    lda #OVL_DEATH
    jsr overlay_load
    bcs !done+
    jsr winner_apply_retirement_bonus_overlay
    lda #OVL_MODAL_MISC
    jsr overlay_load
    bcs !done+
    jsr royal_screen
!done:
    rts

game_over_prompt:
    lda #OVL_DEATH
    jsr overlay_load
    bcc !overlay_ok+
    jmp title_enter_menu
!overlay_ok:
    jmp game_restart_overlay

// hal_msg_print_indirect_aux — Print NUL-terminated BeebAuxData string at
// (zp_ptr0) via low-RAM staging buffer beeb_ss_buf.
.label beeb_aux_str_stage = beeb_ss_buf
beeb_msg_print_indirect_aux:
hal_msg_print_indirect_aux:
    ldy #$ff
!loop:
    iny
    jsr mmu_safe_map_read_ptr0
    sta beeb_aux_str_stage,y
    bne !loop-
    lda #<beeb_aux_str_stage
    sta zp_ptr0
    lda #>beeb_aux_str_stage
    sta zp_ptr0_hi
    jmp msg_print

.segment Default
player_adjust_equipment_stat:
    jsr player_adjust_equipment_stat_prepare
    cpx #EQUIP_RING
    bcc !paes_done+
    cpx #EQUIP_AMULET
    bne !paes_str+
    lda inv_item_id,x
    and #1
    eor #3
    sbc #1
    tax
    jmp !paes_apply+
!paes_str:
    ldx #0
!paes_apply:
    jmp player_adjust_equipment_stat_apply
!paes_done:
    rts

// ============================================================
// BeebPlaySlot segment — play payload in Sideways Bank 4 ($8000-$A3FF).
// Signature "M8P" validated by beeb_require_play.
// ============================================================
.segment BeebPlaySlot
#import "../../core/chest_summons.s"

#define STORE_RUNTIME_DATA_EXTERNAL
#define STORE_INVENTORY_DATA_EXTERNAL
#import "../../core/store_data.s"
#undef STORE_INVENTORY_DATA_EXTERNAL
#undef STORE_RUNTIME_DATA_EXTERNAL
#import "../../core/store_hot_data.s"
#define RECALL_ARRAY_DATA_EXTERNAL
#import "../../core/recall.s"
#undef RECALL_ARRAY_DATA_EXTERNAL
#import "../../core/dungeon_los.s"
#import "../../core/monster_attack.s"

.macro PlayerMoveRestoreResidentSegment() {
    .segment BeebPlaySlot
}
.macro PlayerMoveLookSegment() {
    .segment ModalMiscOverlay
}
.macro PlayerCastSegment() {
    .segment SpellOverlay
}
.macro PlayerCastRestoreResidentSegment() {
    .segment Default
}
.macro PmHelpersSegment() {
    .segment SpellOverlay
}
.macro PmHelpersRestoreSegment() {
    .segment Default
}
.macro ItemInitIdentSegment() {
    .segment StartupOverlay
}
.macro ItemInitIdentRestoreSegment() {
    .segment Default
}
.macro WizardGenExecRestoreSegment() {
    .segment BeebPlaySlot
}
.macro WizardGenExecSegment() {
    .segment ModalMiscOverlay
}
#define RECALL_VIEW_OVERLAYED
.const RECALL_VIEW_OVL = OVL_MODAL_MISC
.macro RecallViewBodySegment() {
    .segment ModalMiscOverlay
}
.macro RecallViewBodyRestoreSegment() {
    .segment BeebPlaySlot
}
.macro ChestRouteSegment() {
    .segment Default
}
.macro ChestRouteRestoreSegment() {
    .segment BeebPlaySlot
}
#define PLAYER_LOOK_EXTERNAL
#import "../../core/player_move.s"
#undef PLAYER_LOOK_EXTERNAL
.macro PlayerRunInitializeSegment() {
    .segment BeebPlaySlot
}
.macro PlayerRunRestoreResidentSegment() {
    .segment BeebPlaySlot
}
#define PLAYER_RUN_INITIALIZE_EXTERNAL
#import "../../core/player_run.s"
#undef PLAYER_RUN_INITIALIZE_EXTERNAL
#define PMU_TURN_FEEDBACK_EXTERNAL
#define CMB_WINNER_STR_EXTERNAL
#define CMB_IN_WAY_EXTERNAL
#import "../../core/combat.s"
#undef CMB_IN_WAY_EXTERNAL
#undef CMB_WINNER_STR_EXTERNAL
#undef PMU_TURN_FEEDBACK_EXTERNAL
#define WIZARD_PROMPT_HELPERS_EXTERNAL
#import "../../core/wizard.s"
#undef WIZARD_PROMPT_HELPERS_EXTERNAL
#define PLAYER_LOOK_EXTERNAL
#define DISARM_COMMAND_EXTERNAL
#define WELCOME_STR_EXTERNAL
#define GAME_LOOP_NAV_STRINGS_EXTERNAL
#define GAME_LOOP_NO_STAIRS_STR_EXTERNAL
#import "../../core/game_loop.s"
#undef DISARM_COMMAND_EXTERNAL
#undef PLAYER_LOOK_EXTERNAL
#import "dungeon_scroll.s"
#define TURN_REST_DISTURBED_EXTERNAL
#import "../../core/turn.s"
#undef TURN_REST_DISTURBED_EXTERNAL
#import "../../core/player_heal_feedback.s"
// Potion heal/cure effects: reached from the items and spell overlays.
#import "../../core/eff_potion_cure.s"
#import "../../core/ui_restore.s"
#import "../../core/ui_help_clear.s"
#import "../../core/stat_display.s"

.segment Default
tramp_do_look:
    lda #OVL_MODAL_MISC
    jsr overlay_load_no_kernal
    bcs !done+
    jsr do_look
!done:
    jmp tramp_sr_epilogue

.assert "Play payload starts with 3-byte signature", beeb_play_body - beeb_play_start, 3

// ============================================================
// BeebAuxData segment — Virtual $6000-$76FF -> Bank 6 Physical $8000-$96FF
// ============================================================
.segment BeebAuxData
#import "../../core/store_inventory_data.s"
#import "../../core/recall_array_data.s"
#import "../../core/spell_class_data.s"
#define STORE_HOT_DATA_EXTERNAL
#import "../../core/store_runtime_data.s"
#undef STORE_HOT_DATA_EXTERNAL
#import "../../core/spell_helper_tables.s"
#import "../../core/spell_names.s"

.align $100
beeb_ego_suffix_slots:
hal_ego_suffix_slots:
beeb_ego_suffix_none: .byte 0
    .fill 16 - (* - beeb_ego_suffix_none), 0
beeb_ego_suffix_slay_animal: .text " (Slay Animal)" ; .byte 0
    .fill 16 - (* - beeb_ego_suffix_slay_animal), 0
beeb_ego_suffix_slay_evil: .text " (Slay Evil)" ; .byte 0
    .fill 16 - (* - beeb_ego_suffix_slay_evil), 0
beeb_ego_suffix_slay_undead: .text " (Slay Undead)" ; .byte 0
    .fill 16 - (* - beeb_ego_suffix_slay_undead), 0
beeb_ego_suffix_flame: .text " (Flame)" ; .byte 0
    .fill 16 - (* - beeb_ego_suffix_flame), 0
beeb_ego_suffix_frost: .text " (Frost)" ; .byte 0
    .fill 16 - (* - beeb_ego_suffix_frost), 0
beeb_ego_suffix_defender: .text " (Defender)" ; .byte 0
    .fill 16 - (* - beeb_ego_suffix_defender), 0
beeb_ego_suffix_holy_avenger: .text " (Holy Avenger)" ; .byte 0
    .fill 16 - (* - beeb_ego_suffix_holy_avenger), 0
beeb_ego_suffix_slots_end:
.assert "Beeb ego suffix slots are page aligned", <beeb_ego_suffix_slots, 0
.assert "Beeb ego suffix slots are 8 x 16 bytes", beeb_ego_suffix_slots_end - beeb_ego_suffix_slots, EGO_TYPE_COUNT * 16

welcome_str:
    .text "Welcome to Moria! ?=help. Shift+Q=quit." ; .byte 0
search_mode_on_str:
    .text "Search mode on." ; .byte 0
search_mode_off_str:
    .text "Search mode off." ; .byte 0
descend_str:
    .text "You descend the staircase." ; .byte 0
ascend_str:
    .text "You ascend the staircase." ; .byte 0
at_surface_str:
    .text "You are already at the surface." ; .byte 0
no_stairs_str:
    .text "You see no stairs here." ; .byte 0
cmb_winner_str:
    .text "You have won! Shift+Q to claim victory." ; .byte 0
ovl_auxdata_end:
.print "BeebAuxData: " + (ovl_auxdata_end - $6000) + " bytes"
.assert "BeebAuxData fits $6000-$76FF", ovl_auxdata_end <= $7700, true

.segment Default
turn_rest_disturbed: .byte 0

// ============================================================
// Overlay segment blocks ($A800-$BFFF in Bank 4)
// ============================================================
.segment TownOverlay
#import "../../core/store.s"
#import "../../core/ui_store.s"
#import "../../core/ui_home.s"
#import "../../core/ui_home_text.s"
ovl_town_end:
.print "Town overlay: " + (ovl_town_end - $a800) + " bytes"
.assert "Town overlay fits window", ovl_town_end <= $c000, true

.segment StartupOverlay
#import "../../core/background_data.s"
#import "../../core/player_create.s"
ovl_start_end:
.print "Startup overlay: " + (ovl_start_end - $a800) + " bytes"
.assert "Startup overlay fits", ovl_start_end <= $c000, true

.segment DeathOverlay
winner_apply_retirement_bonus_overlay:
    lda player_data + PL_LEVEL
    cmp #41
    bcs !gold+
    clc
    adc #40
    sta player_data + PL_LEVEL
    sta zp_player_lvl
!gold:
    lda player_data + PL_GOLD_0
    clc
    adc #$90
    sta player_data + PL_GOLD_0
    lda player_data + PL_GOLD_1
    adc #$d0
    sta player_data + PL_GOLD_1
    lda player_data + PL_GOLD_2
    adc #$03
    sta player_data + PL_GOLD_2
    lda player_data + PL_XP_0
    clc
    adc #$40
    sta player_data + PL_XP_0
    lda player_data + PL_XP_1
    adc #$4b
    sta player_data + PL_XP_1
    lda player_data + PL_XP_2
    adc #$4c
    sta player_data + PL_XP_2
    rts

game_restart_overlay:
    lda #0
    ldx #0
!clr_zp:
    sta zp_player_x,x
    inx
    cpx #(zp_entropy - zp_player_x + 1)
    bne !clr_zp-

    lda #0
    sta eff_fear_timer
    ldx #3
!clr_recall:
    sta recall_query_sc,x
    dex
    bpl !clr_recall-

    lda #$ff
    ldx #TOTAL_INV_SLOTS - 1
!clr_inv_id:
    sta inv_item_id,x
    dex
    bpl !clr_inv_id-

    lda #0
    ldx #TOTAL_INV_SLOTS - 1
!clr_inv_rest:
    sta inv_qty,x
    sta inv_p1,x
    sta inv_flags,x
    dex
    bpl !clr_inv_rest-

    sta current_tier
    sta tier_loaded
    jmp title_enter_menu
#import "../../core/score_io.s"
#import "../../core/score.s"

tramp_game_over_run:
    jsr score_calculate
    jsr hiscore_load
    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    bne !tgo_skip_hiscore+
    jsr hiscore_insert
    jsr hiscore_save
!tgo_skip_hiscore:
    lda death_source_saved
    sta zp_death_source
    jmp score_death_screen
    #define SCROLL_P3_NEW_OWNER
    #define SCROLL_P3_EXISTING_OWNER
    #import "../../core/scroll_effects_p3.s"
    #undef SCROLL_P3_EXISTING_OWNER
    #undef SCROLL_P3_NEW_OWNER
    #import "../../core/player_destroy_area.s"
    #import "../../core/player_magic_map.s"
    #import "../../core/player_magic_earthquake.s"
ovl_death_end:
.print "Death overlay: " + (ovl_death_end - $a800) + " bytes"
.assert "High-score I/O counter is owned by death overlay", hiscore_io_count_lo >= $a800 && hiscore_io_count_hi < ovl_death_end, true
.assert "High-score I/O does not alias storage counter", hiscore_io_count_lo != save_count_lo && hiscore_io_count_hi != save_count_hi, true
.assert "Death overlay fits", ovl_death_end <= $c000, true

.segment ModalMiscOverlay
#import "../../core/royal.s"
#import "../../core/ui_recall.s"
#import "../../core/ui_wizard.s"

wizard_prompt_clear_digits:
    lda #0
    sta wizard_num_digits
    lda #5
    sta zp_cursor_row
    lda wizard_prompt_input_col
    sta zp_cursor_col
    lda #$20
    jsr hal_screen_put_char
    lda #$20
    jsr hal_screen_put_char
    lda #5
    sta zp_cursor_row
    lda wizard_prompt_input_col
    sta zp_cursor_col
    rts

wizard_prompt_bad_value:
    lda #<wizard_bad_value_str
    sta zp_ptr0
    lda #>wizard_bad_value_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp wizard_prompt_clear_digits

wizard_bad_value_str:
    .text "BAD" ; .byte 0
ovl_modal_misc_end:
.print "Modal misc overlay: " + (ovl_modal_misc_end - $a800) + " bytes"
.assert "Modal misc overlay fits", ovl_modal_misc_end <= $c000, true

.segment HelpOverlay
#import "../commodore/c128/ui_help_data_80.s"
#import "../../core/ui_help.s"
#import "../../core/ui_identify.s"
ovl_help_end:
.print "Help overlay: " + (ovl_help_end - $a800) + " bytes"
.assert "Help overlay fits", ovl_help_end <= $c000, true

.segment UiOverlay
#import "../../core/ui_character.s"
#import "../../core/ui_inventory.s"
#import "../../core/ui_equipment.s"
ovl_ui_end:
.print "UI overlay: " + (ovl_ui_end - $a800) + " bytes"
.assert "UI overlay fits", ovl_ui_end <= $c000, true

.segment ItemActionsOverlay
#define SCROLL_P3_ROUTER_ENABLED
    #import "../../core/item_actions_overlay.s"

player_adjust_equipment_stat_prepare:
    lda inv_p1,x
    bcs !paes_prepare_store+
    eor #$ff
    clc
    adc #1
!paes_prepare_store:
    sta stat_work
    rts

player_adjust_equipment_stat_apply:
    lda player_data + PL_STR_CUR,x
    clc
    adc stat_work
    sta player_data + PL_STR_CUR,x
    rts

#import "../../core/player_item_commands.s"
#import "../../core/ego_items.s"
#import "../../core/ranged_fire.s"
#import "../../core/throw.s"
#import "../../core/bash.s"
#import "../../core/disarm.s"
#import "../../core/disarm_helpers.s"
#import "../../core/tunnel.s"
ovl_items_end:
.print "Item actions overlay: " + (ovl_items_end - $a800) + " bytes"
.assert "Item actions overlay fits", ovl_items_end <= $c000, true

.segment SpellOverlay
#define SPELL_CLASS_DATA_EXTERNAL
#define SPELL_HELPER_TABLES_EXTERNAL
#import "../../core/spell_data.s"
#undef SPELL_HELPER_TABLES_EXTERNAL
#undef SPELL_CLASS_DATA_EXTERNAL
#define PMX_EARTHQUAKE_EXTERNAL
#define PMX_MAP_AREA_EXTERNAL
#define PMX_MAP_AREA_TRAMPOLINE
#define PMX_DETECT_EFFECTS_EXTERNAL
#define PMX_DESTROY_AREA_EXTERNAL
#import "../../core/player_magic_slow_runtime.s"
#define PMU_TURN_FEEDBACK_ONLY
#import "../../core/player_magic_turn_banked.s"
#undef PMU_TURN_FEEDBACK_ONLY
#import "../../core/player_magic_execute_overlay.s"
#undef PMX_DETECT_EFFECTS_EXTERNAL
#undef PMX_MAP_AREA_TRAMPOLINE
#undef PMX_MAP_AREA_EXTERNAL

    #define SCROLL_P3_EXISTING_OWNER
    #import "../../core/scroll_effects_p3.s"
    #undef SCROLL_P3_EXISTING_OWNER

iq_dispatch_p3_spell:
    cmp #ITEM_TYPE_POT_HEALING
    beq iqp3_healing
    cmp #ITEM_TYPE_POT_RESTORATION
    beq iqp3_restoration
    cmp #ITEM_TYPE_POT_RESIST_HEAT
    beq iqp3_resist_heat
    cmp #ITEM_TYPE_POT_RESIST_COLD
    beq iqp3_resist_cold
    cmp #ITEM_TYPE_POT_CURE_CRITICAL
    beq iqp3_cure_critical
    cmp #ITEM_TYPE_POT_NEUTRALIZE
    beq iqp3_neutralize

iqp3_healing:
    jmp eff_potion_healing          // 1000 HP + cures (eff_potion_cure.s)

iqp3_cure_critical:
    // 6d7 HP, cures blindness, confusion and poison
    lda #EFF_CURE_ALL
    ldx #7
    ldy #6
    jmp eff_potion_heal_cure

iqp3_restoration:
    jsr player_calc_stats
    ldx #HSTR_PIQ_RESTORED
    jmp huff_print_msg

iqp3_resist_heat:
    lda #10
    jsr rng_range
    clc
    adc #10
    clc
    adc zp_eff_resist
    bcc !iqp3_rh_store+
    lda #255
!iqp3_rh_store:
    sta zp_eff_resist
    rts

iqp3_resist_cold:
    lda #10
    jsr rng_range
    clc
    adc #10
    clc
    adc eff_resist_cold_timer
    bcc !iqp3_rc_store+
    lda #255
!iqp3_rc_store:
    sta eff_resist_cold_timer
    rts

iqp3_neutralize:
    jsr eff_cure_poison
    ldx #HSTR_EFF_POISON_END
    jmp huff_print_msg
#undef PMX_DESTROY_AREA_EXTERNAL
#undef PMX_EARTHQUAKE_EXTERNAL
#import "../../core/player_magic_levelup.s"
#import "../../core/player_magic_display.s"
#import "../../core/player_magic_tail.s"
#import "../../core/player_magic_select_overlay.s"
#import "../../core/player_gain_spell_impl.s"
#import "../../core/player_magic_learn_op.s"
ovl_spell_end:
.print "Spell overlay: " + (ovl_spell_end - $a800) + " bytes"
.assert "Spell overlay fits", ovl_spell_end <= $c000, true

.segment DungeonGenOverlay
#import "../../core/special_rooms.s"
#import "../../core/dungeon_tunnel_guard.s"
#import "../../core/dungeon_gen.s"
ovl_gen_end:
.print "Dungeon gen overlay: " + (ovl_gen_end - $a800) + " bytes"
.assert "Dungeon gen overlay fits", ovl_gen_end <= $c000, true

// Sideways RAM cache slot fit assertions
.assert "Beeb SWR UI slot fits payload", ovl_ui_end - BANKED_DATA_BASE <= BEEB_SWR_PAGES_UI * 256, true
.assert "Beeb SWR TOWN slot fits payload", ovl_town_end - BANKED_DATA_BASE <= BEEB_SWR_PAGES_TOWN * 256, true
.assert "Beeb SWR MODAL slot fits payload", ovl_modal_misc_end - BANKED_DATA_BASE <= BEEB_SWR_PAGES_MODAL * 256, true
.assert "Beeb SWR SPELL slot fits payload", ovl_spell_end - BANKED_DATA_BASE <= BEEB_SWR_PAGES_SPELL * 256, true
.assert "Beeb SWR ITEMS slot fits payload", ovl_items_end - BANKED_DATA_BASE <= BEEB_SWR_PAGES_ITEMS * 256, true
.assert "Beeb SWR GEN slot fits payload", ovl_gen_end - BANKED_DATA_BASE <= BEEB_SWR_PAGES_GEN * 256, true
.assert "Huffman corpus fits 4 KB ANDY ($8000-$8FFF)", ovl_huffdata_end <= BEEB_HUFFDATA_LIMIT, true

.segment StorageOverlay
#import "../../platforms/shared/save.s"
#import "save_slot_menu.s"
#import "disk_setup_beeb.s"
ovl_storage_end:
.print "Storage overlay: " + (ovl_storage_end - $a800) + " bytes"
.assert "Storage overlay fits", ovl_storage_end <= $c000, true

.segment TitleOverlay
#import "title_screen.s"
title_show_sysinfo_banked:
    lda #COL_DGREY
    sta zp_text_color
    lda #23
    sta zp_cursor_row
    lda #26                     // Center 80-col: (80-28)/2 = 26
    sta zp_cursor_col
    lda #<beeb_sysinfo_str
    sta zp_ptr0
    lda #>beeb_sysinfo_str
    sta zp_ptr0_hi
    jmp hal_screen_put_string
beeb_sysinfo_str:
    .text "BBC MASTER 128  MOS 3.20 DFS"
    .byte 0
ovl_title_end:
.print "Title overlay: " + (ovl_title_end - $a800) + " bytes"
.assert "Title overlay fits", ovl_title_end <= $c000, true

.segment ChestOverlay
#import "../../core/chest.s"
#import "../../core/store_restock_overlay.s"
ovl_chest_end:
.print "Chest overlay: " + (ovl_chest_end - $a800) + " bytes"
.assert "Chest overlay fits", ovl_chest_end <= $c000, true

// ============================================================
// Ego-item & cross-overlay trampolines (resident)
// ============================================================
.segment Default
tramp_roll_ego_type:
    pha
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !load_failed+
    pla
    jsr roll_ego_type
    rts
!load_failed:
    pla
    lda #0
    rts

tramp_items_dispatch:
    sta tramp_items_jmp+1
    sty tramp_items_jmp+2
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
tramp_items_jmp:
    jmp $0000
!done:
    rts

tramp_spell_call_items:
    lda #OVL_SPELL
    jsr overlay_load
    lda beeb_tsci_arg
tsci_target:
    jsr $0000
    lda #OVL_ITEMS
    jmp overlay_load
hal_tsci_arg:
beeb_tsci_arg: .byte 0

irs_p3_swap_exec:
    pha
    lda #OVL_DEATH
    jsr overlay_load
    pla
    jsr irs_dispatch_p3_overlay
    lda #OVL_ITEMS
    jsr overlay_load
    sec
    rts

tramp_roll_ego_type_modal:
    ldx #OVL_MODAL_MISC
    bne !roll_ego_common+

tramp_roll_ego_type_gen:
    ldx #OVL_DUNGEON_GEN
!roll_ego_common:
    stx ego_restore_ovl+1
    jsr tramp_roll_ego_type
    pha
ego_restore_ovl:
    lda #$00
    jsr overlay_load
    bcc !restored+
    brk
!restored:
    pla
    rts

tramp_ego_apply_damage:
    pha
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !load_failed+
    pla
    jsr ego_apply_damage
    rts
!load_failed:
    pla
    rts

tramp_ego_get_ac_bonus:
    pha
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !load_failed+
    pla
    jsr ego_get_ac_bonus
    rts
!load_failed:
    pla
    lda #0
    rts

tramp_ui_view_restore_spell_overlay:
    jsr ui_view_restore_modal_overlay
    lda #OVL_SPELL
    bne !restore_overlay+

tramp_ui_view_restore_items_overlay:
    jsr ui_view_restore_modal_overlay
    jmp !restore_items+

tramp_combat_check_levelup_items:
    jsr combat_check_levelup
!restore_items:
    lda #OVL_ITEMS
!restore_overlay:
    jsr overlay_load
    bcc !restored+
    brk
!restored:
    rts

tramp_combat_apply_levelup_modal:
    jsr combat_apply_levelup
    lda #OVL_MODAL_MISC
    bne !restore_overlay-

.assert "Window-return trampolines stay resident", tramp_ui_view_restore_spell_overlay >= $0e00 && * <= $8000, true

.segment BeebPlaySlot
tramp_ego_append_suffix:
    beq !teas_done+
    pha
    lda #OVL_ITEMS
    jsr overlay_load
    pla
    bcs !teas_done+
    jsr ego_get_suffix_ptr
    lda zp_ptr0
    ldy zp_ptr0_hi
    jmp combat_append_str
!teas_done:
    rts

beeb_play_end:
.print "BeebPlaySlot: " + (beeb_play_end - $8000) + " bytes"
.assert "Play payload fits slot ($8000-$A3FF)", beeb_play_end <= $a400, true
.assert "Ego suffix trampoline stays in play", tramp_ego_append_suffix >= $8000 && tramp_ego_append_suffix < beeb_play_end, true

// ============================================================
// Final boundary assertions
// ============================================================
.segment Default
program_end:
.print "BBC Master Resident end: $" + toHexString(program_end)
.assert "Resident image fits below $8000", program_end <= $8000, true
.assert "Ego call trampolines stay resident", tramp_roll_ego_type < $8000 && tramp_ego_get_ac_bonus < $8000, true
