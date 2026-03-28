// main.s — Entry point for Moria8 C64/C128
//
// BASIC stub at $0801 with SYS entry.
// Saves BASIC ZP state, disables BASIC ROM, runs game,
// restores state and exits cleanly to BASIC.

// ============================================================
// BASIC stub — SYS 2062 ($080E)
// ============================================================
// Overlay segments: produce separate PRGs at $E000.
// Assembled in same pass as main program — full symbol access.
// Only ONE overlay is active at a time (they share $E000-$EFFF).
.segmentdef StartupOverlay    [outPrg="out/ovl.start", start=$e000, min=$e000, max=$efff]
.segmentdef TownOverlay       [outPrg="out/ovl.town",  start=$e000, min=$e000, max=$efff]
.segmentdef DeathOverlay      [outPrg="out/ovl.death", start=$e000, min=$e000, max=$efff]
.segmentdef HelpOverlay       [outPrg="out/ovl.help",  start=$e000, min=$e000, max=$efff]
.segmentdef UiOverlay         [outPrg="out/ovl.ui",    start=$e000, min=$e000, max=$efff]
.segmentdef DungeonGenOverlay [outPrg="out/ovl.gen",   start=$e000, min=$e000, max=$efff]

.pc = $0801 "BASIC Stub"
:BasicUpstart2(entry)

// ============================================================
// Imports — order matters: labels must be defined before use
// ============================================================
.pc = $080e "Program"

// Bootstrap — MUST live below $A000 so BASIC's SYS can reach it
// before BASIC ROM is banked out.
entry:
    lda #$36                // Bank out BASIC ROM (keep KERNAL + I/O)
    sta $01
    jmp entry_main          // Now code past $A000 is accessible

// Exit trampoline — MUST live below $A000 because it banks BASIC
// ROM back in. If this ran from $A000+ the CPU would start executing
// BASIC ROM the instant we set bit 0 of $01.
exit_trampoline:
    lda #0
    sta $d418               // Silence SID
    jsr restore_zp          // Must run BEFORE banking BASIC in (buffer may be under BASIC ROM)
    sei
    // Restore default IRQ vector — our handler (irq_no_blink) is in the
    // $A000-$BFFF region, hidden once BASIC ROM is banked in.
    lda #$31
    sta $0314
    lda #$ea
    sta $0315
    lda $01
    ora #%00000001          // Set bit 0 (LORAM) — bank in BASIC ROM
    sta $01
    cli
    lda #$0e
    sta $d020               // Restore default border (light blue)
    lda #$06
    sta $d021               // Restore default background (blue)
    lda $d018
    ora #%00000010          // Lowercase mode (BASIC default)
    sta $d018
    lda $dd00
    ora #%00000011          // Restore VIC-II bank 0 (serial I/O may have corrupted)
    sta $dd00
    lda #$93                // PETSCII clear screen
    jsr $ffd2               // KERNAL CHROUT
    jmp ($a002)             // BASIC warm-start (works for both SYS and chain-load)

// tramp_dig_ability — pinned low for common tunnel code.
tramp_dig_ability:
    jmp calc_dig_ability

// All .text directives produce screen codes (not PETSCII) since
// all output uses direct screen RAM writes at $0400+.
.encoding "screencode_mixed"

.const DUNGEON_GEN_BUSY = 1

