// Relocated Map Model:
//   - MAP_BASE = $0B00-$19FF (Empty Bank 0 RAM)
//   - Main Code = $1C01-$BFFF
//   - BASIC Stub = $1C01 (SYS 7182)
//
// MMU set to $0E at startup (System ROM in, BASIC out via MMU), then $01
// used for runtime banking (same values as C64 for common code compatibility).

// ============================================================
// Overlay segments — produce separate PRGs at $E000.
// Assembled in same pass as main program — full symbol access.
// Only ONE overlay is active at a time (they share $E000-$EFFF).
//
// $E000 works for both C64 and C128:
//   C64:  KERNAL LOAD secondary=1 uses PRG header ($E000). VIC-II
//         bank must be restored after KERNAL serial I/O (done in
//         overlay_load_disk). Execution: $01=$35 hides KERNAL ROM.
//   C128: KERNAL LOAD secondary=1 uses PRG header ($E000). Writes
//         go to Bank 0 RAM under KERNAL ROM (same as C64). Execution:
//         $FF00=$3E hides KERNAL ROM → $E000+ = Bank 0 RAM.
//
// banked_payload is at $F000+ so overlays ($E000-$EFFF max 4096
// bytes) never overlap it.
// ============================================================
.segmentdef StartupOverlay    [outPrg="out/ovl.start", start=$e000, min=$e000, max=$efff]
.segmentdef TownOverlay       [outPrg="out/ovl.town",  start=$e000, min=$e000, max=$efff]
.segmentdef DeathOverlay      [outPrg="out/ovl.death", start=$e000, min=$e000, max=$efff]
.segmentdef DungeonGenOverlay [outPrg="out/ovl.gen",   start=$e000, min=$e000, max=$efff]
.segmentdef Bank1Data         [outPrg="out/bank1.dat", start=$e000, min=$e000, max=$feff]

// ============================================================
// BASIC stub at $1C01 — SYS 7182 ($1C0E)
// ============================================================
.pc = $1c01 "BASIC Stub"
    .byte $0b, $1c, $0a, $00, $9e, $37, $31, $38, $32, $00, $00, $00

.pc = $1c0e "Program"
entry:
    // DIAG-0: RED = game code reached at $1C0E
    lda #$02
    sta $d020
    jmp entry_real

// ============================================================
// Core System & UI Routines — MUST live in Safe Zone (<$C000)
// ============================================================
#import "../common/zeropage.s"
#import "memory128.s"
#import "../common/color.s"
#import "../common/sound.s"
#import "config128.s"
#import "screen_vdc.s"
#import "input128.s"

// Bootstrap — sets up MMU and processor port, jumps to main code
entry_real:
    // DIAG-1: GREEN = entry_real reached
    lda #$05
    sta $d020
    sei
    cld
    ldx #$ff
    txs
    lda #$7f
    sta $dc0d               // Mask all CIA1 interrupt sources
    sta $dd0d               // Mask all CIA2 interrupt sources
    lda $dc0d               // Acknowledge pending CIA1
    lda $dd0d               // Acknowledge pending CIA2
    lda #0
    sta $d01a               // Disable all VIC-II interrupt sources
    lda #$ff
    sta $d019               // Acknowledge any pending VIC-II interrupts
    sta $d8                 // Screen Editor: 80-col mode
    // Mirror KERNAL vectors/stubs into RAM underneath ROM ($FF05-$FFFF)
    // Skipping $FF00-$FF04 to avoid mid-loop MMU bank-switching.
    ldx #5
