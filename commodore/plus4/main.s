// main.s — Entry point for Moria8 Plus/4
//
// BASIC stub at $1001 with SYS entry.
// Saves BASIC ZP state, disables BASIC ROM, runs game,
// restores state and exits cleanly to BASIC.

// ============================================================
// BASIC stub — SYS 2062 ($080E)
// ============================================================
// Overlay segments: produce separate PRGs at $E000.
// Assembled in same pass as main program — full symbol access.
// Only ONE overlay is active at a time (they share $E000-$EFFF).
#define PLUS4_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_PRODUCT_OVERLAY_RUNTIME
#define STORAGE_STATUS_HELPER
.segmentdef StartupOverlay    [outPrg="out/ovl.start", start=$e000, min=$e000, max=$efff]
.segmentdef TownOverlay       [outPrg="out/ovl.town",  start=$e000, min=$e000, max=$efff]
.segmentdef DeathOverlay      [outPrg="out/ovl.death", start=$e000, min=$e000, max=$efff]
.segmentdef HelpOverlay       [outPrg="out/ovl.help",  start=$e000, min=$e000, max=$efff]
.segmentdef UiOverlay         [outPrg="out/ovl.ui",    start=$e000, min=$e000, max=$efff]
.segmentdef ItemActionsOverlay [outPrg="out/ovl.items", start=$e000, min=$e000, max=$efff]
.segmentdef SpellOverlay      [outPrg="out/ovl.spell", start=$e000, min=$e000, max=$efff]
.segmentdef DungeonGenOverlay [outPrg="out/ovl.gen",   start=$e000, min=$e000, max=$efff]
.segmentdef RuntimeBanked     [outPrg="out/4.bank",    start=$f000, min=$f000, max=$ff00]

.const TED_BG      = $ff15
.const TED_BORDER  = $ff19
.const TED_SOUND_CTRL = $ff11
.const PLUS4_EXIT_ROM_ENABLE = $ff3e
.const PLUS4_EXIT_TED_IRQ_STATUS = $ff09
.const PLUS4_KERNAL_RESTOR = $ff8a
.const PLUS4_KERNAL_RESET = $f2a4
.const BASIC_TXTTAB_LO = $2b
.const BASIC_TXTTAB_HI = $2c
.const BASIC_VARTAB_LO = $2d
.const BASIC_VARTAB_HI = $2e
.const BASIC_ARYTAB_LO = $2f
.const BASIC_ARYTAB_HI = $30
.const BASIC_STREND_LO = $31
.const BASIC_STREND_HI = $32
.const PLUS4_BASIC_START_LO = $01
.const PLUS4_BASIC_START_HI = $10
.const PLUS4_KEYSCAN_STATE = $ef
.const PLUS4_KEY_INDEX = $055d
.const PLUS4_KEY_INDEX_SHADOW = $055e
.const PLUS4_ROM_RESET_REBUILD_FLAG = $0508
.const PLUS4_ROM_RESET_REBUILD_FLAG_2 = $0509

.pc = $1001 "BASIC Stub"
.word basic_stub_end
.word 10
.byte $9e
.text "4110"
.byte 0
basic_stub_end:
.word 0

// ============================================================
// Imports — order matters: labels must be defined before use
// ============================================================
.pc = $100e "Program"

// Bootstrap — MUST live below $A000 so BASIC's SYS can reach it
// before BASIC ROM is banked out.
entry:
    sei
    jsr plus4_bank_ram
    jmp entry_main

// Exit trampoline — MUST live below $A000 because it banks Plus/4
// ROM back in. If this ran from $A000+ the CPU would start executing
// BASIC ROM as soon as $FF3E makes ROM visible.
exit_trampoline:
    sei
    lda #$ff
    sta PLUS4_EXIT_ROM_ENABLE
    lda #0
    sta PLUS4_EXIT_TED_IRQ_STATUS
    jsr PLUS4_KERNAL_RESTOR
    ldx #$ff
    txs
    lda #PLUS4_BASIC_START_LO
    sta BASIC_TXTTAB_LO
    lda #PLUS4_BASIC_START_HI
    sta BASIC_TXTTAB_HI
    lda #0
    sta BASIC_VARTAB_LO
    sta BASIC_VARTAB_HI
    sta BASIC_ARYTAB_LO
    sta BASIC_ARYTAB_HI
    sta BASIC_STREND_LO
    sta BASIC_STREND_HI
    sta PLUS4_KEYSCAN_STATE
    sta PLUS4_KEY_INDEX
    sta PLUS4_KEY_INDEX_SHADOW
    sta PLUS4_ROM_RESET_REBUILD_FLAG
    sta PLUS4_ROM_RESET_REBUILD_FLAG_2
    jmp PLUS4_KERNAL_RESET

#import "../common/zeropage.s"

plus4_kernal_call_saved_bank: .byte 0

plus4_kernal_call:
    pha
    txa
    pha
    tya
    pha
    tsx
    lda $0104,x
    sta zp_vol_2
    lda $0105,x
    sta zp_vol_3
    clc
    lda $0104,x
    adc #2
    sta $0104,x
    bcc !cdc_target+
    inc $0105,x
!cdc_target:
    ldy #1
    lda (zp_vol_2),y
    sta !cdc_jsr+ + 1
    iny
    lda (zp_vol_2),y
    sta !cdc_jsr+ + 2
    pla
    tay
    pla
    tax
    pla
    jsr plus4_bank_rom
    cli
!cdc_jsr:
    jsr $ffff
    php
    pha
    tsx
    lda $0102,x
    ora #$04                    // Return to all-RAM game code with IRQs disabled.
    sta $0102,x
    sei
    jsr plus4_bank_ram
    jsr plus4_display_resync
    pla
    plp
    rts

plus4_kernal_setnam:
    jsr plus4_kernal_call
    .word $ffbd
    rts

plus4_kernal_setlfs:
    jsr plus4_kernal_call
    .word $ffba
    rts

plus4_kernal_open:
    jsr plus4_kernal_call
    .word $ffc0
    rts

plus4_kernal_close:
    jsr plus4_kernal_call
    .word $ffc3
    rts

