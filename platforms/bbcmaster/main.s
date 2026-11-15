#define HAL_PLATFORM_LEGAL_VIEWER
#define HELP_TITLE_EXTERNAL
#define HOME_OVERLAY_SEPARATE
// main.s — Acorn BBC Master 128 moria8 linker script + entry
//
// Assemble from platforms/bbcmaster with:
//   -libdir ../../core -libdir . -libdir hal -libdir ../commodore/common -define BBCMASTER
//
// Memory authority: docs/BBCMASTER_MEMORY_CONTRACT.md.
//   Default (resident): $0E00-$7FFF (low helpers < $3000, resident <= $8000)
//   BeebPlaySlot:       Bank 4 ($04) $8000-$A3FF (play payload, boot-preloaded)
//   Name pool:          Bank 4 ($04) $A400-$A7FF (the catalog's species names)
//   Overlay window:     Bank 4 ($04) $A800-$BFFF (6,144 B)
//   Live 198x66 Map:    Bank 5 ($05) $8000-$B30B + cached OVL.MODAL ($B400-$BFFF)
//   BeebAuxData:        Bank 6 ($06) $8000-$94FF (virt $6000-$74FF), the monster
//                       catalog ($9500-$B9FF) and cached OVL.UI ($BA00-$BFFF)
//   Hot Cache Bank 7:   Bank 7 ($07) cached SPELL/ITEMS/GEN
//   BeebHuffData:       ANDY ($84) $8000-$8D93 (4 KB private RAM)
//   LYNNE Shadow RAM:   ACCCON=$05 $3000-$7FFF (1KB font, 1KB gen scratch, char shadow, Mode 0)

.cpu _65c02

#define BBCMASTER
// The VMS monster catalog (2026-11-05): fields and Huffman names in
// sideways Bank 6 (monster_catalog_beeb.s, cache_layout.s), replacing the
// four tier files.
#define HAL_PLATFORM_MONSTER_CATALOG
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#define HAL_PLATFORM_RECALL_CUSTOM
#define HAL_STORAGE_RECALL_CUSTOM
#define RECALL_ARRAY_DATA_EXTERNAL
#define HAL_PLATFORM_EFF_ITEM_P1_EXTERNAL
#define HAL_PLATFORM_EFF_ITEM_EXTENDED_EXTERNAL
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
.const LEGAL_BASE = $a800
.const LEGAL_LIMIT = $c000
.segmentdef LegalOverlay [outPrg=OVL_OUT + "/legalui", start=$a800, min=$a800, max=$bfff]
.segmentdef HelpOverlay        [outPrg=OVL_OUT + "/ovl.help",     start=$a800, min=$a800, max=$bfff]
.segmentdef UiOverlay          [outPrg=OVL_OUT + "/ovl.ui",       start=$a800, min=$a800, max=$bfff]
.segmentdef ItemActionsOverlay [outPrg=OVL_OUT + "/ovl.items",    start=$a800, min=$a800, max=$bfff]
.segmentdef SpellOverlay       [outPrg=OVL_OUT + "/ovl.spell",    start=$a800, min=$a800, max=$bfff]
.segmentdef DungeonGenOverlay  [outPrg=OVL_OUT + "/ovl.gen",      start=$a800, min=$a800, max=$bfff]
.segmentdef StorageOverlay     [outPrg=OVL_OUT + "/ovl.storage",  start=$a800, min=$a800, max=$bfff]
.segmentdef TitleOverlay       [outPrg=OVL_OUT + "/ovl.title",    start=$a800, min=$a800, max=$bfff]
.segmentdef ChestOverlay       [outPrg=OVL_OUT + "/ovl.chest",    start=$a800, min=$a800, max=$bfff]
.segmentdef HomeOverlay        [outPrg=OVL_OUT + "/ovl.home",     start=$a800, min=$a800, max=$bfff]
.segmentdef BeebPlaySlot       [outPrg=OVL_OUT + "/beeb.play",    start=$8000, min=$8000, max=$a3ff]
.segmentdef BeebAuxData        [outPrg=OVL_OUT + "/beeb.auxdata", start=$6000, min=$6000, max=$74ff]
.segmentdef BeebCatalog        [outPrg=OVL_OUT + "/beeb.catalog", start=$9500, min=$9500, max=$b9ff]
.segmentdef BeebHuffData       [outPrg=OVL_OUT + "/beeb.huffdata",start=$8000, min=$8000, max=$8fff]
.segmentdef BeebLynneAux       [start=$3f80, min=$3f80, max=$43ff, virtual]

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
.const OVL_HOME    = 11
.const OVL_STORAGE = 12
.const OVL_TITLE   = 13
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
#import "legal.s"
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
// Equipment effect flags ride SWR-cached OVL.MODAL behind hal_player_recalc_pflags
// (Phase 2 cold eviction, 2026-11-14) to keep resident Default headroom < $8000.
#define PFLAGS_SEGMENT_CUSTOM
#define PLAYER_RECALC_PFLAGS_EXTERNAL
.macro PflagsSegment() {
    .segment ModalMiscOverlay
}
.macro PflagsRestoreSegment() {
    .segment Default
}
#define PLAYER_STAT_HELPERS_EXTERNAL
#import "../../core/player.s"
#undef PLAYER_STAT_HELPERS_EXTERNAL

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
#define GENERATION_BUSY_INSTALL_EXTERNAL
#import "../../core/generation_busy.s"
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