!mirror:
    lda $ff00,x
    sta $ff00,x
    inx
    bne !mirror-

    // DIAG-2: BLUE = mirror done
    lda #$06
    sta $d020

    // --- Patch KERNAL JMP table in RAM ---
    // Read original targets from ROM stubs and patch stubs to point to our safe wrappers.
    // This allows game code to call JSR $FFxx and have the wrapper manage the MMU.
    
    // FFB7 READST
    lda $ffb8
    sta t_readst
    lda $ffb9
    sta t_readst+1
    lda #<w_readst
    sta $ffb8
    lda #>w_readst
    sta $ffb9
    // FFBA SETLFS
    lda $ffbb
    sta t_setlfs
    lda $ffbc
    sta t_setlfs+1
    lda #<w_setlfs
    sta $ffbb
    lda #>w_setlfs
    sta $ffbc
    // FFBD SETNAM
    lda $ffbe
    sta t_setnam
    lda $ffbf
    sta t_setnam+1
    lda #<w_setnam
    sta $ffbe
    lda #>w_setnam
    sta $ffbf
    // FFC0 OPEN
    lda $ffc1
    sta t_open
    lda $ffc2
    sta t_open+1
    lda #<w_open
    sta $ffc1
    lda #>w_open
    sta $ffc2
    // FFC3 CLOSE
    lda $ffc4
    sta t_close
    lda $ffc5
    sta t_close+1
    lda #<w_close
    sta $ffc4
    lda #>w_close
    sta $ffc5
    // FFC6 CHKIN
    lda $ffc7
    sta t_chkin
    lda $ffc8
    sta t_chkin+1
    lda #<w_chkin
    sta $ffc7
    lda #>w_chkin
    sta $ffc8
    // FFC9 CHKOUT
    lda $ffca
    sta t_chkout
    lda $ffcb
    sta t_chkout+1
    lda #<w_chkout
    sta $ffca
    lda #>w_chkout
    sta $ffcb
    // FFCC CLRCHN
    lda $ffcd
    sta t_clrchn
    lda $ffce
    sta t_clrchn+1
    lda #<w_clrchn
    sta $ffcd
    lda #>w_clrchn
    sta $ffce
    // FFCF CHRIN
    lda $ffd0
    sta t_chrin
    lda $ffd1
    sta t_chrin+1
    lda #<w_chrin
    sta $ffd0
    lda #>w_chrin
    sta $ffd1
    // FFD2 CHROUT
    lda $ffd3
    sta t_chrout
    lda $ffd4
    sta t_chrout+1
    lda #<w_chrout
    sta $ffd3
    lda #>w_chrout
    sta $ffd4
    // FFD5 LOAD
    lda $ffd6
    sta t_load
    lda $ffd7
    sta t_load+1
    lda #<w_load
    sta $ffd6
    lda #>w_load
    sta $ffd7

    // Patch hardware IRQ vector ($FFFE/$FFFF) in RAM.
    // When $FF00=$3E (game mode), CPU reads $FFFE from RAM.
    // The mirrored ROM vector points to KERNAL code at $E000+ which is
    // hidden by $FF00=$3E. Our safe handler just acknowledges CIA and RTIs.
    lda #<safe_irq
    sta $fffe
    lda #>safe_irq
    sta $ffff
    // Patch hardware NMI vector ($FFFA/$FFFB) in RAM — same issue.
    lda #<safe_nmi
    sta $fffa
    lda #>safe_nmi
    sta $fffb

    // DIAG-3: YELLOW = patching done
    lda #$07
    sta $d020

    :MachineRestoreDefault()
    jmp entry_main

// ============================================================
// Safe KERNAL Wrappers
// Each wrapper switches to MMU_NORMAL, calls real target, 
// then restores MMU_ALL_RAM. Flags (Carry!) are preserved via PHP/PLP.
// ============================================================

// READST
w_readst:
    pha
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_NO_BASIC
    sta $01
    pla
    .byte $20
t_readst: .word 0
    php
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    pla
    plp
    rts
// SETLFS
w_setlfs:
    pha
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_NO_BASIC
    sta $01
    pla
    .byte $20
t_setlfs: .word 0
    php
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    pla
    plp
    rts
// SETNAM
w_setnam:
    pha
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_NO_BASIC
    sta $01
    pla
    .byte $20
t_setnam: .word 0
    php
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    pla
    plp
    rts
// OPEN
w_open:
    pha
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_NO_BASIC
    sta $01
    pla
    .byte $20