plus4_kernal_chkout:
    jsr plus4_kernal_call
    .word $ffc9
    rts

plus4_kernal_chkin:
    jsr plus4_kernal_call
    .word $ffc6
    rts

plus4_kernal_clrchn:
    jsr plus4_kernal_call
    .word $ffcc
    rts

plus4_kernal_chrin:
    jsr plus4_kernal_call
    .word $ffcf
    rts

plus4_kernal_chrout:
    jsr plus4_kernal_call
    .word $ffd2
    rts

plus4_kernal_readst:
    jsr plus4_kernal_call
    .word $ffb7
    rts

plus4_kernal_load:
    jsr plus4_kernal_call
    .word $ffd5
    rts

#import "hal/storage.s"

plus4_storage_marker_present:
    lda #1
    sta disk_status
    lda #$81                    // DISK_ERR_MARKER_OPEN
    jsr disk_error_set_phase
    jsr plus4_kernal_clrchn
    lda #hal_storage_marker_file_num
    jsr plus4_kernal_close
    lda #hal_storage_marker_read_name_len
    ldx #<hal_storage_marker_read_name
    ldy #>hal_storage_marker_read_name
    jsr plus4_kernal_setnam
    lda #hal_storage_marker_file_num
    ldx save_device
    ldy #hal_storage_marker_sec_read
    jsr plus4_kernal_setlfs
    jsr plus4_kernal_open
    bcc !cdmp_open_ok+
    sta disk_error_readst
    jmp !cdmp_close+
!cdmp_open_ok:
    jsr plus4_kernal_readst
    sta disk_error_readst
    beq !cdmp_chkin+
    jmp !cdmp_close+
!cdmp_chkin:
    lda #$82                    // DISK_ERR_MARKER_CHKIN
    jsr disk_error_set_phase
    ldx #hal_storage_marker_file_num
    jsr plus4_kernal_chkin
    bcc !cdmp_chkin_ok+
    sta disk_error_readst
    jmp !cdmp_close+
!cdmp_chkin_ok:
    lda #$83                    // DISK_ERR_MARKER_READ
    jsr disk_error_set_phase
    lda #0
    sta disk_temp
!cdmp_read:
    jsr plus4_kernal_chrin
    sta disk_error_actual
    ldx disk_temp
    lda hal_storage_marker_magic,x
    sta disk_error_expect
    stx disk_error_index
    cmp disk_error_actual
    bne !cdmp_close+
    jsr plus4_kernal_readst
    sta disk_error_readst
    beq !cdmp_byte_ok+
    cmp #$40
    bne !cdmp_close+
    ldx disk_temp
    cpx #hal_storage_marker_magic_len - 1
    bne !cdmp_close+
!cdmp_byte_ok:
    inc disk_temp
    lda disk_temp
    cmp #hal_storage_marker_magic_len
    bcc !cdmp_read-
    dec disk_status
!cdmp_close:
    lda #hal_storage_marker_file_num
    jsr plus4_kernal_close
    jsr plus4_kernal_clrchn
!cdmp_done:
    lda disk_status
    beq !cdmp_status_done+
    jsr plus4_disk_read_command_status
!cdmp_status_done:
    lda disk_status
    beq !cdmp_ok+
    sec
    rts
!cdmp_ok:
    jsr disk_error_clear
    clc
    rts

// tramp_dig_ability — pinned low for common tunnel code.
tramp_dig_ability:
    jmp calc_dig_ability

// All .text directives produce screen codes (not PETSCII) since
// all output uses direct screen RAM writes at $0400+.
.encoding "screencode_mixed"

.const DUNGEON_GEN_BUSY = 1

#import "../common/zeropage.s"
#import "memory.s"
#import "hal/layout.s"
#import "hal/lifecycle_policy.s"
#import "reu_stub.s"
#import "screen.s"
#import "../common/color.s"
#import "config.s"
#import "input.s"
#import "../common/rng.s"
#import "../common/math.s"
#import "../common/tables.s"
#import "../common/item_defs.s"
#import "../common/player.s"
#import "../common/ui_messages.s"
#import "../common/ui_status.s"
#import "../common/generation_busy.s"
#import "../common/stat_display.s"
#import "sound.s"
#import "../common/huffman.s"
#import "../common/dungeon_data.s"
#import "../common/dungeon_features.s"
#import "../common/monster.s"
#import "../common/tier_manager.s"
#define OVERLAY_LOAD_PROMPT_GAME
#import "../common/overlay.s"
#undef OVERLAY_LOAD_PROMPT_GAME
#import "../common/monster_ai.s"
#import "../common/recall.s"
#import "../common/monster_magic.s"
#import "../common/item.s"
#define ITEM_ACTIONS_OVERLAY_EXTERNAL
#import "../common/player_items.s"
#import "../common/spell_data.s"
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../common/spell_effects.s"
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../common/player_magic_state.s"
#import "../common/player_magic_state_ops.s"
#import "../common/player_magic.s"
#import "dungeon_render.s"
#import "../common/dungeon_los.s"
#import "../common/player_move.s"
#define PMU_TURN_FEEDBACK_EXTERNAL
#import "../common/combat.s"
#undef PMU_TURN_FEEDBACK_EXTERNAL
#import "../common/projectile.s"
#import "../common/monster_attack.s"
#import "../common/turn.s"
#import "../common/store_data.s"
#import "../common/runtime_ui_strings.s"
#import "../common/compat/io_kernal_consts.s"
#import "../common/save.s"
#import "hal/storage_policy.s"
#import "../common/disk_swap.s"
#import "../common/score_io.s"
#import "../common/title_screen.s"
#import "../common/wizard.s"
#import "../common/game_loop.s"
#import "hal/storage.s"

// Resident helper for Plus/4 save-disk marker creation. It must execute from
// visible RAM while KERNAL is banked in; the $F000 runtime is hidden then.
plus4_storage_marker_write_resident:
    lda #2
    sta disk_status
    lda #DISK_ERR_MARKER_WRITE_OPEN
    jsr disk_error_set_phase
    jsr plus4_kernal_clrchn
    lda #hal_storage_marker_file_num
    jsr plus4_kernal_close
    // Disk Setup already scratched any stale marker; create a fresh marker.
    lda #hal_storage_marker_write_name_len - 1
    ldx #<(hal_storage_marker_write_name + 1)
    ldy #>(hal_storage_marker_write_name + 1)
    jsr plus4_kernal_setnam
    lda #hal_storage_marker_file_num
    ldx save_device
    ldy #hal_storage_marker_sec_write
    jsr plus4_kernal_setlfs
    jsr plus4_kernal_open
    bcc !cdmw_open_ok+
    sta disk_error_readst
    jmp !cdmw_close+