#import "../common/zeropage.s"
#import "memory.s"
#import "../common/reu.s"
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
#import "../common/sound.s"
#import "../common/huffman.s"
#import "../common/dungeon_data.s"
#import "../common/dungeon_features.s"
#import "../common/monster.s"
#import "../common/tier_manager.s"
#import "../common/overlay.s"
#import "../common/monster_ai.s"
#import "../common/recall.s"
#import "../common/monster_magic.s"
#import "../common/item.s"
#import "../common/player_items.s"
#import "../common/spell_data.s"
#import "../common/spell_effects.s"
#import "../common/player_magic.s"
#import "dungeon_render.s"
#import "../common/dungeon_los.s"
#import "../common/player_move.s"
#import "../common/combat.s"
#import "../common/projectile.s"
#import "../common/ranged_fire.s"
#import "../common/throw.s"
#import "../common/bash.s"
#import "../common/tunnel.s"
#import "../common/monster_attack.s"
#import "../common/turn.s"
#import "../common/store_data.s"
#import "../common/string_bank.s"
#import "../common/runtime_ui_strings.s"
#import "../common/io_kernal_consts.s"
#import "../common/save.s"
#import "../common/disk_swap.s"
#import "../common/score_io.s"
#import "../common/title_screen.s"
#import "../common/wizard.s"
#import "../common/game_loop.s"

// ============================================================
// Entry point
// ============================================================
entry_main:
    // Save BASIC's zero page state so we can restore on exit
    jsr save_zp

    // BASIC ROM already banked out by bootstrap above

    // Copy banked code payload to $F000 (must happen before any
    // trampoline calls — payload stored inline after program code)
    jsr init_copy_banked

    // Patch reu_show_status: RTS → JMP tramp_reu_show_status
    lda #$4c                    // JMP absolute opcode
    sta reu_show_status
    lda #<tramp_reu_show_status
    sta reu_show_status + 1
    lda #>tramp_reu_show_status
    sta reu_show_status + 2

    jsr generation_busy_install
    jsr platform_services_install64
    jsr platform_services_assert_installed

    // Select lowercase/uppercase character set (52 letter symbols)
    // Bit 1 of $D018 selects character set: 0=uppercase+graphics, 1=lowercase+uppercase
    lda $d018
    ora #%00000010          // Set bit 1 → lowercase + uppercase
    sta $d018
    // Also set via $D016 to ensure proper state
    // (Actually $D018 bit 1 is sufficient on C64)

    // Set border and background to black
    lda #COL_BLACK
    sta $d020               // Border
    sta $d021               // Background

restart_entry:
    // --- Initialize subsystems ---
    jsr detect_machine
    jsr reu_detect
    jsr tier_init
    jsr sound_init
    jsr rng_seed

title_enter_menu:
    // Install IRQ wedge: suppress KERNAL cursor blink permanently.
    // KERNAL routines (CHROUT, LOAD) constantly reset $CC=0 which
    // re-enables cursor blink. Our wedge forces $CC non-zero on every
    // IRQ tick BEFORE the KERNAL handler checks it, so the blink code
    // never executes and never corrupts color RAM.
    sei
    lda #<irq_no_blink
    sta $0314
    lda #>irq_no_blink
    sta $0315
    cli

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

title_menu_loop:
    jsr input_get_key
    cmp #$4e                // 'N' — new game
    bne !not_n+
    jmp game_new_start
!not_n:
    cmp #$4c                // 'L' — load game
    bne !not_l+
    jmp title_load_game
!not_l:
    cmp #$44                // 'D' — disk setup sub-menu
    bne title_menu_loop

disk_menu_show:
    // Show disk sub-menu in the reserved bottom status area, not over title art.
    lda #DS_TITLE_MENU_ROW
    jsr screen_clear_row
    lda #DS_TITLE_PROMPT_ROW
    jsr screen_clear_row
    lda #COL_WHITE
    sta zp_text_color
    lda #DS_TITLE_MENU_ROW
    sta zp_cursor_row
    lda #9                  // Center: (40-22)/2 = 9
    sta zp_cursor_col
    lda #<ds_menu_str
    sta zp_ptr0
    lda #>ds_menu_str
    sta zp_ptr0_hi
    jsr screen_put_string

!disk_menu_loop:
    jsr input_get_key
    cmp #$53                // 'S' — same disk (mode 0)
    beq !disk_same+
    cmp #$57                // 'W' — swap disks (mode 1)
    beq !disk_swap+
    cmp #$23                // '#' — custom drive number (mode 2)
    beq !disk_drv9+
    jmp !disk_menu_loop-