t_open: .word 0
    php
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    pla
    plp
    rts
// CLOSE
w_close:
    pha
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_NO_BASIC
    sta $01
    pla
    .byte $20
t_close: .word 0
    php
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    pla
    plp
    rts
// CHKIN
w_chkin:
    pha
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_NO_BASIC
    sta $01
    pla
    .byte $20
t_chkin: .word 0
    php
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    pla
    plp
    rts
// CHKOUT
w_chkout:
    pha
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_NO_BASIC
    sta $01
    pla
    .byte $20
t_chkout: .word 0
    php
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    pla
    plp
    rts
// CLRCHN
w_clrchn:
    pha
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_NO_BASIC
    sta $01
    pla
    .byte $20
t_clrchn: .word 0
    php
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    pla
    plp
    rts
// CHRIN
w_chrin:
    pha
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_NO_BASIC
    sta $01
    pla
    .byte $20
t_chrin: .word 0
    php
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    pla
    plp
    rts
// CHROUT
w_chrout:
    pha
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_NO_BASIC
    sta $01
    pla
    .byte $20
t_chrout: .word 0
    php
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    pla
    plp
    rts
// LOAD
w_load:
    pha
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_NO_BASIC
    sta $01
    pla
    .byte $20
t_load: .word 0
    php
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    pla
    plp
    rts

// safe_irq — Minimal IRQ handler for $FF00=$3E mode.
// When $FF00=$3E (game mode), the CPU reads the IRQ vector from RAM.
// We can't dispatch to the KERNAL handler (hidden behind RAM), so we
// just acknowledge ALL interrupt sources and return. Both CIA1 and VIC-II
// share the IRQ line — if VIC-II raster IRQ fires and isn't acknowledged,
// it reasserts immediately after RTI causing an infinite IRQ loop.
safe_irq:
    pha
    lda $dc0d               // Acknowledge CIA1 interrupt (read clears flags)
    lda #$ff
    sta $d019               // Acknowledge VIC-II interrupts (write 1s clears flags)
    pla
    rti

// safe_nmi — Minimal NMI handler for $FF00=$3E mode.
safe_nmi:
    pha
    lda $dd0d               // Acknowledge CIA2 NMI
    pla
    rti

// kernal_load_safe — KERNAL LOAD wrapper for C128
// Reinstalls keyboard stub on exit. Callers manage MMU.
kernal_load_safe:
    sei
    jsr $ffd5
    php
    lda #<chrin_keyboard_stub
    sta $0302
    lda #>chrin_keyboard_stub
    sta $0303
    plp
    rts

chrin_keyboard_stub:
    lda #0
    clc
    rts

// safe_setbnk — SETBNK ($FF68) wrapper for C128
// Temporarily enables KERNAL ROM, calls real SETBNK, restores MMU.
// $FF68 is in the banked code range ($F000-$FFB6) so it can't be
// patched via the JMP table — call this routine directly instead.
safe_setbnk:
    pha
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_NO_BASIC
    sta $01
    pla
    jsr $ff68
    php
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    pla
    plp
    rts

// init_copy_banked — Copy banked code payload to $EB00
// Uses $3F (NOIO) instead of $3E because source data crosses the I/O
// range $D000-$DFFF. With $3E, reads from $D000+ return I/O register
// garbage instead of game data.
// NOTE: destination is $EB00, not $E000, because $E000-$E80D is used
// at runtime by BANKED_DATA_BASE (tier monster/item databases).
init_copy_banked:
    sei
    // DIAG-6a: WHITE = entered init_copy_banked
    lda #COL_WHITE
    sta $d020
    lda #<banked_payload
    sta zp_ptr0
    lda #>banked_payload
    sta zp_ptr0_hi
    lda #$00
    sta zp_ptr1
    lda #$EB
    sta zp_ptr1_hi
    ldx #((banked_payload_end - banked_payload + 255) / 256)
    ldy #0
    // DIAG-6b: YELLOW = about to start copy loop
    pha
    lda #COL_YELLOW
    sta $d020
    pla
    // Switch to NOIO for the copy (source crosses $D000)
    lda #$3f                // MMU_ALL_RAM but with I/O hidden (RAM at $D000)
    sta $ff00