!cdmw_open_ok:
    lda #DISK_ERR_MARKER_CHKOUT
    jsr disk_error_set_phase
    ldx #hal_storage_marker_file_num
    jsr plus4_kernal_chkout
    bcc !cdmw_chkout_ok+
    sta disk_error_readst
    jmp !cdmw_close+
!cdmw_chkout_ok:
    lda #DISK_ERR_MARKER_WRITE
    jsr disk_error_set_phase
    lda #0
    sta disk_temp
!cdmw_write:
    ldx disk_temp
    lda hal_storage_marker_magic,x
    stx disk_error_index
    jsr plus4_kernal_chrout
    jsr plus4_kernal_readst
    sta disk_error_readst
    bne !cdmw_close+
    inc disk_temp
    lda disk_temp
    cmp #hal_storage_marker_magic_len
    bcc !cdmw_write-
    lda #0
    sta disk_status
!cdmw_close:
    jsr plus4_kernal_clrchn
    lda #hal_storage_marker_file_num
    jsr plus4_kernal_close
    lda disk_status
    bne !cdmw_status_done+
    jsr plus4_disk_read_command_status
!cdmw_status_done:
    lda disk_status
    beq !cdmw_ok+
    sec
    rts
!cdmw_ok:
    jsr disk_error_clear
    clc
    rts

plus4_disk_read_command_status:
    lda #0
    sta disk_error_dos0
    sta disk_error_dos1
    ldx #0
    ldy #0
    jsr plus4_kernal_setnam
    lda #hal_storage_cmd_channel
    ldx save_device
    ldy #hal_storage_cmd_channel
    jsr plus4_kernal_setlfs
    jsr plus4_kernal_open
    bcs !p4dcs_done+
    ldx #hal_storage_cmd_channel
    jsr plus4_kernal_chkin
    bcs !p4dcs_close+
    jsr plus4_kernal_chrin
    sta disk_error_dos0
    jsr plus4_kernal_readst
    sta disk_error_readst
    jsr plus4_kernal_chrin
    sta disk_error_dos1
    jsr plus4_kernal_readst
    sta disk_error_readst
    jsr plus4_disk_status_to_disk_status
!p4dcs_close:
    jsr plus4_kernal_clrchn
    lda #hal_storage_cmd_channel
    jsr plus4_kernal_close
!p4dcs_done:
    rts

plus4_disk_status_to_disk_status:
    lda disk_error_dos0
    cmp #$30                    // "0"
    bne !check_26+
    lda disk_error_dos1
    cmp #$30                    // "0"
    bne !done+
    lda #0
    sta disk_error_dos0
    sta disk_error_dos1
    rts
!check_26:
    lda disk_error_dos0
    cmp #$32                    // "2"
    bne !check_72+
    lda disk_error_dos1
    cmp #$36                    // "6"
    bne !done+
    lda #26
    sta disk_status
    rts
!check_72:
    cmp #$37                    // "7"
    bne !done+
    lda disk_error_dos1
    cmp #$32                    // "2"
    bne !check_74+
    lda #72
    sta disk_status
    rts
!check_74:
    cmp #$34                    // "4"
    bne !done+
    lda #74
    sta disk_status
!done:
    rts

// ============================================================
// Entry point
// ============================================================
entry_main:
    // Save BASIC's zero page state so we can restore on exit
    jsr save_zp
    jsr disk_reset_session_state
    jsr plus4_install_ram_irq_vectors

    // BASIC ROM already banked out by bootstrap above

    // Load banked runtime payload to $F000 before any $F000 trampoline calls.
    jsr init_load_banked

    jsr generation_busy_install
    jsr plus4_platform_services_install
    jsr platform_services_assert_installed
    jsr input_lock_charset_switch

    lda #COL_BLACK
    tax
    lda plus4_color_attr,x
    sta TED_BORDER
    sta TED_BG

restart_entry:
    // --- Initialize subsystems ---
    jsr detect_machine
    lda #0
    sta reu_present
    sta reu_banks
    sta reu_size_kb
    sta reu_size_kb + 1
    jsr tier_init
    jsr hal_sound_init
    jsr rng_seed

title_enter_menu:
    // Set default text color
    lda #COL_LGREY
    sta zp_text_color

    // Clear screen now so stale status bar (rows 21–23) from any prior session
    // is gone before KERNAL LOAD starts printing "SEARCHING...".
    // title_load_and_draw also clears after KERNAL LOAD to remove those messages.
    jsr screen_clear

    // Load and display title (clears screen internally after KERNAL LOAD)
    jsr title_load_and_draw

    // Explicitly clear status rows 21–23 before sysinfo draws on row 23.
    // title_load_and_draw + KERNAL LOAD together may leave stale status bar
    // data in those rows (e.g. from title_render_data parsing MAP_BASE).
    lda #STATUS_ROW             // row 21
    jsr screen_clear_row
    lda #STATUS_ROW + 1         // row 22
    jsr screen_clear_row
    lda #STATUS_ROW + 2         // row 23
    jsr screen_clear_row

    // Title re-entry must rebuild message/title UI state from scratch after
    // any failed load attempt, not just branch back into the old loop.
    jsr msg_init

    // Show system info on row 23 (machine type, KERNAL rev, REU)
    jsr title_show_sysinfo

    jsr title_draw_menu
    jsr plus4_title_clear_lower_rows

#if PLUS4_TEST_SCRIPTED_OVERLAY_LOAD_PRODUCT
    jsr plus4_test_overlay_load_all
#endif

#if PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || PLUS4_TEST_SCRIPTED_LOAD_WRONG_MEDIA_PRODUCT
    ldx #9
    jsr hal_storage_probe_media
    lda #9
    sta save_device
    lda #2
    sta disk_mode
    lda #1
    sta disk_setup_done