!disk_same:
    lda #0
    sta disk_mode
    lda #8
    sta save_device
    lda #DS_TITLE_MENU_ROW
    jsr screen_clear_row
    lda #DS_TITLE_PROMPT_ROW
    jsr screen_clear_row
    jmp title_menu_loop

!disk_swap:
    lda #1
    sta disk_mode
    lda #8
    sta save_device
    jsr title_draw_save_disk_indicator
    jmp title_menu_loop

!disk_drv9:
    jsr disk_enter_device
    bcs !disk_drv9_fail+        // fail — re-show disk sub-menu
    jmp title_menu_loop         // success — device configured
!disk_drv9_fail:
    jmp disk_menu_show

title_draw_menu:
    // --- Show title menu: N)EW  L)OAD  D)UAL DISK ---
    lda #COL_WHITE
    sta zp_text_color
    lda #17
    sta zp_cursor_row
    lda #8                  // Center: (40-23)/2 ≈ 8
    sta zp_cursor_col
    lda #<title_menu_str
    sta zp_ptr0
    lda #>title_menu_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda disk_mode
    cmp #1
    bne !title_menu_done+
    jsr title_draw_save_disk_indicator
!title_menu_done:
    rts

title_draw_save_disk_indicator:
    // Show "[Save Disk]" indicator in the reserved bottom status area.
    lda #DS_TITLE_MENU_ROW
    jsr screen_clear_row
    lda #DS_TITLE_PROMPT_ROW
    jsr screen_clear_row
    lda #COL_CYAN
    sta zp_text_color
    lda #DS_TITLE_MENU_ROW
    sta zp_cursor_row
    lda #14                 // Center: (40-11)/2 ≈ 14
    sta zp_cursor_col
    lda #<ds_dual_str
    sta zp_ptr0
    lda #>ds_dual_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #COL_WHITE
    sta zp_text_color
    rts

title_load_game:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr sound_play
    jsr msg_init
    jsr disk_prompt_save        // Swap to save disk if dual
    jsr load_game
    // C64 callers must branch on load_result, not carry, because the
    // EnterKernal/ExitKernal wrapper preserves caller flags via php/plp.
    lda load_result
    bne !title_load_fail+
    jsr disk_prompt_game        // Swap back for tier loading
    jmp load_resume_game
!title_load_fail:
    jsr disk_prompt_game        // Swap back even on failure
    jsr input_get_key           // Let user see error message from load_game
    jmp title_enter_menu

// ============================================================
// IRQ wedge — suppress KERNAL cursor blink
// Forces $CC non-zero before KERNAL IRQ handler checks it.
// Must live in main RAM (always accessible during IRQ).
// ============================================================
irq_no_blink:
    cld
irq_no_blink_after_cld:
    lda #1
    sta zp_screen_editor_state // Force non-zero (inc wraps $FF→$00, re-enabling blink)
    jmp $ea31               // Continue to standard KERNAL IRQ handler

// ============================================================
// kernal_load_safe — KERNAL LOAD wrapper for C64
// ============================================================
kernal_load_safe:
    jsr $ffd5               // KERNAL LOAD — carry set on error
    php                     // Preserve carry for caller
    lda #<irq_no_blink      // Reinstall: KERNAL/JiffyDOS overwrites $0314
    sta $0314
    lda #>irq_no_blink
    sta $0315
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
    lda #BANK_NO_ROMS           // $34 — KERNAL off, I/O on; $E000 = overlay RAM
    sta $01
    jsr level_generate          // executes from DungeonGenOverlay at $E000
    lda #BANK_NO_BASIC          // $36 — KERNAL back on; restore normal game banking
    sta $01
    cli
    rts