!copy:
    lda zp_ptr1_hi
    cmp #$ff
    bne !do_copy+
    cpy #5
    bcc !skip_copy+
    cpy #$b7
    bcs !skip_copy+             // Protect $FFB7-$FFFF (patched KERNAL JMP table + vectors)
!do_copy:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
!skip_copy:
    iny
    bne !copy-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dex
    bne !copy-
    lda #MMU_ALL_RAM
    sta $ff00
    // DIAG-6c: RED = copy loop done, I/O restored
    lda #COL_RED
    sta $d020
    cli
    rts

// Exit trampoline — MUST live below $A000
exit_trampoline:
    lda #0
    sta $d418
    jsr restore_zp
    sei
    lda #$00
    sta $ff00
    lda #BANK_ALL_ROM
    sta $01
    cli
    lda #$93
    jsr $ffd2
    jmp ($4002)

// ============================================================
// Entry point
// ============================================================
entry_main:
    // DIAG-4: ORANGE = entry_main reached
    lda #$08
    sta $d020
    sei
    cld
    ldx #$ff
    txs

    // Mask CIA1 interrupts — game mode uses direct hardware access.
    lda #$7f
    sta $dc0d
    lda $dc0d                   // Acknowledge any pending CIA1 interrupt

    // Reset SETBNK to Bank 0 — boot128 left SETBNK=Bank1 after loading
    // the game PRG. Without this reset, all subsequent KERNAL LOADs
    // (overlays, title, etc.) silently write to Bank1 while game reads Bank0.
    lda #0
    ldx #0
    jsr $ff68                   // SETBNK: reset to Bank 0
    // DIAG-5e: LIGHT GREEN = SETBNK reset done
    lda #$0d
    sta $d020

    // Save BASIC's zero page state so we can restore on exit
    jsr save_zp
    // DIAG-5f: LIGHT BLUE = save_zp done
    lda #$0e
    sta $d020

    // Relocate banked code payload to $E000.
    // MUST be done before any UI or overlay call.
    jsr init_copy_banked

    // --- DIAG: Purple border = init_copy_banked done ---
    lda #COL_PURPLE
    sta $d020

    // Patch reu_show_status: RTS → JMP tramp_reu_show_status
    lda #$4c                    // JMP absolute opcode
    sta reu_show_status
    lda #<tramp_reu_show_status
    sta reu_show_status + 1
    lda #>tramp_reu_show_status
    sta reu_show_status + 2

    // Disable hardware cursor (register 10, bits 6-5 = 01 = cursor off)
    // Prevents KERNAL cursor-blink IRQ from writing to VDC regs 14/15/18/19
    lda #$20
    ldx #10
    jsr vdc_write_reg

    // Set VDC background to black (register 26 = background color)
    lda #0                      // RGBI 0 = black
    ldx #26
    jsr vdc_write_reg

    // Set border and background to black (VIC-II — harmless in 80-col mode)
    lda #0
    sta $d020               // Border
    sta $d021               // Background