#endif

title_menu_loop:
    jsr input_get_key
    cmp #$4e                // 'N' — new game
    bne !not_n+
    jmp game_new_start
!not_n:
    cmp #$4c                // 'L' — load game
    bne !not_l+
    lda disk_setup_done
    bne !load_now+
    jsr tramp_disk_setup
    bcs plus4_title_redraw_cached
!load_now:
    jmp title_load_game
!not_l:
    cmp #$44                // 'D' — disk setup
    bne title_menu_loop
    jsr tramp_disk_setup
    jmp plus4_title_redraw_cached

plus4_title_redraw_cached:
    lda plus4_title_art_cached
    beq title_enter_menu
    lda #COL_LGREY
    sta zp_text_color
    jsr screen_clear
    jsr title_render_data
    lda #STATUS_ROW
    jsr screen_clear_row
    lda #STATUS_ROW + 1
    jsr screen_clear_row
    lda #STATUS_ROW + 2
    jsr screen_clear_row
    jsr msg_init
    jsr title_show_sysinfo
    jsr title_draw_menu
    jsr plus4_title_clear_lower_rows
    jmp title_menu_loop

title_draw_menu:
    // --- Show title menu: N)EW  L)OAD  D)ISK SETUP ---
    lda #COL_WHITE
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #7                  // Center: (40-25)/2 ~= 7
    sta zp_cursor_col
    lda #<title_menu_str
    sta zp_ptr0
    lda #>title_menu_str
    sta zp_ptr0_hi
    jsr screen_put_string
    rts

plus4_title_clear_lower_rows:
    lda #COL_BLACK
    sta zp_text_color
    lda #20
    sta plus4_title_clear_row
!clear:
    lda plus4_title_clear_row
    jsr screen_clear_row
    inc plus4_title_clear_row
    lda plus4_title_clear_row
    cmp #SCREEN_ROWS
    bcc !clear-
    rts

plus4_title_clear_row: .byte 0
plus4_title_art_cached: .byte 0

#if PLUS4_TEST_SCRIPTED_OVERLAY_LOAD_PRODUCT
plus4_test_overlay_load_all:
    lda #OVL_STARTUP
    sta plus4_test_overlay_id
!loop:
    lda plus4_test_overlay_id
    jsr overlay_load
    bcs plus4_test_overlay_load_fail_sym
    inc plus4_test_overlay_id
    lda plus4_test_overlay_id
    cmp #(OVL_COUNT + 1)
    bcc !loop-
plus4_test_overlay_load_pass_sym:
    jmp plus4_test_overlay_load_pass_sym
plus4_test_overlay_load_fail_sym:
    jmp plus4_test_overlay_load_fail_sym

plus4_test_overlay_id:
    .byte 0
#endif

title_load_game:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr hal_sound_play
    jsr disk_prompt_save        // Swap to save disk if dual
    jsr ui_clear_full_screen_safe
    jsr ui_reset_message_state
    jsr load_game
    php
    jsr disk_prompt_game        // Swap back for tier loading
    plp
    // Fail closed on the explicit load carry result before resuming gameplay.
    bcc !title_load_fail+
    jmp load_resume_game
!title_load_fail:
    jsr input_get_modal_dismiss_key
    jsr disk_prompt_game        // Swap back for tier loading after dismissal
    jmp title_enter_menu

// ============================================================
// IRQ wedge — suppress KERNAL cursor blink
// Forces $CC non-zero before KERNAL IRQ handler checks it.
// Must live in main RAM (always accessible during IRQ).
// ============================================================
irq_no_blink:
    cld
irq_no_blink_after_cld:
    rti

// plus4_irq_hidden_rom — IRQ/NMI handler for all-RAM mode.
// If an interrupt leaks through while Plus/4 ROM is hidden, CPU vectors read
// RAM at $FFFA/$FFFE. Return without touching KERNAL ROM, which is not visible
// in that banking mode.
plus4_irq_hidden_rom:
    lda TED_IRQ_STATUS
    sta TED_IRQ_STATUS
    rti

plus4_install_ram_irq_vectors:
    php
    sei
    jsr plus4_bank_ram
    lda #0
    sta TED_IRQ_ENABLE
    lda TED_IRQ_STATUS
    sta TED_IRQ_STATUS
    lda #<plus4_irq_hidden_rom
    sta $fffa
    sta $fffe
    lda #>plus4_irq_hidden_rom
    sta $fffb
    sta $ffff
    plp
    rts

.label hal_irq_install_runtime = plus4_install_ram_irq_vectors

// ============================================================
// kernal_load_safe — KERNAL LOAD wrapper for Plus/4
// ============================================================
kernal_load_safe:
    jsr plus4_kernal_load   // KERNAL LOAD — carry set on error
    php                     // Preserve carry for caller
    jsr plus4_platform_runtime_resync
    plp
    rts

// ============================================================
// Dungeon gen overlay trampoline — bank KERNAL out, call $E000 overlay
// ============================================================
// KERNAL must be off ($34) while executing overlay code at $E000.
// IRQs must stay DISABLED for the entire overlay execution:
//   - tramp_level_generate holds sei from entry to exit
//   - inner trampolines (tramp_assign_special_room, tramp_vault_seal_entrance,
//     verify_connectivity) use php/plp to preserve the caller's interrupt state
//     instead of cli, so IRQs remain disabled throughout dungeon generation
tramp_level_generate:
    sei
    jsr plus4_bank_ram
    jsr level_generate          // executes from DungeonGenOverlay at $E000
    jsr plus4_bank_ram
    rts

// ============================================================
// Special rooms trampolines — SEI + bank out KERNAL, call $F000+
// ============================================================
tramp_assign_special_room:
    php                         // Save interrupt state (caller may be in sei context)
    sei
    jsr plus4_bank_ram
    jsr assign_special_room
    jsr plus4_bank_ram
    plp                         // Restore interrupt state (no cli — would re-enable IRQs with $01=$34)
    rts