#import "../../core/recall_defs.s"
#import "monster_catalog_beeb.s"
#import "../../core/monster_catalog.s"
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
// item_spawn_level and chest loot share OVL.CHEST with the item picker so
// OVL.GEN stays within its Bank 7 SWR cache budget.
#define ITEM_SPAWN_IN_GEN_OVERLAY
#define PICKER_IN_CHEST_OVERLAY
.macro ItemSpawnSegment() {
    .segment ChestOverlay
}
.macro ItemSpawnRestoreSegment() {
    .segment Default
}
// roll_enchantment's equipment branch rides SWR-cached OVL.MODAL behind
// tramp_re_equip (Phase 2 cold eviction, 2026-11-14).
#define RE_EQUIP_SEGMENT_CUSTOM
.macro ReEquipSegment() {
    .segment ModalMiscOverlay
}
.macro ReEquipRestoreSegment() {
    .segment Default
}
.label re_equip_entry = tramp_re_equip
.macro ItemPickupSegment() {
    .segment ItemActionsOverlay
}
.macro ItemPickupRestoreSegment() {
    .segment Default
}
#import "../../core/item.s"
// The acid attack's armour damage (MON-015) is resident (Default): the play
// payload has no room for it.
#define MON_ATK_ACID_EXTERNAL
#import "../../core/monster_acid.s"
.macro ChestLootSegment() {
    .segment ChestOverlay
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
#define EFF_FIND_DOORS_EXTERNAL
#import "../../core/spell_effects.s"
#undef EFF_FIND_DOORS_EXTERNAL
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
// Heal feedback and potion heal/cure effects stay resident in Default so both
// OVL.ITEMS and OVL.SPELL reach them directly without touching BeebPlaySlot.
#import "../../core/player_heal_feedback.s"
#import "../../core/eff_potion_cure.s"

#import "../../core/store_data_defs.s"
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

restart_entry:
    jsr detect_machine
    jsr reu_detect
    jsr tier_init
    jsr hal_sound_init
    jsr rng_seed

title_enter_menu:
    lda #OVL_TITLE
    jsr overlay_load
    bcs !tem_draw_menu+
    jsr title_enter_menu_ovl
!tem_draw_menu:
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
    bra title_load_game
!not_l:
    cmp #$41                // A: About, before a character exists
    bne !not_legal_title+
    jsr tramp_ui_legal_display
    bcc !legal_done+
    // No program disk is needed to return to the resident title menu.
    jsr hal_screen_clear
    jsr title_draw_menu
    bra title_menu_loop
!legal_done:
    bra title_enter_menu
!not_legal_title:
    cmp #$44                // 'D' — disk setup
    bne title_menu_loop
    jsr tramp_disk_setup
    bra title_enter_menu

title_draw_menu:
    lda #COL_WHITE
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #(SCREEN_COLS - (title_menu_str_end - title_menu_str)) / 2
    sta zp_cursor_col
    lda #<title_menu_str
    sta zp_ptr0
    lda #>title_menu_str
    sta zp_ptr0_hi
    jmp screen_put_string

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
    lda #OVL_STORAGE
    jsr overlay_load
    bcs !title_load_fail+
    jmp title_load_game_ovl
!title_load_fail:
    jsr input_get_modal_dismiss_key
    bra !legal_done-

// ============================================================
// Generated resident trampolines (tools/trampoline_manifest.py)
// ============================================================
#import "../../build/trampolines/bbcmaster_trampolines.inc"

// ============================================================
// Special rooms dispatcher & item-spawn helper — implementations live in OVL.GEN
// ============================================================
item_spawn_level:
    lda #<item_spawn_level_gen
    ldy #>item_spawn_level_gen
    bra chest_dispatch

gen_dispatch:
    pha
    lda #OVL_DUNGEON_GEN
    bne ovl_dispatch_ay

ui_dispatch:
    pha
    lda #OVL_UI
    bne ovl_dispatch_ay

chest_dispatch:
    pha
    lda #OVL_CHEST
    bne ovl_dispatch_ay

spell_dispatch:
    pha
    lda #OVL_SPELL

ovl_dispatch_ay:
    sty ovl_disp_jmp+2
    tay
    pla
    sta ovl_disp_jmp+1
    tya
    jsr overlay_load
    bcs !done+
ovl_disp_jmp:
    jmp $0000
!done:
    rts

#if !BYPASS_SLOT_PROMPT
save_prepare_slot_prompt:
    lda #OVL_STORAGE
    jmp overlay_load

save_select_slot_prompt:
    jmp save_select_slot_prompt_impl
#endif

// ============================================================
// UI / item / store / spell dispatchers & resident helpers
// ============================================================
.label overlay_load_no_kernal = overlay_load

run_initialize:
    lda #<run_initialize_impl
    ldy #>run_initialize_impl
    bra modal_swap_dispatch

// Resident dispatcher into SWR-cached OVL.MODAL that preserves caller overlay
// (e.g. OVL.GEN for re_equip or OVL.ITEMS/OVL.SPELL for pflags) and returns A.
hal_player_recalc_pflags:
    lda #<player_recalc_pflags_equipment
    ldy #>player_recalc_pflags_equipment
modal_swap_dispatch:
    ldx #OVL_MODAL_MISC
    bra ovl_swap_dispatch_x

// find_special_room is resident (18 B) so both OVL.GEN and OVL.CHEST reach it
// directly; tramp_spawn_nest_gold preserves caller overlay via ovl_swap_dispatch_x.
tramp_find_special_room:
#import "../../core/special_rooms_find.s"

tramp_spawn_nest_gold:
    lda #<spawn_nest_gold
    ldy #>spawn_nest_gold
    ldx #OVL_DUNGEON_GEN
    bra ovl_swap_dispatch_x

// Resident trampolines preserving caller overlay via ovl_swap_dispatch_x.
eff_find_doors:
    lda #<eff_find_doors_impl
    ldy #>eff_find_doors_impl
    bra help_swap_dispatch
eff_destroy_traps_doors:
    lda #<eff_destroy_traps_doors_impl
    ldy #>eff_destroy_traps_doors_impl
help_swap_dispatch:
    ldx #OVL_HELP
ovl_swap_dispatch_x:
    sta osx_jmp+1
    sty osx_jmp+2
    cpx current_overlay
    bne !osx_swap+
osx_jmp:
    jmp $0000
!osx_swap:
    lda current_overlay
    pha
    txa
    jsr overlay_load
    bcs !osx_fail+
    jsr osx_jmp
    php
    sta osx_a+1
    pla
    sta osx_p+1
    pla
    beq !osx_clr+
    jsr overlay_load
    bra !osx_ret+
!osx_clr:
    stz current_overlay
!osx_ret:
osx_p:
    lda #$00
    pha
osx_a:
    lda #$00
    plp
    rts
!osx_fail:
    pla
    lda #0
    sec
    rts

// Resident trampolines into SWR-cached OVL.UI preserving caller A/X/Y/overlay.
player_str_tohit_adj:
    pha
    lda #<bbcm_player_str_tohit_adj
    ldy #>bbcm_player_str_tohit_adj
    bra items_swap_dispatch_a
player_str_damage_adj:
    pha
    lda #<bbcm_player_str_damage_adj
    ldy #>bbcm_player_str_damage_adj
    bra items_swap_dispatch_a
player_dex_tohit_adj:
    pha
    lda #<bbcm_player_dex_tohit_adj
    ldy #>bbcm_player_dex_tohit_adj
    bra items_swap_dispatch_a
player_dex_ac_adj:
    pha
    lda #<bbcm_player_dex_ac_adj
    ldy #>bbcm_player_dex_ac_adj
    bra items_swap_dispatch_a
player_con_hp_adj:
    pha
    lda #<bbcm_player_con_hp_adj
    ldy #>bbcm_player_con_hp_adj
items_swap_dispatch_a:
    sta isda_jmp+1
    sty isda_jmp+2
    pla
    sta isda_arg+1
    stx isda_x+1
    lda current_overlay
    cmp #OVL_UI
    bne !isda_swap+
    sty isda_fast_y+1
isda_arg:
    lda #$00
    jsr isda_jmp
    ldx isda_x+1
isda_fast_y:
    ldy #$00
    rts
isda_jmp:
    jmp $0000
!isda_swap:
    pha
    sty isda_y+1
    lda #OVL_UI
    jsr overlay_load
    bcs !isda_fail+
    lda isda_arg+1
    jsr isda_jmp
    sta isda_arg+1
    pla
    beq !isda_clr+
    jsr overlay_load
    bra !isda_ret+
!isda_clr:
    stz current_overlay
!isda_ret:
    lda isda_arg+1
isda_x:
    ldx #$00
isda_y:
    ldy #$00
    rts
!isda_fail:
    pla
    rts

// ============================================================
// Media prompts (1-drive swap mode only)
// ============================================================
disk_prompt_save:
    lda #<disk_prompt_save_impl
    ldy #>disk_prompt_save_impl
    bra !dp_common+

disk_prompt_game:
    lda #<disk_prompt_game_impl
    ldy #>disk_prompt_game_impl
!dp_common:
    ldx disk_mode
    cpx #1                      // 1-drive swap mode
    beq !dp_load+
    clc
    rts
!dp_load:
    pha
    lda #OVL_STORAGE
    jmp ovl_dispatch_ay

// ============================================================
// Death orchestration
// ============================================================
tramp_winner_royal:
    lda #OVL_DEATH
    jsr overlay_load
    bcs !done+
    jsr winner_apply_retirement_bonus_overlay
    jmp royal_screen
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
#import "../../core/recall.s"
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
    .segment ItemActionsOverlay
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
    .segment ModalMiscOverlay
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
#import "../../core/ui_restore.s"

tramp_do_look:
    lda #OVL_MODAL_MISC
    jsr overlay_load_no_kernal
    bcs !done+
    jsr do_look
!done:
    jmp tramp_sr_epilogue

.segment Default
.assert "Play payload starts with 3-byte signature", beeb_play_body - beeb_play_start, 3

// ============================================================
// BeebLynneAux segment — LYNNE Shadow RAM $3F80-$43FF (ACCCON=$05, virtual)
// Zero-initialized at boot and New Game; accessed via hal_recall_*_byte.
// ============================================================
.segment BeebLynneAux
.label recall_data_start = *
.fill RECALL_DATA_SIZE, 0
.label recall_data_end = *
beeb_lynne_aux_end:
.print "BeebLynneAux: " + (beeb_lynne_aux_end - BEEB_LYNNE_AUX_BASE) + " bytes"
.assert "BeebLynneAux stays within $3F80-$43FF", recall_data_start >= BEEB_LYNNE_AUX_BASE && recall_data_end - recall_data_start == RECALL_DATA_SIZE && beeb_lynne_aux_end <= BEEB_LYNNE_AUX_LIMIT, true

// ============================================================
// BeebAuxData segment — Virtual $6000-$74FF -> Bank 6 Physical $8000-$94FF
// ============================================================
.segment BeebAuxData
#import "../../core/store_inventory_data.s"
#import "../../core/spell_class_data.s"
#define STORE_HOT_DATA_EXTERNAL
#import "../../core/store_runtime_data.s"
#undef STORE_HOT_DATA_EXTERNAL
#import "../../core/spell_helper_tables.s"
#import "../../core/spell_names.s"

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
.assert "BeebAuxData fits $6000-$72FF (19 pages: ITEMCAT Slots 0..1 & catalog follow in Bank 6)", ovl_auxdata_end <= $6000 + BEEB_CACHE_AUX_PAGES * $100, true

.segment Default
turn_rest_disturbed: .byte 0

// ============================================================
// Overlay segment blocks ($A800-$BFFF in Bank 4)
// ============================================================
.segment TownOverlay
#import "../../core/store.s"
#import "../../core/ui_store.s"
inv_add_carried:                    // the store's (HAL_PLATFORM_INV_ADD_CARRIED_EXTERNAL)
    :InvAddCarriedBody()
ovl_town_end:
.print "Town overlay: " + (ovl_town_end - $a800) + " bytes"
.assert "Town overlay fits window", ovl_town_end <= $c000, true

.segment HomeOverlay
#import "../../core/ui_home.s"
#import "../../core/ui_home_text.s"
#import "../../core/eff_item_p1.s"
#import "../../core/eff_item_extended.s"
ovl_home_end:
.print "Home overlay: " + (ovl_home_end - $a800) + " bytes"
.assert "Home overlay fits window", ovl_home_end <= $c000, true

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
    :GoldCapOnCarry()               // 250,000 more stops at 16,777,215
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
#import "../../core/royal.s"

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
#import "../../core/ui_help_title.s"
#import "../commodore/c128/ui_help_data_80.s"
#import "../../core/ui_help.s"
#import "../../core/ui_identify.s"

// Relocated spell helpers (EFF_FIND_DOORS_EXTERNAL / EFF_DESTROY_TRAPS_DOORS_EXTERNAL)
eff_fd_row: .byte 0

eff_find_doors_impl:
    lda #1
    sta eff_fd_row
!efd_row_loop:
    lda eff_fd_row
    cmp #MAP_ROWS - 1
    bcs !efd_done+
    ldx eff_fd_row
    jsr map_row_ptr0_x
    ldy #1
!efd_col_loop:
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    bne !efd_col_next+
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_CLOSED
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
!efd_col_next:
    iny
    cpy #MAP_COLS - 1
    bcc !efd_col_loop-
    inc eff_fd_row
    jmp !efd_row_loop-
!efd_done:
    lda #1
    sta vis_room_revealed
    rts

eff_destroy_traps_doors_impl:
    lda #0
    sta adj_dir_idx
!edtd_tile_loop:
    lda adj_dir_idx
    cmp #8
    bcs !edtd_tiles_done+
    tax
    jsr df_target_from_dir
    jsr !edtd_tile_cb+
    inc adj_dir_idx
    jmp !edtd_tile_loop-
!edtd_tiles_done:
    jsr !edtd_remove_adjacent_traps+
    lda #1
    sta vis_room_revealed
    rts

!edtd_tile_cb:
    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    sta zp_temp0
    cmp #TILE_TRAP
    bne !edtd_check_door+
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_FLOOR
    :MapWrite_ptr0_y()
    rts

!edtd_check_door:
    lda zp_temp0
    cmp #TILE_DOOR_CLOSED
    beq !edtd_open_door+
    cmp #TILE_SECRET
    bne !edtd_tile_done+

!edtd_open_door:
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_OPEN
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
    lda df_target_x
    ldy df_target_y
    jsr door_state_clear_at
!edtd_tile_done:
    rts

!edtd_remove_adjacent_traps:
    ldx #0
!edtd_scan:
    cpx trap_count
    bcs !edtd_scan_done+
    lda trap_x,x
    sec
    sbc zp_player_x
    clc
    adc #1
    cmp #3
    bcs !edtd_scan_next+
    lda trap_y,x
    sec
    sbc zp_player_y
    clc
    adc #1
    cmp #3
    bcs !edtd_scan_next+
    lda trap_x,x
    cmp zp_player_x
    bne !edtd_remove+
    lda trap_y,x
    cmp zp_player_y
    beq !edtd_scan_next+

!edtd_remove:
    dec trap_count
    ldy trap_count
    lda trap_x,y
    sta trap_x,x
    lda trap_y,y
    sta trap_y,x
    lda trap_type,y
    sta trap_type,x
    jmp !edtd_scan-

!edtd_scan_next:
    inx
    jmp !edtd_scan-

!edtd_scan_done:
    rts

ovl_help_end:
.print "Help overlay: " + (ovl_help_end - $a800) + " bytes"
.assert "Help overlay fits", ovl_help_end <= $c000, true

.segment UiOverlay
#import "../../core/ui_character.s"
#import "../../core/ui_inventory.s"
#import "../../core/ui_equipment.s"

// Player stat adjustment helpers (PLAYER_STAT_HELPERS_EXTERNAL) in SWR OVL.UI
bbcm_player_str_tohit_adj:
    ldx #0
    ldy #3
    bra !padj_go+
bbcm_player_str_damage_adj:
    ldx #8
    ldy #10
    bra !padj_go+
bbcm_player_dex_tohit_adj:
    ldx #17
    ldy #20
    bra !padj_go+
bbcm_player_dex_ac_adj:
    ldx #26
    ldy #30
    bra !padj_go+
bbcm_player_con_hp_adj:
    cmp #7
    bcs !con7+
    sec
    sbc #7
    rts
!con7:
    ldx #36
    ldy #36
!padj_go:
    cmp #$ff
    bcc !padj_lp+
    lda #$fe
!padj_lp:
    cmp bbcm_padj_tbl,x
    bcc !padj_done+
    inx
    bra !padj_lp-
!padj_done:
    sty padj_sub + 1
    txa
    sec
padj_sub:
    sbc #$00
    rts

bbcm_padj_tbl:
    .byte 4, 5, 7, 18, 94, 109, 117, $ff
    .byte 4, 5, 16, 17, 18, 94, 109, 117, $ff
    .byte 4, 6, 8, 16, 17, 18, 69, 118, $ff
    .byte 4, 5, 6, 7, 15, 18, 59, 94, 117, $ff
    .byte 17, 18, 94, 117, $ff

ovl_ui_end:
.print "UI overlay: " + (ovl_ui_end - $a800) + " bytes"
.assert "UI overlay fits", ovl_ui_end <= $c000, true

.segment ItemActionsOverlay
#define SCROLL_P3_ROUTER_ENABLED
    #import "../../core/item_actions_overlay.s"
    #import "../../core/item_exchange.s"
inv_add_carried_items:              // the floor pickup's, through tramp_inv_add_carried
    :InvAddCarriedBody()
.segment BeebPlaySlot
// tramp_inv_add_carried — the resident floor pickup's way to inv_add_carried
// (ovl.items); the play slot holds it, the resident image being full. An
// overlay that will not load refuses the item, which stays on the floor.
tramp_inv_add_carried:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !tiac_fail+
    jmp inv_add_carried_items
!tiac_fail:
    ldx #HSTR_UIS_PACK_FULL
    clc
    rts
.segment ItemActionsOverlay

player_adjust_equipment_stat:
    // As core/player_adjust_equipment_stat.s: the stat by the item
    // (equip_stat_index, core/player.s), p1 added or taken away.
    jsr player_adjust_equipment_stat_prepare
    jsr equip_stat_index
    bcc !paes_done+
    jmp player_adjust_equipment_stat_apply   // Y = the stat
!paes_done:
    rts

player_adjust_equipment_stat_prepare:
    lda inv_p1,x
    bcs !paes_prepare_store+
    eor #$ff
    adc #1                      // carry clear: -p1
!paes_prepare_store:
    sta stat_work
    rts

player_adjust_equipment_stat_apply:
    lda player_data + PL_STR_CUR,y
    clc
    adc stat_work
    sta player_data + PL_STR_CUR,y
    rts

#import "../../core/player_item_commands.s"
#import "../../core/ego_items.s"
#import "../../core/ranged_fire.s"
#import "../../core/throw.s"
#import "../../core/bash.s"
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
#import "../../core/wand_bolt_entries.s"   // the Fire Bolts and Drain Life entries (OVL.SPELL)
#undef PMX_DETECT_EFFECTS_EXTERNAL
#undef PMX_MAP_AREA_TRAMPOLINE
#undef PMX_MAP_AREA_EXTERNAL

    #define SCROLL_P3_EXISTING_OWNER
    #import "../../core/scroll_effects_p3.s"
    #undef SCROLL_P3_EXISTING_OWNER
    #define EFF_DESTROY_TRAPS_DOORS_EXTERNAL
    #import "../../core/spell_effects_overlay.s"
    #undef EFF_DESTROY_TRAPS_DOORS_EXTERNAL

    #import "../../core/eff_gain_stat.s"

iq_dispatch_p3_spell:
    .assert "Phase 3 potions 96..100 contiguous below 126 < 140", ITEM_TYPE_POT_RESTORATION == ITEM_TYPE_POT_HEALING + 1 && ITEM_TYPE_POT_RESIST_HEAT == ITEM_TYPE_POT_HEALING + 2 && ITEM_TYPE_POT_RESIST_COLD == ITEM_TYPE_POT_HEALING + 3 && ITEM_TYPE_POT_CURE_CRITICAL == ITEM_TYPE_POT_HEALING + 4 && ITEM_TYPE_POT_CURE_CRITICAL < ITEM_TYPE_POT_NEUTRALIZE && ITEM_TYPE_POT_NEUTRALIZE < ITEM_TYPE_POT_GAIN_STR, true
    cmp #ITEM_TYPE_POT_GAIN_STR
    bcs eff_potion_gain_stat        // potions of gain stat (140-145)
    cmp #ITEM_TYPE_POT_RESTORATION
    bcc iqp3_healing
    beq iqp3_restoration
    cmp #ITEM_TYPE_POT_RESIST_COLD
    bcc iqp3_resist_heat
    beq iqp3_resist_cold
    cmp #ITEM_TYPE_POT_NEUTRALIZE
    beq iqp3_neutralize

iqp3_cure_critical:
    // 6d7 HP, cures blindness, confusion and poison
    lda #EFF_CURE_ALL
    ldx #7
    ldy #6
    jmp eff_potion_heal_cure

iqp3_healing:
    jmp eff_potion_healing          // 1000 HP + cures (eff_potion_cure.s)

iqp3_restoration:
    jsr player_calc_stats
    ldx #HSTR_PIQ_RESTORED
    bra !iqp3_msg+

iqp3_resist_heat:
    ldx #zp_eff_resist
    bne !iqp3_add_resist+
iqp3_resist_cold:
    ldx #eff_resist_cold_timer
!iqp3_add_resist:
    phx
    lda #10
    jsr rng_range
    plx
    sec                             // + 1: VMS randint(10) + 10 = 11..20 (C=0)
    adc #10
    adc $00,x
    bcc !iqp3_store+
    lda #255
!iqp3_store:
    sta $00,x
    rts

iqp3_neutralize:
    jsr eff_cure_poison
    ldx #HSTR_EFF_POISON_END
!iqp3_msg:
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
.assert "Beeb SWR MODAL slot fits payload", ovl_modal_misc_end - BANKED_DATA_BASE <= BEEB_SWR_PAGES_MODAL * 256, true
.assert "Beeb SWR SPELL slot fits payload", ovl_spell_end - BANKED_DATA_BASE <= BEEB_SWR_PAGES_SPELL * 256, true
.assert "Beeb SWR ITEMS slot fits payload", ovl_items_end - BANKED_DATA_BASE <= BEEB_SWR_PAGES_ITEMS * 256, true
.assert "Beeb SWR GEN slot fits payload", ovl_gen_end - BANKED_DATA_BASE <= BEEB_SWR_PAGES_GEN * 256, true
.assert "Huffman corpus fits 4 KB ANDY ($8000-$8FFF)", ovl_huffdata_end <= BEEB_HUFFDATA_LIMIT, true
.assert "Huffman corpus fits below ANDY zp_save_buf ($8F00)", ovl_huffdata_end <= BEEB_ZP_SAVE_BASE, true
.assert "zp_save_buf fits ANDY top below $9000", zp_save_buf + ZP_SAVE_SIZE <= BEEB_HUFFDATA_LIMIT, true

.segment StorageOverlay
#import "../../platforms/shared/save.s"
#import "save_slot_menu.s"
#import "disk_setup_beeb.s"
title_load_game_ovl:
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
ovl_storage_end:
.print "Storage overlay: " + (ovl_storage_end - $a800) + " bytes"
.assert "Storage overlay fits", ovl_storage_end <= $c000, true

.segment TitleOverlay
#import "title_screen.s"
generation_busy_install:
    lda #$4c
    sta generation_busy_begin_api
    sta generation_busy_tick_api
    sta generation_busy_end_api

    lda #<generation_busy_begin
    sta generation_busy_begin_api + 1
    lda #>generation_busy_begin
    sta generation_busy_begin_api + 2

    lda #<generation_busy_tick
    sta generation_busy_tick_api + 1
    lda #>generation_busy_tick
    sta generation_busy_tick_api + 2

    lda #<generation_busy_end
    sta generation_busy_end_api + 1
    lda #>generation_busy_end
    sta generation_busy_end_api + 2

    lda #0
    sta generation_busy_active_api
    rts

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

title_enter_menu_ovl:
    jsr generation_busy_install
    jsr platform_services_install_beeb
    jsr platform_services_assert_installed
    lda #$ff
    sta save_slot_index
    lda #COL_LGREY
    sta zp_text_color
    jsr title_clear_full_screen
    jsr title_load_and_draw
    jsr title_clear_below_menu
    jsr msg_init
    jsr title_show_sysinfo_banked
    rts

title_str:
    .text "MORIA 8 (BBC MASTER)"
    .byte 0

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
#import "../../core/disarm.s"
#import "../../core/disarm_helpers.s"
#import "../../core/store_restock_overlay.s"
ovl_chest_end:
.print "Chest overlay: " + (ovl_chest_end - $a800) + " bytes"
.assert "Chest overlay fits", ovl_chest_end <= $c000, true

// ============================================================
// Ego-item & cross-overlay trampolines (resident)
// ============================================================
.segment Default
tramp_items_dispatch:
    pha
    lda #OVL_ITEMS
    jmp ovl_dispatch_ay

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
    bra !roll_ego_common+

tramp_roll_ego_type_gen:
    ldx current_overlay
!roll_ego_common:
    stx ego_restore_ovl+1
    jsr tramp_roll_ego_type
    pha
ego_restore_ovl:
    lda #$00
    beq !rest_clr+
    jsr overlay_load
    bcc !restored+
    brk
!rest_clr:
    stz current_overlay
!restored:
    pla
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

tramp_eff_item_p1:
    lda #<eff_item_p1_exec
    ldy #>eff_item_p1_exec
    bne !tcho_run+
tramp_eff_ext_eat:
    lda #<eff_ext_eat_piw
    ldy #>eff_ext_eat_piw
    bne !tcho_run+
tramp_eff_ext_quaff:
    lda #<eff_ext_quaff_piw
    ldy #>eff_ext_quaff_piw
!tcho_run:
    ldx #OVL_HOME
    jmp ovl_swap_dispatch_x

.assert "Window-return trampolines stay resident", tramp_ui_view_restore_spell_overlay >= $0e00 && * <= $8000, true

.segment BeebPlaySlot
tramp_ego_append_suffix:
    beq !teas_done+
    cmp #EGO_TYPE_COUNT
    bcs !teas_done+
    jsr item_cat_decode_ego
    lda zp_ptr0
    ldy zp_ptr0_hi
    jmp combat_append_str
!teas_done:
    rts

beeb_play_end:
.print "BeebPlaySlot: " + (beeb_play_end - $8000) + " bytes"
.assert "Play payload fits slot ($8000-$A3FF)", beeb_play_end <= $a400, true
.assert "Ego suffix trampoline stays in play", tramp_ego_append_suffix >= $8000 && tramp_ego_append_suffix < beeb_play_end, true
.assert "Look trampoline runs in play", tramp_do_look >= $8000 && tramp_do_look < beeb_play_end, true
.assert "Equipment stat helper runs in OVL.ITEMS", player_adjust_equipment_stat >= $a800 && player_adjust_equipment_stat < ovl_items_end, true

// ============================================================
// Final boundary assertions
// ============================================================
.segment Default
program_end:
.print "BBC Master Resident end: $" + toHexString(program_end)
.assert "Resident image fits below $8000", program_end <= $8000, true
.assert "beeb_icat_page_slot matches ITMCAT_TOTAL_SIZE pages", beeb_icat_slot_hi - beeb_icat_page_slot, floor((ITMCAT_TOTAL_SIZE + 255) / 256)
.assert "Ego call trampolines stay resident", tramp_roll_ego_type < $8000 && tramp_ego_get_ac_bonus < $8000, true
.assert "Home overlay owns home_enter separately from TownOverlay", home_enter >= $a800 && home_enter < ovl_home_end && home_inv_add_carried >= $a800 && home_inv_add_carried < ovl_home_end && store_enter >= $a800 && store_enter < ovl_town_end && inv_add_carried >= $a800 && inv_add_carried < ovl_town_end, true
.assert "Death overlay owns royal_screen", royal_screen >= $a800 && royal_screen < ovl_death_end, true
.assert "Phase 2 evicted trampolines stay resident while targets live in overlays", re_equip_entry < $8000 && re_equip >= $a800 && re_equip < ovl_modal_misc_end && hal_player_recalc_pflags < $8000 && player_recalc_pflags_equipment >= $a800 && player_recalc_pflags_equipment < ovl_modal_misc_end && run_initialize < $8000 && run_initialize_impl >= $a800 && run_initialize_impl < ovl_modal_misc_end && title_load_game_ovl >= $a800 && title_load_game_ovl < ovl_storage_end && title_enter_menu_ovl >= $a800 && title_enter_menu_ovl < ovl_title_end, true

// Cold legal modal: workspace is reserved but not emitted to disk.
.segment LegalOverlay
#import "../../core/ui_legal.s"
#import "../shared/legal_disk_stream.s"
legal_code_end:
.assert "Legal code stays below its modal workspace", legal_code_end <= legal_zp_save, true
.assert "Legal ZP snapshot stays below input cache", legal_zp_save + $8e <= legal_input_cache, true
.segment Default