restart_entry:
    // --- DIAG: White border = restart_entry reached ---
    lda #COL_WHITE
    sta $d020

    // --- Initialize subsystems ---
    jsr detect_machine

    // Cache KERNAL revision byte — must read from low RAM (below $C000)
    // because MMU_NORMAL banks Screen Editor ROM over $C000-$CFFF.
    lda #MMU_NORMAL             // Expose KERNAL ROM at $E000-$FFFF
    sta $ff00
    lda KERNAL_REV              // $FF80 — in KERNAL ROM
    sta tsi_krev_cached
    lda #MMU_ALL_RAM            // Back to all-RAM mode
    sta $ff00

    lda #0                      // Force REU absent for C128 MVP
    sta reu_present
    sta reu_banks
    sta reu_size_kb
    sta reu_size_kb + 1

    jsr tier_init
    jsr sound_init
    jsr rng_seed

    // --- DIAG: Red border = subsystems done ---
    lda #COL_RED
    sta $d020

    lda #$ff
    sta $d8                     // Screen Editor: 80-col mode

    cli

    lda #<chrin_keyboard_stub
    sta $0302
    lda #>chrin_keyboard_stub
    sta $0303

    lda #COL_LGREY
    sta zp_text_color

    // --- DIAG: Cyan border = about to screen_clear ---
    lda #COL_CYAN
    sta $d020

    jsr screen_clear

    // --- DIAG: Green border = screen_clear done, about to title_load ---
    lda #COL_GREEN
    sta $d020

    jsr title_load_and_draw

    // --- DIAG: Blue border = title_load done ---
    lda #COL_BLUE
    sta $d020

    lda #STATUS_ROW
    jsr screen_clear_row
    lda #STATUS_ROW + 1
    jsr screen_clear_row
    lda #STATUS_ROW + 2
    jsr screen_clear_row

    jsr title_show_sysinfo

    // --- DIAG: Yellow border = title_show_sysinfo done ---
    lda #COL_YELLOW
    sta $d020

    // --- Show title menu ---
    lda #COL_WHITE
    sta zp_text_color
    lda #17
    sta zp_cursor_row
    lda #8
    sta zp_cursor_col
    lda #<title_menu_str
    sta zp_ptr0
    lda #>title_menu_str
    sta zp_ptr0_hi
    jsr screen_put_string

!title_menu_loop:
    jsr input_get_key
    cmp #$4e                // 'N' — new game
    bne !not_n+
    jmp game_new_start
!not_n:
    cmp #$4c                // 'L' — load game
    bne !not_l+
    jmp !title_load+
!not_l:
    cmp #$44                // 'D' — disk setup
    bne !title_menu_loop-

disk_menu_show:
    // Show disk sub-menu on row 18
    lda #18
    jsr screen_clear_row
    lda #COL_WHITE
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #9                  // Keep C64-style centering for MVP
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
    lda #18
    jsr screen_clear_row
    jmp !title_menu_loop-

!disk_swap:
    lda #1
    sta disk_mode
    lda #8
    sta save_device
    jmp !disk_show_indicator+

!disk_drv9:
    jsr disk_enter_device
    bcs !disk_drv9_fail+        // fail — re-show disk sub-menu
    jmp !title_menu_loop-       // success — device configured
!disk_drv9_fail:
    jmp disk_menu_show

!disk_show_indicator:
    // Show "[Save Disk]" indicator on row 18
    lda #18
    jsr screen_clear_row
    lda #COL_CYAN
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #14                 // Keep C64-style centering for MVP
    sta zp_cursor_col
    lda #<ds_dual_str
    sta zp_ptr0
    lda #>ds_dual_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #COL_WHITE
    sta zp_text_color
    jmp !title_menu_loop-

!title_load:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr sound_play
    jsr msg_init
    jsr disk_prompt_save
    jsr load_game
    bcc !title_load_fail+
    jsr disk_prompt_game
    jmp load_resume_game
!title_load_fail:
    jsr disk_prompt_game
    jsr input_get_key
    jmp !title_menu_loop-


// ============================================================
// Imports — Game Engine (Safe to spill past $C000)
// ============================================================
#import "../common/tables.s"
#import "../common/item_defs.s"
#import "../common/reu.s"
#import "../common/rng.s"
#import "../common/math.s"
#import "../common/player.s"
#import "../common/ui_messages.s"
#import "../common/ui_status.s"
#import "../common/stat_display.s"
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
#import "dungeon_render_vdc.s"
#import "../common/dungeon_los.s"
#import "../common/turn.s"
#import "../common/store_data.s"
#import "../common/monster_attack.s"
#import "../common/string_bank.s"
#import "../common/save.s"
#import "../common/disk_swap.s"
#import "../common/score_io.s"
#import "../common/title_screen.s"
#import "../common/game_loop.s"
#import "../common/ui_help_clear.s"
#import "../common/player_move.s"
#import "../common/combat.s"
#import "../common/projectile.s"
#import "../common/ranged_fire.s"
#import "../common/throw.s"
#import "../common/bash.s"
#import "../common/tunnel.s"