tramp_vault_seal_entrance:
    php                         // Save interrupt state (caller may be in sei context)
    sei
    jsr plus4_bank_ram
    jsr vault_seal_entrance
    jsr plus4_bank_ram
    plp                         // Restore interrupt state
    rts

tramp_spawn_special_room_monsters:
    sei
    jsr plus4_bank_ram
    jsr spawn_special_room_monsters
    jmp tramp_sr_epilogue

tramp_spawn_nest_gold:
    sei
    jsr plus4_bank_ram
    jsr spawn_nest_gold
    jmp tramp_sr_epilogue

tramp_find_special_room:
    pha                         // Save A (room type input)
    sei
    jsr plus4_bank_ram
    pla                         // Restore A
    jsr find_special_room
    // Carry flag preserved — lda/sta don't affect carry
    jmp tramp_sr_epilogue

tramp_sr_epilogue:
    jmp plus4_platform_runtime_resync

// ============================================================
// Ego item trampolines — SEI + bank out KERNAL, call $F000+
// ============================================================
tramp_roll_ego_type:
    pha                         // Save A (item type input)
    sei
    jsr plus4_bank_ram
    pla                         // Restore A
    jsr roll_ego_type
    pha                         // Save result
    jsr plus4_bank_ram
    pla                         // Restore result
    rts

// tramp_ego_append_suffix — Append ego suffix to combat_msg_buf
// Input: A = ego type
// Copies suffix string from $F000 region to combat_msg_buf while banked out.
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1
tramp_ego_append_suffix:
    cmp #0
    beq !teas_done+             // No ego → nothing to append
    pha
    sei
    jsr plus4_bank_ram
    pla
    jsr ego_get_suffix_ptr      // zp_ptr0 = suffix string (in $F000)
    // Copy string to combat_msg_buf (while banked out so we can read $F000)
    ldx cmb_buf_idx
    ldy #0
!teas_loop:
    lda (zp_ptr0),y
    beq !teas_end+
    sta combat_msg_buf,x
    inx
    iny
    cpx #COMBAT_MSG_BUF_LAST    // Buffer overflow protection
    bcs !teas_end+
    jmp !teas_loop-
!teas_end:
    stx cmb_buf_idx
    jsr plus4_bank_ram
!teas_done:
    rts

// ============================================================
// tramp_ego_apply_damage — Apply ego slay/bonus damage (banked at $F000)
// Input: A = ego type (1-7), cmb_damage and cmb_type set
// Output: cmb_damage updated
// Clobbers: A, X, Y, zp_math_a/b, zp_temp3, zp_temp4
tramp_ego_apply_damage:
    pha
    sei
    jsr plus4_bank_ram
    pla
    jsr ego_apply_damage
    jsr plus4_bank_ram
    rts

// tramp_ego_get_ac_bonus — Get ego AC bonus (banked at $F000)
// Input: A = ego type (1-7)
// Output: A = AC bonus (0 if none)
// Clobbers: X
tramp_ego_get_ac_bonus:
    pha
    sei
    jsr plus4_bank_ram
    pla
    jsr ego_get_ac_bonus
    pha
    jsr plus4_bank_ram
    pla
    rts


// Init-only strings — kept in main RAM (small, referenced by title_screen.s)
// ============================================================
title_str:
    .text "MORIA8 PLUS/4" ; .byte 0

// title_show_sysinfo — Trampoline to call banked version at $F000
// Reads KERNAL_REV while KERNAL is still banked in, then banks out.
title_show_sysinfo:
    rts
tsi_krev_cached: .byte 0

// tramp_reu_show_status — Bank out KERNAL to call banked status display
// Patched into reu_show_status at startup by init code.
tramp_reu_show_status:
    rts

plus4_platform_main_loop_begin:
plus4_platform_vector_reassert:
plus4_platform_runtime_resync:
    sei
    jsr plus4_bank_ram
    jmp plus4_display_resync

plus4_platform_services_install:
    lda #$4c
    sta platform_main_loop_begin_api
    sta platform_vector_reassert_api
    sta platform_runtime_resync_api

    lda #<plus4_platform_main_loop_begin
    sta platform_main_loop_begin_api + 1
    lda #>plus4_platform_main_loop_begin
    sta platform_main_loop_begin_api + 2

    lda #<plus4_platform_vector_reassert
    sta platform_vector_reassert_api + 1
    lda #>plus4_platform_vector_reassert
    sta platform_vector_reassert_api + 2

    lda #<plus4_platform_runtime_resync
    sta platform_runtime_resync_api + 1
    lda #>plus4_platform_runtime_resync
    sta platform_runtime_resync_api + 2

    jmp platform_services_mark_installed

#import "../common/ui_help_clear.s"

// ============================================================
// UI screen trampolines — help and modal UI load from $E000 overlays
// ============================================================
overlay_load_no_kernal:
    pha
    pla
    jsr overlay_load
    bcs !done+
    sei
    jsr plus4_install_ram_irq_vectors
    jsr plus4_bank_ram
!done:
    rts

tramp_ui_help_display:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcc !loaded+
    jmp tramp_sr_epilogue
!loaded:
    lda #<help_pages
    sta help_pages_src_lo
    lda #>help_pages
    sta help_pages_src_hi
    jsr ui_help_display
    jmp tramp_sr_epilogue

tramp_ui_char_display:
    lda #OVL_UI
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_char_display
!done:
    jmp tramp_sr_epilogue

tramp_ui_inv_display:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_inv_display
!done:
    jmp tramp_sr_epilogue

tramp_ui_inv_select_display:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_inv_select_display
!done:
    jmp tramp_sr_epilogue

tramp_ui_equip_display:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_equip_display
!done:
    jmp tramp_sr_epilogue

tramp_ui_equip_select_display:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_equip_select_display
!done:
    jmp tramp_sr_epilogue

tramp_ui_recall:
    lda #OVL_DEATH
    jsr overlay_load_no_kernal
    bcs !done+
    sei
    jsr plus4_bank_ram
    jsr ui_recall_display
!done:
    jmp tramp_sr_epilogue

tramp_item_gain_spell:
    lda #OVL_UI
    jsr overlay_load_no_kernal
    bcs !done+
    jsr item_gain_spell
!done:
    jmp tramp_sr_epilogue