// ============================================================
// Special rooms trampolines — SEI + bank out KERNAL, call $F000+
// ============================================================
tramp_assign_special_room:
    php                         // Save interrupt state (caller may be in sei context)
    sei
    lda $01
    pha                         // Save caller's $01 (may be $34 if called from overlay)
    lda #BANK_NO_ROMS
    sta $01
    jsr assign_special_room
    pla
    sta $01                     // Restore caller's banking state
    plp                         // Restore interrupt state (no cli — would re-enable IRQs with $01=$34)
    rts

tramp_vault_seal_entrance:
    php                         // Save interrupt state (caller may be in sei context)
    sei
    lda $01
    pha                         // Save caller's $01 (may be $34 if called from overlay)
    lda #BANK_NO_ROMS
    sta $01
    jsr vault_seal_entrance
    pla
    sta $01                     // Restore caller's banking state
    plp                         // Restore interrupt state
    rts

tramp_spawn_special_room_monsters:
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr spawn_special_room_monsters
    jmp tramp_sr_epilogue

tramp_spawn_nest_gold:
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr spawn_nest_gold
    jmp tramp_sr_epilogue

tramp_find_special_room:
    pha                         // Save A (room type input)
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla                         // Restore A
    jsr find_special_room
    // Carry flag preserved — lda/sta don't affect carry
    jmp tramp_sr_epilogue

tramp_sr_epilogue:
    lda #BANK_NO_BASIC
    sta $01
    cli
    rts

// ============================================================
// Ego item trampolines — SEI + bank out KERNAL, call $F000+
// ============================================================
tramp_roll_ego_type:
    pha                         // Save A (item type input)
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla                         // Restore A
    jsr roll_ego_type
    pha                         // Save result
    lda #BANK_NO_BASIC
    sta $01
    cli
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
    lda #BANK_NO_ROMS
    sta $01
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
    cpx #41                     // Buffer overflow protection
    bcs !teas_end+
    jmp !teas_loop-
!teas_end:
    stx cmb_buf_idx
    lda #BANK_NO_BASIC
    sta $01
    cli
!teas_done:
    rts

// tramp_ego_put_suffix — Write ego suffix directly to screen
// Input: A = ego type
// Uses screen_put_char to write each char while KERNAL banked out.
// Clobbers: A, X, Y, zp_ptr0
tramp_ego_put_suffix:
    cmp #0
    beq !teps_done+
    pha
    sei
    lda #BANK_NO_KERNAL         // $35 — I/O visible for color RAM
    sta $01
    pla
    jsr ego_get_suffix_ptr      // zp_ptr0 = suffix string (in $F000)
    // Read chars from $F000 and write to screen
    ldy #0
!teps_loop:
    lda (zp_ptr0),y
    beq !teps_end+
    sty teps_save_y
    jsr screen_put_char         // Clobbers Y
    ldy teps_save_y
    iny
    jmp !teps_loop-
!teps_end:
    lda #BANK_NO_BASIC
    sta $01
    cli
!teps_done:
    rts
teps_save_y: .byte 0

// ============================================================
// tramp_ego_apply_damage — Apply ego slay/bonus damage (banked at $F000)
// Input: A = ego type (1-7), cmb_damage and cmb_type set
// Output: cmb_damage updated
// Clobbers: A, X, Y, zp_math_a/b, zp_temp3, zp_temp4
tramp_ego_apply_damage:
    pha
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla
    jsr ego_apply_damage
    lda #BANK_NO_BASIC
    sta $01
    cli
    rts

// tramp_ego_get_ac_bonus — Get ego AC bonus (banked at $F000)
// Input: A = ego type (1-7)
// Output: A = AC bonus (0 if none)
// Clobbers: X
tramp_ego_get_ac_bonus:
    pha
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla
    jsr ego_get_ac_bonus
    pha
    lda #BANK_NO_BASIC
    sta $01
    cli
    pla
    rts