// ============================================================
// Dungeon gen overlay trampoline — overlays now at $0400 (Safe Zone)
// ============================================================

tramp_level_generate:
    jsr level_generate
    rts

// ============================================================
// Special rooms trampolines — SEI + bank out KERNAL, call $E000+
// ============================================================
tramp_assign_special_room:
    php
    sei
    lda $01
    pha
    :BankOutKernal()
    jsr assign_special_room
    pla
    sta $01
    plp
    rts

tramp_vault_seal_entrance:
    php
    sei
    lda $01
    pha
    :BankOutKernal()
    jsr vault_seal_entrance
    pla
    sta $01
    plp
    rts

tramp_spawn_special_room_monsters:
    sei
    :BankOutKernal()
    jsr spawn_special_room_monsters
    jmp tramp_sr_epilogue

tramp_spawn_nest_gold:
    sei
    :BankOutKernal()
    jsr spawn_nest_gold
    jmp tramp_sr_epilogue

tramp_find_special_room:
    pha
    sei
    :BankOutKernal()
    pla
    jsr find_special_room
    jmp tramp_sr_epilogue

tramp_sr_epilogue:
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    rts

// ============================================================
// Ego item trampolines — SEI + bank out KERNAL, call $F000+
// ============================================================
tramp_roll_ego_type:
    pha
    sei
    :BankOutKernal()
    pla
    jsr roll_ego_type
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    pla
    rts

tramp_ego_append_suffix:
    cmp #0
    beq !teas_done+
    pha
    sei
    :BankOutKernal()
    pla
    jsr ego_get_suffix_ptr
    ldx cmb_buf_idx
    ldy #0
!teas_loop:
    lda (zp_ptr0),y
    beq !teas_end+
    sta combat_msg_buf,x
    inx
    iny
    cpx #41
    bcs !teas_end+
    jmp !teas_loop-
!teas_end:
    stx cmb_buf_idx
    lda #MMU_ALL_RAM
    sta $ff00
    cli
!teas_done:
    rts

tramp_ego_put_suffix:
    cmp #0
    beq !teps_done+
    pha
    sei
    :BankOutKernal()           // KERNAL off, I/O on
    pla
    jsr ego_get_suffix_ptr
    ldy #0
!teps_loop:
    lda (zp_ptr0),y
    beq !teps_end+
    sty teps_save_y
    jsr screen_put_char
    ldy teps_save_y
    iny
    jmp !teps_loop-
!teps_end:
    lda #MMU_ALL_RAM
    sta $ff00
    cli
!teps_done:
    rts
teps_save_y: .byte 0

// ============================================================
// tramp_ego_apply_damage — Apply ego slay/bonus damage (banked at $F000)
// ============================================================
tramp_ego_apply_damage:
    pha
    sei
    :BankOutKernal()
    pla
    jsr ego_apply_damage
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    rts

// tramp_ego_get_ac_bonus — Get ego AC bonus (banked at $F000)
tramp_ego_get_ac_bonus:
    pha
    sei
    :BankOutKernal()
    pla
    jsr ego_get_ac_bonus
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    pla
    rts


// Init-only strings — kept in main RAM
// ============================================================
title_str:
    .text "MORIA8 C=128" ; .byte 0

// title_show_sysinfo — Trampoline to call banked version at $F000
// KERNAL_REV is cached at startup in restart_entry (low RAM, below $C000)
// because MMU_NORMAL banks Screen Editor ROM over $C000-$CFFF, making it
// impossible to execute code here while KERNAL ROM is visible.
title_show_sysinfo:
    sei
    lda $01
    pha
    :BankOutKernal()           // $35 — I/O visible for VDC register access
    jsr title_show_sysinfo_banked
    pla
    sta $01                    // Restore processor port
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    rts
tsi_krev_cached: .byte 0