tramp_item_read_scroll:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr item_read_scroll
!done:
    jmp tramp_sr_epilogue

tramp_item_aim_wand:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr item_aim_wand
!done:
    jmp tramp_sr_epilogue

tramp_item_use_staff:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr item_use_staff
!done:
    jmp tramp_sr_epilogue

tramp_eff_earthquake:
    sei
    jsr plus4_bank_ram
    jsr eff_earthquake_banked
    rts

tramp_item_refuel:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr item_refuel
!done:
    jmp tramp_sr_epilogue

tramp_ranged_fire:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ranged_fire
!done:
    jmp tramp_sr_epilogue

tramp_throw_item:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr throw_item
!done:
    jmp tramp_sr_epilogue

tramp_bash_command:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr bash_command
!done:
    jmp tramp_sr_epilogue

tramp_player_tunnel:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr player_tunnel
!done:
    jmp tramp_sr_epilogue

tramp_spell_list_display:
    lda #OVL_UI
    jsr overlay_load_no_kernal
    bcs !done+
    jsr spell_list_display
!done:
    jmp tramp_sr_epilogue

tramp_spell_execute_selected:
    lda #OVL_SPELL
    jsr overlay_load_no_kernal
    bcs !done+
    jsr spell_execute_selected
!done:
    jmp tramp_sr_epilogue

tramp_reveal_floorplan:
    lda #OVL_SPELL
    jsr overlay_load_no_kernal
    bcs !done+
    jsr eff_reveal_floorplan
!done:
    jmp tramp_sr_epilogue

tramp_ui_identify:
    lda #OVL_UI
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_identify_print
    jsr plus4_bank_ram
    jsr tier_restore_after_overlay
!done:
    jmp tramp_sr_epilogue

tramp_ui_wizard_display:
    jmp wizard_40col_menu_display

tramp_disk_setup:
    lda #OVL_HELP
    jsr overlay_load
    bcs !tds_done+
    sei
    jsr plus4_bank_ram
    jsr disk_setup_run
    jmp tramp_sr_epilogue

!tds_done:
    rts



// ============================================================
// Store overlay trampolines — load overlay, bank out KERNAL, call $E000+
// ============================================================
// Shared preamble: ensure town overlay is loaded, then bank out KERNAL
store_overlay_preamble:
    lda #OVL_TOWN
    jsr overlay_load
    sei
    jsr plus4_bank_ram
    rts

tramp_store_init_all:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr store_init_all
!done:
    jmp tramp_sr_epilogue

tramp_store_restock_all:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr store_restock_all
!done:
    jmp tramp_sr_epilogue

tramp_store_enter:
    jsr store_overlay_preamble
    jsr store_enter
    jmp tramp_sr_epilogue

#if C64_TEST_SCRIPTED_BOOK_OVERLAY || C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY
test_expect_screen_string:
    sta test_expect_row
    stx test_expect_col
    ldx test_expect_row
    lda screen_row_lo,x
    clc
    adc test_expect_col
    sta zp_ptr2
    lda screen_row_hi,x
    adc #0
    sta zp_ptr2_hi
    ldy #0
!tes_loop:
    lda (zp_ptr0),y
    beq !tes_ok+
    cmp (zp_ptr2),y
    bne !tes_fail+
    iny
    bne !tes_loop-
!tes_fail:
    clc
    rts
!tes_ok:
    sec
    rts

test_expect_row: .byte 0
test_expect_col: .byte 0

.encoding "screencode_mixed"
test_inventory_title_str: .text "Inventory" ; .byte 0
test_beginner_book_str:   .text "Beginner's Spellbook" ; .byte 0
test_mage_book_title_str: .text "Mage Book" ; .byte 0
test_magic_missile_str:   .text "Magic Missile" ; .byte 0
test_phase_door_str:      .text "Phase Door" ; .byte 0

#if C64_TEST_SCRIPTED_BOOK_OVERLAY
test_assert_book_overlay:
    lda #<test_inventory_title_str
    sta zp_ptr0
    lda #>test_inventory_title_str
    sta zp_ptr0_hi
    lda #0
    ldx #15
    jsr test_expect_screen_string
    bcc !book_fail+

    lda #<test_beginner_book_str
    sta zp_ptr0
    lda #>test_beginner_book_str
    sta zp_ptr0_hi
    lda #2
    ldx #4
    jsr test_expect_screen_string
    bcc !book_fail+

    jmp c64_test_book_overlay_pass_sym
!book_fail:
    jmp c64_test_book_overlay_fail_sym
#endif

#if C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY
test_assert_spell_list_overlay:
    lda #<test_mage_book_title_str
    sta zp_ptr0
    lda #>test_mage_book_title_str
    sta zp_ptr0_hi
    lda #0
    ldx #14
    jsr test_expect_screen_string
    bcc !list_fail+

    lda #<test_magic_missile_str
    sta zp_ptr0
    lda #>test_magic_missile_str
    sta zp_ptr0_hi
    lda #2
    ldx #4
    jsr test_expect_screen_string
    bcc !list_fail+

    lda #<test_phase_door_str
    sta zp_ptr0
    lda #>test_phase_door_str
    sta zp_ptr0_hi
    lda #4
    ldx #4
    jsr test_expect_screen_string
    bcc !list_fail+

    jmp c64_test_spell_list_overlay_pass_sym
!list_fail:
    jmp c64_test_spell_list_overlay_fail_sym
#endif
#endif

#if C64_TEST_SCRIPTED_SPELL
c64_test_spell_fail_no_cast_sym:
    brk
c64_test_spell_fail_level_sym:
    brk
c64_test_spell_fail_known_sym:
    brk
c64_test_spell_fail_validate_sym:
    brk
c64_test_spell_fail_roll_sym:
    brk
c64_test_spell_fail_cancel_sym:
    brk
c64_test_spell_fail_input_sym:
    brk
c64_test_spell_pass_sym:
    brk
#else
#if C64_TEST_SCRIPTED_BOOK_OVERLAY
c64_test_book_overlay_fail_sym:
    brk
c64_test_book_overlay_fail_input_sym:
    brk
c64_test_book_overlay_pass_sym:
    brk