// Init-only strings — kept in main RAM (small, referenced by title_screen.s)
// ============================================================
title_str:
    .text "MORIA8 C=64" ; .byte 0

// title_show_sysinfo — Trampoline to call banked version at $F000
// Reads KERNAL_REV while KERNAL is still banked in, then banks out.
title_show_sysinfo:
    lda KERNAL_REV              // Read from ROM while KERNAL banked in
    sta tsi_krev_cached
    sei
    lda #BANK_NO_KERNAL         // $35 — I/O visible for color RAM
    sta $01
    jsr title_show_sysinfo_banked
    lda #BANK_NO_BASIC
    sta $01
    cli
    rts
tsi_krev_cached: .byte 0

// tramp_reu_show_status — Bank out KERNAL to call banked status display
// Patched into reu_show_status at startup by init code.
tramp_reu_show_status:
    sei
    lda $01
    pha
    lda #BANK_NO_KERNAL         // $35 — I/O visible for screen writes
    sta $01
    jsr reu_show_status_banked
    pla
    sta $01
    cli
    rts

platform_main_loop_begin_c64:
platform_vector_reassert_c64:
platform_runtime_resync_c64:
    rts

platform_services_install64:
    lda #$4c
    sta platform_main_loop_begin_api
    sta platform_vector_reassert_api
    sta platform_runtime_resync_api

    lda #<platform_main_loop_begin_c64
    sta platform_main_loop_begin_api + 1
    lda #>platform_main_loop_begin_c64
    sta platform_main_loop_begin_api + 2

    lda #<platform_vector_reassert_c64
    sta platform_vector_reassert_api + 1
    lda #>platform_vector_reassert_c64
    sta platform_vector_reassert_api + 2

    lda #<platform_runtime_resync_c64
    sta platform_runtime_resync_api + 1
    lda #>platform_runtime_resync_c64
    sta platform_runtime_resync_api + 2

    jmp platform_services_mark_installed

#import "../common/ui_help_clear.s"

// ============================================================
// UI screen trampolines — help loads from $E000 overlay, others call $F000+
// ============================================================
tramp_ui_help_display:
    lda #OVL_HELP
    jsr overlay_load
    bcc !loaded+
    jmp tramp_sr_epilogue
!loaded:
    lda #<help_pages
    sta help_pages_src_lo
    lda #>help_pages
    sta help_pages_src_hi
    sei
    lda #BANK_NO_KERNAL       // $35 — I/O visible for color RAM writes
    sta $01
    jsr ui_help_display
    jmp tramp_sr_epilogue

tramp_ui_char_display:
    sei
    lda #BANK_NO_KERNAL       // $35 — I/O visible for color RAM writes
    sta $01
    jsr ui_char_display
    jmp tramp_sr_epilogue

tramp_ui_inv_display:
    sei
    lda #BANK_NO_KERNAL       // $35 — I/O visible for color RAM writes
    sta $01
    jsr ui_inv_display
    jmp tramp_sr_epilogue

tramp_ui_equip_display:
    sei
    lda #BANK_NO_KERNAL       // $35 — I/O visible for color RAM writes
    sta $01
    jsr ui_equip_display
    jmp tramp_sr_epilogue

tramp_ui_wizard_display:
    jmp wizard_c64_menu_display

tramp_ui_recall:
    sei
    lda #BANK_NO_KERNAL       // $35 — I/O visible for color RAM writes
    sta $01
    jsr ui_recall_display
    jmp tramp_sr_epilogue



// ============================================================
// Store overlay trampolines — load overlay, bank out KERNAL, call $E000+
// ============================================================
// Shared preamble: ensure town overlay is loaded, then bank out KERNAL
store_overlay_preamble:
    lda #OVL_TOWN
    jsr overlay_load
    sei
    lda #BANK_NO_KERNAL         // $35 — $E000 = RAM + I/O for color RAM
    sta $01
    rts