// tramp_reu_show_status — Bank out KERNAL to call banked status display
tramp_reu_show_status:
    sei
    lda $01
    pha
    :BankOutKernal()           // $35 — I/O visible for VDC
    jsr reu_show_status_banked
    pla
    sta $01
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    rts

// ============================================================
// UI screen trampolines — SEI + bank out KERNAL, call $F000+
// ============================================================
tramp_ui_help_display:
    sei
    :BankOutKernal()       // $35 — I/O visible for VDC
    jsr ui_help_display
    jmp tramp_sr_epilogue

tramp_ui_char_display:
    sei
    :BankOutKernal()
    jsr ui_char_display
    jmp tramp_sr_epilogue

tramp_ui_inv_display:
    sei
    :BankOutKernal()
    jsr ui_inv_display
    jmp tramp_sr_epilogue

tramp_ui_equip_display:
    sei
    :BankOutKernal()
    jsr ui_equip_display
    jmp tramp_sr_epilogue

tramp_ui_recall:
    sei
    :BankOutKernal()
    jsr ui_recall_display
    jmp tramp_sr_epilogue


// ============================================================
// Store overlay trampolines — load overlay at $0400, call directly
// ============================================================
tramp_store_init_all:
    lda #OVL_TOWN
    jsr overlay_load
    jsr store_init_all
    rts

tramp_store_restock_all:
    lda #OVL_TOWN
    jsr overlay_load
    jsr store_restock_all
    rts

tramp_store_enter:
    lda #OVL_TOWN
    jsr overlay_load
    jsr store_enter
    rts

// ============================================================
// Startup overlay trampoline — character creation at $0400
// ============================================================
tramp_player_create:
    lda #OVL_STARTUP
    jsr overlay_load
    jsr player_create
    rts

// ============================================================
// Death overlay trampoline — death screen at $0400
// ============================================================
tramp_game_over:
    // 1. Resolve creature name while tier data still at $E000
    lda zp_death_source
    cmp #DEATH_CURSED
    bcs !tgo_load_overlay+
    tax
    jsr creature_get_name

!tgo_load_overlay:
    // 2. Load death overlay at $0400
    lda #OVL_DEATH
    jsr overlay_load

    // 3. Calculate score
    jsr score_calculate

    // 4. Load high scores from disk (needs KERNAL)
    jsr hiscore_load

    // 5. Insert into high score table
    jsr hiscore_insert

    // 6. Save high scores to disk (needs KERNAL)
    jsr hiscore_save

    // 7. Display death screen
    jsr score_death_screen
    rts

// Bank1Data segment — content moved to banked_payload ($EB00, Bank 0).
// Segment kept empty; bank1.dat is no longer loaded at runtime.
.segment Bank1Data
.segment Default


// ============================================================
// game_over_prompt — R)EBOOT / S)TART OVER / Q)UIT prompt
// ============================================================
game_over_prompt:
    jsr screen_clear
    lda #COL_WHITE
    sta zp_text_color
    lda #12
    sta zp_cursor_row
    lda #9                      // Keep C64-style centering for MVP
    sta zp_cursor_col
    lda #<game_over_str
    sta zp_ptr0
    lda #>game_over_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #0
    sta KBDBUF_COUNT            // Flush keyboard buffer (C128: $D0)
!gop_loop:
    jsr input_get_key
    cmp #$52                    // 'R' — reboot (reset)
    beq !gop_reboot+
    cmp #$53                    // 'S' — start over (restart to title)
    beq !gop_restart+
    cmp #$51                    // 'Q' — quit to BASIC
    bne !gop_loop-
    rts                         // Q: fall through to exit_trampoline
!gop_reboot:
    lda #MMU_NORMAL             // $0E — expose KERNAL ROM reset vector
    sta $ff00
    jmp ($fffc)                 // Hard reset via KERNAL ROM vector