#else
#if C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY
c64_test_spell_list_overlay_fail_sym:
    brk
c64_test_spell_list_overlay_fail_input_sym:
    brk
c64_test_spell_list_overlay_pass_sym:
    brk
#else
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
c64_test_spell_fail_no_cast_sym:
    brk
c64_test_spell_fail_level_sym:
    brk
c64_test_spell_fail_known_sym:
    brk
c64_test_spell_fail_validate_sym:
    brk
c64_test_spell_fail_roll_sym:
    brk
c64_test_spell_fail_cancel_sym:
    brk
c64_test_spell_fail_input_sym:
    brk
c64_test_spell_pass_sym:
    brk
#else
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
c64_test_spell_fail_no_cast_sym:
    brk
c64_test_spell_fail_level_sym:
    brk
c64_test_spell_fail_known_sym:
    brk
c64_test_spell_fail_validate_sym:
    brk
c64_test_spell_fail_roll_sym:
    brk
c64_test_spell_fail_cancel_sym:
    brk
c64_test_spell_fail_input_sym:
    brk
c64_test_spell_pass_sym:
    brk
#endif
#endif
#endif
#endif
#endif

// ============================================================
// Startup overlay trampoline — load overlay, bank out KERNAL, call $E000+
// ============================================================
tramp_player_create:
    lda #OVL_STARTUP
    jsr overlay_load
    sei
    jsr plus4_bank_ram
    jsr player_create
    jmp tramp_sr_epilogue

// ============================================================
// Death overlay trampoline — orchestrates the full game-over sequence
// ============================================================
// Interleaves overlay calls ($E000, $01=$34) with KERNAL I/O ($01=$36).
// Pre-resolves creature name before overlay overwrites tier data.
tramp_game_over:
    lda death_source_saved
    sta zp_death_source

    // 1. Resolve death source text while tier data still at $E000
    lda zp_death_source
    cmp #DEATH_TRAP_PIT         // Special sources ($F9-$FF) don't need name
    bcs !tgo_load_overlay+
    tax
    jsr creature_get_name       // Copies name to creature_name_buf in main RAM

!tgo_load_overlay:
    // 2. Load death overlay (replaces tier data at $E000)
    lda #OVL_DEATH
    jsr overlay_load

    // 3. Calculate score (overlay code, no KERNAL needed)
    sei
    jsr plus4_bank_ram
    jsr score_calculate
    jsr plus4_bank_ram

    // 4. Load high scores from disk (main RAM, needs KERNAL)
    jsr hiscore_load

    // 5. Insert into high score table (overlay code)
    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    bne !tgo_skip_hiscore+
    sei
    jsr plus4_bank_ram
    jsr hiscore_insert
    jsr plus4_bank_ram

    // 6. Save high scores to disk (main RAM, needs KERNAL)
    jsr hiscore_save
!tgo_skip_hiscore:
    lda death_source_saved
    sta zp_death_source

    // 7. Display death screen (overlay code)
    sei
    jsr plus4_bank_ram
    jsr score_death_screen
    jsr plus4_bank_ram
    rts

// ============================================================
// game_over_prompt — return to title/menu after save, quit, or death.
// Shown at all exit points (save+quit, voluntary quit, death).
// ============================================================
game_over_prompt:
    jmp game_restart

// ============================================================
// game_restart — reset game state, return to title screen
// Clears mutable state (ZP vars, inventory, tier), then jumps
// to restart_entry (skipping one-time init_copy_banked etc.).
// ============================================================
game_restart:
    // Clear ZP game variables $2B–$8F (player stats, turn counter,
    // effect timers, monster counts, etc.)
    lda #0
    ldx #0
!clr_zp:
    sta zp_player_x,x
    inx
    cpx #(zp_entropy - zp_player_x + 1) // 101 bytes
    bne !clr_zp-

    // Clear static game-state variables in data segments
    lda #0
    sta eff_fear_timer
    ldx #3
!clr_recall:
    sta recall_query_sc,x
    dex
    bpl !clr_recall-

    // Clear inventory: inv_item_id[] = FI_EMPTY ($FF), qty/p1/flags = $00
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

    // Reset tier state (zp_current_tier already zeroed above)
    sta current_tier
    sta tier_loaded

    jmp restart_entry

// Safety: ensure runtime code doesn't overlap runtime data areas
program_end:
.assert "Program fits below MAP_BASE", program_end <= MAP_BASE, true

// ============================================================
// Init-only code below — lives past CREATURE_BASE, safe because
// it runs once at startup before dungeon map or RLE workspace
// are used. Overwritten during normal gameplay.
// ============================================================

// init_load_banked — Load banked runtime payload to $F000.
// Called once at startup before any $F000 trampoline is used.
// Clobbers: A, X, Y
init_load_banked:
    lda #plus4_banked_fname_len
    ldx #<plus4_banked_fname
    ldy #>plus4_banked_fname
    jsr plus4_kernal_setnam
    lda #2
    ldx program_device
    ldy #1                      // Use PRG header address ($F000)
    jsr plus4_kernal_setlfs
    lda #0
    ldx #$00
    ldy #$f0
    jsr plus4_kernal_load
    php
    lda #2
    jsr plus4_kernal_close
    jsr plus4_kernal_clrchn
    plp
    bcs !load_failed+
    rts
!load_failed:
    lda plus4_color_attr + COL_RED
    sta TED_BORDER
    jmp !load_failed-

plus4_banked_fname:
    .byte $34,$2e,$42,$41,$4e,$4b  // "4.BANK"
.label plus4_banked_fname_len = * - plus4_banked_fname

// ============================================================
// Banked runtime payload — loadable PRG at $F000.
// ============================================================
.segment RuntimeBanked
    #import "../common/special_rooms.s"
    #import "../common/ego_items.s"
    #import "../common/ui_home.s"
    #import "../common/item_desc_banked.s"
    #import "../common/disk_setup_banked.s"

save_append_disk_detail_plus4:
    lda #$20
    jsr screen_put_char
    lda disk_error_dos0
    bne !dos+
    lda disk_error_phase
    ora disk_error_readst
    bne !status+
    rts
!dos:
    lda disk_error_dos0
    jsr screen_put_char
    lda disk_error_dos1
    jmp screen_put_char