tramp_store_init_all:
    jsr store_overlay_preamble
    jsr store_init_all
    jmp tramp_sr_epilogue

tramp_store_restock_all:
    jsr store_overlay_preamble
    jsr store_restock_all
    jmp tramp_sr_epilogue

tramp_store_enter:
    jsr store_overlay_preamble
    jsr store_enter
    jmp tramp_sr_epilogue

// ============================================================
// Startup overlay trampoline — load overlay, bank out KERNAL, call $E000+
// ============================================================
tramp_player_create:
    lda #OVL_STARTUP
    jsr overlay_load
    sei
    lda #BANK_NO_KERNAL         // $35 — $E000 = RAM + I/O for color RAM
    sta $01
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

    // 1. Resolve creature name while tier data still at $E000
    lda zp_death_source
    cmp #DEATH_CURSED           // Special sources ($FD-$FF) don't need name
    bcs !tgo_load_overlay+
    tax
    jsr creature_get_name       // Copies name to creature_name_buf in main RAM

!tgo_load_overlay:
    // 2. Load death overlay (replaces tier data at $E000)
    lda #OVL_DEATH
    jsr overlay_load

    // 3. Calculate score (overlay code, no KERNAL needed)
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr score_calculate
    lda #BANK_NO_BASIC
    sta $01
    cli

    // 4. Load high scores from disk (main RAM, needs KERNAL)
    jsr hiscore_load

    // 5. Insert into high score table (overlay code)
    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    bne !tgo_skip_hiscore+
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr hiscore_insert
    lda #BANK_NO_BASIC
    sta $01
    cli

    // 6. Save high scores to disk (main RAM, needs KERNAL)
    jsr hiscore_save
!tgo_skip_hiscore:
    lda death_source_saved
    sta zp_death_source

    // 7. Display death screen (overlay code)
    // Defensive: restore VIC-II bank 0 after KERNAL serial I/O
    // KERNAL uses CIA2 ($DD00) bits 3-5 for serial bus;
    // bits 0-1 select VIC bank. Ensure bank 0 ($0000-$3FFF).
    lda $dd00
    ora #%00000011              // Bits 0-1 = %11 → bank 0
    sta $dd00
    sei
    lda #BANK_NO_KERNAL         // $35 — I/O visible for color RAM
    sta $01
    jsr score_death_screen
    lda #BANK_NO_BASIC
    sta $01
    cli
    rts

// ============================================================
// game_over_prompt — R)EBOOT / S)TART OVER / Q)UIT prompt
// Shown at all exit points (save+quit, voluntary quit, death).
// Q falls through; R and S branch internally.
// ============================================================
game_over_prompt:
    // Hide the previous gameplay/death frame before preparing the full-screen
    // quit/restart prompt so stale status rows do not remain visible.
    jsr screen_blank
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all
    lda #COL_WHITE
    sta zp_text_color
    lda #12                     // Row 12 (center)
    sta zp_cursor_row
    lda #9                      // Col 9: (40-22)/2 = 9
    sta zp_cursor_col
    lda #<game_over_str
    sta zp_ptr0
    lda #>game_over_str
    sta zp_ptr0_hi
    jsr screen_put_string
    jsr screen_unblank
    lda #0
    sta zp_kbdbuf_count         // Flush keyboard buffer
!gop_loop:
    jsr input_get_key
    cmp #$52                    // 'R' — reboot (reload from disk)
    beq !gop_reboot+
    cmp #$53                    // 'S' — start over (restart to title)
    beq !gop_restart+
    cmp #$51                    // 'Q' — quit to BASIC
    bne !gop_loop-
    rts                         // Q: fall through to exit_trampoline
!gop_reboot:
    // Hard reset — jump through the C64 cold-start vector.
    // KERNAL ROM is readable ($01=$36, HIRAM set), so $FFFC/$FFFD
    // contain the reset vector ($FCE2). Equivalent to pressing reset.
    jmp ($fffc)