!gop_restart:
    jmp game_restart

game_over_str:
    .text "R)EBOOT  S)TART  Q)UIT" ; .byte 0

// ============================================================
// game_restart — reset game state, return to title screen
// ============================================================
game_restart:
    // Clear ZP game variables $2B–$8F
    lda #0
    ldx #0
!clr_zp:
    sta $2b,x
    inx
    cpx #($8f - $2b + 1)        // 101 bytes
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

    // Reset tier state
    sta current_tier
    sta tier_loaded

    jmp restart_entry


// ============================================================
// Banked code payload — stored inline here, copied to $EB00
// at startup by init_copy_banked. Runs in Bank 0 at $EB00-$FFFA.
// All Bank1Data functions (UI screens, home) are included here so
// they live in Bank 0 and are accessible with $FF00=$3E (MMU_ALL_RAM).
//
// Note: overlays load at $E000-$EFFF and overlap the early portion
// of this range ($EB00-$EFFF). This is intentional — functions in
// that range (special_rooms, ego_items) are only needed while an
// overlay is active. Gameplay UI functions live at $F000+ and are
// never overwritten by an overlay.
// ============================================================
banked_payload:
.pseudopc $EB00 {
    #import "../common/special_rooms.s"
    #import "../common/ego_items.s"
    #import "../common/title_sysinfo_banked.s"
    #import "../common/reu_loading_banked.s"
    #import "../common/string_bank_banked.s"
    #import "../common/ui_recall.s"
    #import "../common/ui_help_data.s"
    #import "../common/ui_help.s"
    #import "../common/ui_character.s"
    #import "../common/ui_inventory.s"
    #import "../common/ui_home.s"

banked_code_end:
}
banked_payload_end:

.print "Banked payload: " + (banked_payload_end - banked_payload) + " bytes at $" + toHexString(banked_payload) + "-$" + toHexString(banked_payload_end)
.assert "Banked code fits below CPU vectors", banked_code_end <= $FFFA, true

// ============================================================
// Safety: ensure runtime code doesn't overlap runtime data areas
program_end:
.assert "Program fits below System ROM", program_end <= BANKED_DATA_BASE, true


// ============================================================
// Init-only code — lives past CREATURE_BASE, safe because it runs
// once at startup before dungeon map or RLE workspace are used.
// ============================================================

// ============================================================
// Town overlay — store code at $E000, output to separate PRG
// ============================================================
.segment TownOverlay
    #import "../common/store.s"
    #import "../common/ui_store.s"
ovl_town_end:
.print "Town overlay: " + (ovl_town_end - $e000) + " bytes at $E000-$" + toHexString(ovl_town_end)
.assert "Town overlay fits in $E000-$EFFF", ovl_town_end <= $f000, true

// ============================================================
// Startup overlay — character creation at $E000
// ============================================================
.segment StartupOverlay
    #import "../common/background_data.s"
    #import "../common/player_create.s"
ovl_start_end:
.print "Startup overlay: " + (ovl_start_end - $e000) + " bytes at $E000-$" + toHexString(ovl_start_end)
.assert "Startup overlay fits in $E000-$EFFF", ovl_start_end <= $f000, true

// ============================================================
// Death overlay — score + high score display at $E000
// ============================================================
.segment DeathOverlay
    #import "../common/score.s"
ovl_death_end:
.print "Death overlay: " + (ovl_death_end - $e000) + " bytes at $E000-$" + toHexString(ovl_death_end)
.assert "Death overlay fits in $E000-$EFFF", ovl_death_end <= $f000, true

// ============================================================
// Dungeon generation overlay
// ============================================================
.segment DungeonGenOverlay
    #import "../common/dungeon_gen.s"
ovl_gen_end:
.print "DungeonGen overlay: " + (ovl_gen_end - $e000) + " bytes at $E000-$" + toHexString(ovl_gen_end)
.assert "DungeonGen overlay fits in $E000-$EFFF", ovl_gen_end <= $f000, true