!status:
    lda #$24                    // $
    jsr screen_put_char
    lda disk_error_readst
    jsr screen_put_hex
    lda #$2f                    // /
    jsr screen_put_char
    lda #$24                    // $
    jsr screen_put_char
    lda disk_error_phase
    jmp screen_put_hex

    #import "../common/player_magic_learn_op.s"
    #import "../common/player_magic_map.s"
    #import "../common/player_magic_turn_banked.s"
    #import "../common/player_magic_slow_runtime.s"
    #define PM_EQ_BANKED
    #import "../common/player_magic_earthquake.s"
    #undef PM_EQ_BANKED

banked_code_end:

.print "Banked runtime: " + (banked_code_end - $f000) + " bytes at $F000-$" + toHexString(banked_code_end)
.assert "Banked code fits below TED ROM helper page", banked_code_end <= $FF00, true

// ============================================================
// Town overlay — store code at $E000, output to separate PRG
// ============================================================
// This segment produces out/ovl_town (loaded from disk as OVL.TOWN).
// Labels resolve to $E000+ but bytes go to the overlay PRG file,
// not the main moria.prg. All main RAM symbols are accessible.
.segment TownOverlay
    #import "../common/store.s"
    #import "../common/ui_store.s"
    #import "../common/ui_home_text.s"
ovl_town_end:
.print "Town overlay: " + (ovl_town_end - $e000) + " bytes at $E000-$" + toHexString(ovl_town_end)
.assert "Town overlay fits in $E000-$EFFF", ovl_town_end <= $F000, true

// ============================================================
// Startup overlay — character creation at $E000, output to separate PRG
// ============================================================
// This segment produces out/ovl_start (loaded from disk as OVL.START).
// Used once during new game, then replaced by town/death overlays.
.segment StartupOverlay
    #import "../common/background_data.s"
    #import "../common/player_create.s"
ovl_start_end:
.print "Startup overlay: " + (ovl_start_end - $e000) + " bytes at $E000-$" + toHexString(ovl_start_end)
.assert "Startup overlay fits in $E000-$EFFF", ovl_start_end <= $F000, true

// ============================================================
// Death overlay — score + high score display at $E000
// ============================================================
// This segment produces out/ovl_death (loaded from disk as OVL.DEATH).
// Used once at game over. Contains scoring math, death screen display,
// and high score insertion/display. KERNAL I/O stays in score_io.s.
.segment DeathOverlay
    #import "../common/score.s"
    #import "../common/ui_recall.s"
ovl_death_end:
.print "Death overlay: " + (ovl_death_end - $e000) + " bytes at $E000-$" + toHexString(ovl_death_end)
.assert "Death overlay fits in $E000-$EFFF", ovl_death_end <= $F000, true

// ============================================================
// Spell overlay — spell/prayer execution at $E000
// ============================================================
.segment SpellOverlay
    #define PMX_EARTHQUAKE_EXTERNAL
    #define PMX_MAP_AREA_EXTERNAL
    #define PMU_VISIBLE_FLAGGED_EXTERNAL
    #import "../common/player_magic_execute_overlay.s"
    #undef PMU_VISIBLE_FLAGGED_EXTERNAL
    #undef PMX_MAP_AREA_EXTERNAL
    #undef PMX_EARTHQUAKE_EXTERNAL
ovl_spell_end:
.print "Spell overlay: " + (ovl_spell_end - $e000) + " bytes at $E000-$" + toHexString(ovl_spell_end)
.assert "Spell overlay fits in $E000-$EFFF", ovl_spell_end <= $F000, true

// ============================================================
// Help overlay — dedicated help modal screen at $E000
// ============================================================
.segment HelpOverlay
    #import "../common/ui_help_data.s"
    #import "../common/ui_help_page2_data.s"
    #import "../common/ui_help.s"
    #import "../common/ui_inventory.s"
    #import "../common/ui_equipment.s"
    #import "../common/ui_disk_setup.s"
ovl_help_end:
.print "Help overlay: " + (ovl_help_end - $e000) + " bytes at $E000-$" + toHexString(ovl_help_end)
.assert "Help overlay fits in $E000-$EFFF", ovl_help_end <= $F000, true

// ============================================================
// UI overlay — low-frequency modal UI and symbol identify screens
// ============================================================
.segment UiOverlay
    #import "../common/ui_character.s"
    #import "../common/ui_identify.s"
    #import "../common/spell_names.s"
    #import "../common/player_magic_select_overlay.s"
    #import "../common/player_gain_spell_impl.s"
ovl_ui_end:
.print "UI overlay: " + (ovl_ui_end - $e000) + " bytes at $E000-$" + toHexString(ovl_ui_end)
.assert "UI overlay fits in $E000-$EFFF", ovl_ui_end <= $F000, true

// ============================================================
// Item actions overlay — low-frequency read/aim/use/refuel commands
// ============================================================
.segment ItemActionsOverlay
    #import "../common/store_restock_overlay.s"
    #import "../common/item_actions_overlay.s"
    #import "../common/ranged_fire.s"
    #import "../common/throw.s"
    #import "../common/bash.s"
    #import "../common/tunnel.s"
ovl_items_end:
.print "Items overlay: " + (ovl_items_end - $e000) + " bytes at $E000-$" + toHexString(ovl_items_end)
.assert "Items overlay fits in $E000-$EFFF", ovl_items_end <= $F000, true

// ============================================================
// Dungeon generation overlay — town + dungeon generation at $E000
// ============================================================
// This segment produces out/ovl.gen (loaded from disk as OVL.GEN).
// Loaded on demand whenever stairs are used or a new game starts.
// Shared constants and data tables stay in dungeon_data.s (main segment).
.segment DungeonGenOverlay
    #import "../common/dungeon_gen.s"
ovl_gen_end:
.print "DungeonGen overlay: " + (ovl_gen_end - $e000) + " bytes at $E000-$" + toHexString(ovl_gen_end)
.assert "DungeonGen overlay fits in $E000-$EFFF", ovl_gen_end <= $F000, true
.assert "irq_no_blink begins with CLD", irq_no_blink_after_cld == irq_no_blink + 1, true