!gop_restart:
    jmp game_restart

game_over_str:
    .text "R)EBOOT  S)TART  Q)UIT" ; .byte 0

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
    sta recall_query_sc
    sta recall_found_type
    sta recall_last_sc
    sta recall_last_idx

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

// init_copy_banked — Copy banked code payload to $F000
// Called once at startup before any $F000 trampoline is used.
// Clobbers: A, X, Y, zp_ptr0/hi, zp_ptr1/hi
init_copy_banked:
    sei
    lda #BANK_NO_ROMS           // $34 — bank out all ROMs to write $F000
    sta $01
    lda #<banked_payload
    sta zp_ptr0
    lda #>banked_payload
    sta zp_ptr0_hi
    lda #$00
    sta zp_ptr1
    lda #$F0
    sta zp_ptr1_hi
    ldx #((banked_payload_end - banked_payload + 255) / 256)
    ldy #0
!copy:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    bne !copy-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dex
    bne !copy-
    lda #BANK_NO_BASIC          // $36 — restore normal banking
    sta $01
    cli
    rts

// ============================================================
// Banked code payload — stored inline here, copied to $F000
// at startup by init_copy_banked.
//
// Using .pseudopc so labels resolve to $F000+ addresses (where
// the code runs) but bytes are stored contiguously after the
// main program. This avoids spanning $D000 (I/O registers) in
// the PRG file, which would corrupt the serial bus during
// KERNAL LOAD from disk.
// ============================================================
banked_payload:
.pseudopc $F000 {
    #import "../common/special_rooms.s"
    #import "../common/ego_items.s"
    #import "../common/title_sysinfo_banked.s"
    #import "../common/reu_loading_banked.s"
    #import "../common/ui_character.s"
    #import "../common/ui_inventory.s"
    #import "../common/ui_home.s"
    #import "../common/string_bank_banked.s"
    #import "../common/ui_recall.s"

banked_code_end:
}
banked_payload_end:

.print "Banked payload: " + (banked_payload_end - banked_payload) + " bytes at $" + toHexString(banked_payload) + "-$" + toHexString(banked_payload_end)
.assert "Payload fits below I/O ($D000)", banked_payload_end < $D000, true
.assert "Banked code fits below CPU vectors", banked_code_end <= $FFFA, true

// ============================================================
// Town overlay — store code at $E000, output to separate PRG
// ============================================================
// This segment produces out/ovl_town (loaded from disk as OVL.TOWN).
// Labels resolve to $E000+ but bytes go to the overlay PRG file,
// not the main moria.prg. All main RAM symbols are accessible.
.segment TownOverlay
    #import "../common/store.s"
    #import "../common/ui_store.s"
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
ovl_death_end:
.print "Death overlay: " + (ovl_death_end - $e000) + " bytes at $E000-$" + toHexString(ovl_death_end)
.assert "Death overlay fits in $E000-$EFFF", ovl_death_end <= $F000, true

// ============================================================
// Help overlay — dedicated help modal screen at $E000
// ============================================================
.segment HelpOverlay
    #import "../common/ui_help_data.s"
    #import "../common/ui_help_page2_data.s"
    #import "../common/ui_help.s"
ovl_help_end:
.print "Help overlay: " + (ovl_help_end - $e000) + " bytes at $E000-$" + toHexString(ovl_help_end)
.assert "Help overlay fits in $E000-$EFFF", ovl_help_end <= $F000, true

// ============================================================
// UI overlay — reserved placeholder on C64 for shared overlay numbering
// ============================================================
.segment UiOverlay
ovl_ui_stub:
    rts
ovl_ui_end:
.print "UI overlay: " + (ovl_ui_end - $e000) + " bytes at $E000-$" + toHexString(ovl_ui_end)
.assert "UI overlay fits in $E000-$EFFF", ovl_ui_end <= $F000, true

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
