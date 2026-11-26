; ovl_storage.asm — Moria8 CP/M Save V2, Load, Drive Setup & High-Score Overlay
; (OVL_STORAGE = 12, DAT slot 11)
;
; Fixed vector jump table at OVL_WINDOW_BASE (0x5600):
;   +0:  JP ovl_storage_save_game     (CF=0 saved, CF=1 cancel/error)
;   +3:  JP ovl_storage_load_menu     (CF=0 loaded, CF=1 cancel/error)
;   +6:  JP ovl_storage_disk_setup    (Drive A:..P: selection via BIOS SELDSK probe)
;   +9:  JP ovl_storage_hiscore_load  (Read HISCORE.DAT from abi_save_drive)
;   +12: JP ovl_storage_hiscore_save  (Write HISCORE.DAT to abi_save_drive)
;
; Memory & CP/M 2.2 discipline:
; - Pure 0xNN hex constants (sjasmplus v1.24.0, DEVICE NOSLOT64K).
; - Zero static DS 128 buffers inside .ovl: LDIR-chunked streaming directly
;   through CPM_DMA_BUF_BASE (0xD080), UI formatting via line_buf/temp_str_buf.
; - Strict CP/M 2.2 FCB discipline:
;   * bdos_probe_drive(abi_save_drive) before BDOS open/delete/make so
;     unmounted drives never trip BDOS 14 "Bdos Err on X: Select".
;   * Atomic writes via FCB_TMP_ADDR (.TMP): delete stale .TMP -> BDOS 22 make
;     -> write & zero-pad -> BDOS 16 close -> BDOS 19 delete target ->
;     bdos_rename (.TMP -> .SAV/.DAT). On failure, close & delete .TMP +
;     bdos_reset_disk_recover, leaving prior .SAV/.DAT intact.
;   * Two-pass verified load: checks magic/version/length/checksum before RAM write.

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "item_ids_z80.inc"
    DEFINE HUFF_CONSTS_ONLY 1
    INCLUDE "huff_ascii.inc"
    UNDEFINE HUFF_CONSTS_ONLY
    INCLUDE "main_exp.inc"
    DEFINE MONSTER_IDX_CONSTS_ONLY 1
    INCLUDE "monster_idx_z80.inc"
    UNDEFINE MONSTER_IDX_CONSTS_ONLY

    ORG  OVL_WINDOW_BASE

ovl_start:
    JP   ovl_storage_save_game
    JP   ovl_storage_load_menu
    JP   ovl_storage_disk_setup
    JP   ovl_storage_hiscore_load
    JP   ovl_storage_hiscore_save

; ============================================================================
; Save Game Entry (+0) — CF=0 saved, CF=1 cancelled or I/O/drive error
; ============================================================================
ovl_storage_save_game:
    PUSH IX
    PUSH IY

    CALL player_sync_from_abi

    LD   A, (abi_save_drive)
    CALL bdos_probe_drive
    JR   NC, .save_drv_ok
    LD   A, HSTR_SAVE_NOT_READY
    LD   (ovl_storage_last_huff), A
    CALL screen_hard_clear
    JP   .save_err_wait

.save_drv_ok:
    CALL ovl_storage_draw_slot_menu

.save_prompt_loop:
.wait_save_key:
    CALL input_get_key
    CP   KEY_ESC
    JP   Z, .save_cancel
    CP   'q'
    JP   Z, .save_cancel
    CP   'Q'
    JP   Z, .save_cancel
    CP   '1'
    JR   C, .wait_save_key
    CP   '5'
    JR   NC, .wait_save_key

    SUB  '1'
    LD   (ovl_storage_cur_slot), A

    ; Confirm overwrite if slot already exists on disk
    CALL ovl_storage_slot_bit_a
    LD   HL, ovl_storage_slot_exist_mask
    AND  (HL)
    JR   Z, .do_write

    LD   B, INPUT_ROW
    CALL screen_clear_row
    LD   A, HSTR_SAVE_OVERWRITE
    LD   DE, line_buf
    CALL huff_decode_string
    LD   B, INPUT_ROW
    LD   C, 2
    LD   E, COL_YELLOW
    CALL screen_put_str
    CALL screen_flush
.wait_overwrite_key:
    CALL input_get_key
    CP   'y'
    JR   Z, .do_write
    CP   'Y'
    JR   Z, .do_write
    CP   'n'
    JR   Z, .save_cancel
    CP   'N'
    JR   Z, .save_cancel
    JR   .wait_overwrite_key

.do_write:
    ; Strip transient search/rest flags before serializing
    LD   A, (player_data + PL_FLAGS)
    AND  ~(PLF_SEARCHING | PLF_RESTING) & 0xFF
    LD   (player_data + PL_FLAGS), A
    XOR  A
    LD   (zp_search_count), A
    CALL player_sync_to_abi

    LD   A, HSTR_SAVE_SAVING
    LD   E, COL_CYAN
    CALL ovl_storage_show_status_huff
    CALL screen_flush

    LD   A, (ovl_storage_cur_slot)
    CALL ovl_storage_write_slot
    JR   C, .save_err_wait

    LD   A, (ovl_storage_cur_slot)
    LD   (save_slot_selected), A
    LD   A, HSTR_SAVE_DONE
    LD   E, COL_CYAN
    CALL ovl_storage_show_status_huff
    CALL screen_flush
    CALL screen_hard_clear
    OR   A
    POP  IY
    POP  IX
    RET

.save_err_wait:
    LD   A, (ovl_storage_last_huff)
    LD   E, COL_RED
    CALL ovl_storage_show_status_huff
    CALL screen_flush
    CALL input_get_key

.save_cancel:
    SCF
    POP  IY
    POP  IX
    RET

; ============================================================================
; Load Game Entry (+3) — CF=0 loaded, CF=1 cancelled or corrupt/error
; ============================================================================
ovl_storage_load_menu:
    PUSH IX
    PUSH IY

    LD   A, (abi_save_drive)
    CALL bdos_probe_drive
    JR   NC, .load_drv_ok
    LD   A, HSTR_SAVE_NOT_READY
    LD   (ovl_storage_last_huff), A
    CALL screen_hard_clear
    JP   .load_failed

.load_drv_ok:
    CALL ovl_storage_draw_slot_menu

.load_prompt_loop:
.wait_load_key:
    CALL input_get_key
    CP   KEY_ESC
    JP   Z, .load_cancel
    CP   'q'
    JP   Z, .load_cancel
    CP   'Q'
    JP   Z, .load_cancel
    CP   '1'
    JR   C, .wait_load_key
    CP   '5'
    JR   NC, .wait_load_key

    SUB  '1'
    LD   (ovl_storage_cur_slot), A

    ; Reject empty slot cleanly
    CALL ovl_storage_slot_bit_a
    LD   HL, ovl_storage_slot_exist_mask
    AND  (HL)
    JR   NZ, .try_load_slot

    LD   A, HSTR_SAVE_NOTFOUND
    LD   E, COL_RED
    CALL ovl_storage_show_status_huff
    CALL screen_flush
    CALL input_get_key
    LD   B, INPUT_ROW
    CALL screen_clear_row
    CALL screen_flush
    JR   .load_prompt_loop

.try_load_slot:
    LD   A, HSTR_SAVE_LOADING
    LD   E, COL_CYAN
    CALL ovl_storage_show_status_huff
    CALL screen_flush

    ; Pass 1: Verify magic, version, length, and checksum BEFORE modifying RAM
    LD   A, (ovl_storage_cur_slot)
    CALL ovl_storage_verify_slot
    JP   C, .load_failed

    ; Pass 2: Stream verified Save V2 blocks into RAM
    LD   A, (ovl_storage_cur_slot)
    CALL ovl_storage_apply_slot
    JP   C, .load_failed

    LD   A, (ovl_storage_cur_slot)
    LD   (save_slot_selected), A

    ; Normalize transient state and clamp loaded count fields safely
    LD   A, (player_data + PL_FLAGS)
    AND  ~(PLF_SEARCHING | PLF_RESTING) & 0xFF
    LD   (player_data + PL_FLAGS), A
    LD   A, 0xFF
    LD   (zp_run_dir), A

    ; Clamp loaded count fields safely
    LD   HL, room_count
    LD   B, MAX_ROOMS
    CALL ovl_storage_clamp_u8
    LD   HL, trap_count
    LD   B, MAX_TRAPS
    CALL ovl_storage_clamp_u8

    ; Sanitize loaded 9-bit item IDs and recount entities from tables
    CALL ovl_storage_sanitize_all_ids
    CALL ovl_storage_recount_monsters
    CALL ovl_storage_recount_floor_items

    ; Clear all STORE_COUNT (8) hg_kicked slots & all MAX_GLYPHS (4) active flags
    LD   HL, hg_kicked
    LD   DE, hg_kicked + 1
    LD   BC, STORE_COUNT - 1
    LD   (HL), 0
    LDIR

    LD   HL, glyph_active
    LD   DE, glyph_active + 1
    LD   BC, MAX_GLYPHS - 1
    LD   (HL), 0
    LDIR

    ; Clear M4/transient state & restore town/dungeon monster catalog slots
    XOR  A
    LD   (zp_search_count), A
    LD   (wizard_wall_walk_active), A
    LD   (recall_query_sc), A
    LD   (recall_last_sc), A
    LD   (recall_last_cat_lo), A
    LD   (recall_last_cat_hi), A
    LD   (md_queue_count), A
    LD   (eff_invuln_timer), A
    LD   (eff_detect_timer), A
    LD   (eff_detect_evil_mode), A
    LD   (muv_clear_detected), A
    LD   (muv_changed), A
    LD   A, 1
    LD   (game_loaded_flag), A
    CALL catalog_init_town_creatures
    ; Reject corrupted save cat_slot_id >= CATALOG_COUNT (279) before refetch
    LD   B, CAT_SLOTS
    LD   HL, cat_slot_id_hi
.chk_cat:
    LD   A, (HL)
    BIT  7, A
    JR   NZ, .cat_ok
    PUSH HL
    LD   DE, cat_slot_id_lo - cat_slot_id_hi
    ADD  HL, DE
    LD   E, (HL)
    LD   D, A
    LD   HL, CATALOG_COUNT - 1
    OR   A
    SBC  HL, DE
    POP  HL
    JR   NC, .cat_ok
    LD   (HL), 0xFF
.cat_ok:
    INC  HL
    DJNZ .chk_cat
    CALL catalog_refetch_slots

    ; Recompute PL_*_CUR & 118/3 cap residuals from base + equipment (matching 6502 load_resume_game player_calc_stats)
    CALL msg_init
    CALL id_refresh_fixed_known
    CALL inv_calc_weight
    CALL player_sync_eq_stat_mod
    LD   C, 0
.res_lp:
    LD   B, 0
    LD   HL, player_data + PL_STR_BASE
    ADD  HL, BC
    LD   A, (HL)
    LD   HL, player_eq_stat_mod
    ADD  HL, BC
    ADD  A, (HL)
    CALL player_clamp_stat_a        ; A = clamped [3..118], E = signed residual
    LD   HL, player_data + PL_STR_CUR
    ADD  HL, BC
    LD   (HL), A
    LD   HL, player_stat_res
    ADD  HL, BC
    LD   (HL), E
    INC  C
    LD   A, C
    CP   STAT_COUNT
    JR   C, .res_lp
    CALL player_calc_hp
    CALL player_calc_combat
    CALL player_sync_to_abi
    CALL viewport_center_on_player
    CALL status_mark_dirty
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    CALL screen_hard_clear

    OR   A
    POP  IY
    POP  IX
    RET

.load_failed:
    LD   A, (ovl_storage_last_huff)
    LD   E, COL_RED
    CALL ovl_storage_show_status_huff
    CALL screen_flush
    CALL input_get_key

.load_cancel:
    SCF
    POP  IY
    POP  IX
    RET

; ============================================================================
; Drive Setup Entry (+6) — 6502 1/2/3/Q Menu + CP/M BIOS SELDSK A:..P: Probe
; ============================================================================
ovl_storage_disk_setup:
    PUSH IX
    PUSH IY

.disk_redraw:
    CALL screen_hard_clear
    LD   B, 0
    LD   C, 35
    LD   E, COL_WHITE
    LD   HL, ovl_storage_str_disk_hdr
    CALL screen_put_str

    ; Row 2: Program: X:
    LD   B, 2
    LD   C, 28
    LD   E, COL_CYAN
    LD   HL, ovl_storage_str_prog_drv
    CALL screen_put_str
    LD   A, (abi_program_drive)
    ADD  A, 'A'
    LD   B, 2
    LD   C, 37
    LD   E, COL_CYAN
    CALL screen_put_char
    LD   B, 2
    LD   C, 38
    LD   A, ':'
    LD   E, COL_CYAN
    CALL screen_put_char

    ; Row 3: Save:    Y:
    LD   B, 3
    LD   C, 28
    LD   E, COL_CYAN
    LD   HL, ovl_storage_str_save_drv
    CALL screen_put_str
    LD   A, (abi_save_drive)
    ADD  A, 'A'
    LD   B, 3
    LD   C, 37
    LD   E, COL_CYAN
    CALL screen_put_char
    LD   B, 3
    LD   C, 38
    LD   A, ':'
    LD   E, COL_CYAN
    CALL screen_put_char

    ; Menu options rows 5..8 matching core/6502/ui_disk_setup.s
    LD   B, 5
    LD   C, 28
    LD   E, COL_WHITE
    LD   HL, ovl_storage_str_ds_opt1
    CALL screen_put_str
    LD   B, 6
    LD   C, 28
    LD   E, COL_WHITE
    LD   HL, ovl_storage_str_ds_opt2
    CALL screen_put_str
    LD   B, 7
    LD   C, 28
    LD   E, COL_WHITE
    LD   HL, ovl_storage_str_ds_opt3
    CALL screen_put_str
    LD   B, 8
    LD   C, 28
    LD   E, COL_WHITE
    LD   HL, ovl_storage_str_ds_optq
    CALL screen_put_str
    CALL screen_flush

.disk_key_loop:
    CALL input_get_key
    CP   '1'
    JR   NZ, .chk_opt2
    LD   A, (abi_program_drive)
    LD   (abi_save_drive), A
    LD   A, 1
    LD   (disk_setup_done), A
    JP   .disk_redraw

.chk_opt2:
    CP   '2'
    JR   NZ, .chk_opt3
    LD   B, 10
    LD   C, 28
    LD   E, COL_YELLOW
    LD   HL, ovl_storage_str_disk_hint
    CALL screen_put_str
    CALL screen_flush
.pick_drv_key:
    CALL input_get_key
    CP   KEY_ESC
    JP   Z, .disk_redraw
    CP   'q'
    JP   Z, .disk_redraw
    CP   'Q'
    JP   Z, .disk_redraw

.pick_drv_fold:
    CP   'a'
    JR   C, .chk_drv_upper
    CP   'z' + 1
    JR   NC, .chk_drv_upper
    AND  0xDF
.chk_drv_upper:
    CP   'A'
    JR   C, .pick_drv_key
    CP   'P' + 1
    JR   NC, .pick_drv_key

    SUB  'A'
    LD   (ovl_storage_tmp_drv), A

    ; Non-fatal BIOS SELDSK probe (restores abi_program_drive & fcb_dat cleanly)
    CALL bdos_probe_drive
    JR   NC, .drv_valid

    LD   A, HSTR_SAVE_NOT_READY
    LD   E, COL_RED
    CALL ovl_storage_show_status_huff
    CALL screen_flush
    CALL input_get_key
    JP   .disk_redraw

.drv_valid:
    LD   A, (ovl_storage_tmp_drv)
    LD   (abi_save_drive), A
    LD   A, 1
    LD   (disk_setup_done), A
    JP   .disk_redraw

.chk_opt3:
    CP   '3'
    JR   Z, .disk_accept_done
    CP   KEY_CR
    JR   Z, .disk_accept_done
    CP   KEY_ESC
    JR   Z, .disk_done
    CP   'q'
    JR   Z, .disk_done
    CP   'Q'
    JR   Z, .disk_done
    JP   .disk_key_loop

.disk_accept_done:
    LD   A, 1
    LD   (disk_setup_done), A
.disk_done:
    OR   A
    POP  IY
    POP  IX
    RET

; ============================================================================
; High-Score Load (+9) — Read HISCORE.DAT on abi_save_drive
; Missing file -> hiscore_count = 0, CF = 0. Unmounted/corrupt -> count = 0, CF = 1.
; ============================================================================
ovl_storage_hiscore_load:
    PUSH IX
    PUSH IY

    XOR  A
    LD   (hiscore_count), A
    CALL ovl_storage_clear_hiscore_tbl

    LD   A, (abi_save_drive)
    CALL bdos_probe_drive
    JR   NC, .hs_drv_ok
    SCF
    POP  IY
    POP  IX
    RET

.hs_drv_ok:
    CALL bdos_reset_dma_default
    CALL ovl_storage_init_hs_fcb
    LD   DE, FCB_SAVE_ADDR
    CALL bdos_open
    JR   NC, .hs_opened
    ; Missing HISCORE.DAT is clean empty high-score state (CF = 0)
    OR   A
    POP  IY
    POP  IX
    RET

.hs_opened:
    XOR  A
    LD   (FCB_SAVE_ADDR + 32), A
    LD   A, CPM_RECORD_SIZE
    LD   (ovl_storage_dma_pos), A

    ; Check 3-byte magic 'M', 'H', 0x01
    CALL ovl_storage_get_raw_byte
    JR   C, .hs_load_err
    CP   'M'
    JR   NZ, .hs_load_err
    CALL ovl_storage_get_raw_byte
    JR   C, .hs_load_err
    CP   'H'
    JR   NZ, .hs_load_err
    CALL ovl_storage_get_raw_byte
    JR   C, .hs_load_err
    CP   0x01
    JR   NZ, .hs_load_err

    ; Read entry count (0..HISCORE_MAX_ENTRIES)
    CALL ovl_storage_get_raw_byte
    JR   C, .hs_load_err
    CP   HISCORE_MAX_ENTRIES + 1
    JR   NC, .hs_load_err
    LD   (ovl_storage_hs_tmp_cnt), A
    OR   A
    JR   Z, .hs_read_ok

    ASSERT (HISCORE_MAX_ENTRIES * HISCORE_ENTRY_SIZE) <= 255

    ; Read count * HISCORE_ENTRY_SIZE (<= 230 B) via chunked LDIR reader
    LD   B, A
    XOR  A
.hs_mul_loop:
    ADD  A, HISCORE_ENTRY_SIZE
    DJNZ .hs_mul_loop
    LD   C, A
    LD   B, 0
    LD   HL, hiscore_table
    CALL ovl_storage_read_mem_raw
    JR   C, .hs_load_err

.hs_read_ok:
    LD   A, (ovl_storage_hs_tmp_cnt)
    LD   (hiscore_count), A
    LD   DE, FCB_SAVE_ADDR
    CALL bdos_close
    OR   A
    POP  IY
    POP  IX
    RET

.hs_load_err:
    LD   DE, FCB_SAVE_ADDR
    CALL bdos_close
    XOR  A
    LD   (hiscore_count), A
    CALL ovl_storage_clear_hiscore_tbl
    SCF
    POP  IY
    POP  IX
    RET

; ============================================================================
; High-Score Save (+12) — Atomic write HISCORE.TMP -> rename HISCORE.DAT
; ============================================================================
ovl_storage_hiscore_save:
    PUSH IX
    PUSH IY

    LD   A, (abi_save_drive)
    CALL bdos_probe_drive
    JR   NC, .hs_wr_drv_ok
    SCF
    POP  IY
    POP  IX
    RET

.hs_wr_drv_ok:
    LD   A, (hiscore_count)
    CP   HISCORE_MAX_ENTRIES + 1
    JR   C, .hs_cnt_ok
    LD   A, HISCORE_MAX_ENTRIES
    LD   (hiscore_count), A
.hs_cnt_ok:
    LD   (ovl_storage_hs_tmp_cnt), A

    ; Prepare temp_str_buf with HISCORE.TMP and open FCB_TMP_ADDR
    LD   HL, ovl_storage_hs_tmp_name11
    LD   DE, temp_str_buf
    LD   BC, 11
    LDIR
    CALL ovl_storage_prep_tmp_write
    JR   C, .hs_make_fail

    ; Header: 'M', 'H', 0x01, count
    LD   A, 'M'
    CALL ovl_storage_put_raw_byte
    JR   C, .hs_wr_abort
    LD   A, 'H'
    CALL ovl_storage_put_raw_byte
    JR   C, .hs_wr_abort
    LD   A, 0x01
    CALL ovl_storage_put_raw_byte
    JR   C, .hs_wr_abort
    LD   A, (ovl_storage_hs_tmp_cnt)
    CALL ovl_storage_put_raw_byte
    JR   C, .hs_wr_abort

    LD   A, (ovl_storage_hs_tmp_cnt)
    OR   A
    JR   Z, .hs_flush
    LD   B, A
    XOR  A
.hs_wr_mul:
    ADD  A, HISCORE_ENTRY_SIZE
    DJNZ .hs_wr_mul
    LD   C, A
    LD   B, 0
    LD   HL, hiscore_table
    CALL ovl_storage_write_mem_ck
    JR   C, .hs_wr_abort

.hs_flush:
    CALL ovl_storage_flush_dma_zero_pad
    JR   C, .hs_wr_abort

    ; Commit HISCORE.TMP -> HISCORE.DAT atomically
    CALL ovl_storage_init_hs_fcb
    CALL ovl_storage_commit_tmp
    JR   C, .hs_save_done_err

    OR   A
    POP  IY
    POP  IX
    RET

.hs_wr_abort:
    CALL ovl_storage_abort_tmp
    JR   .hs_save_done_err
.hs_make_fail:
    LD   A, (abi_program_drive)
    CALL bdos_reset_disk_recover
.hs_save_done_err:
    SCF
    POP  IY
    POP  IX
    RET

; ============================================================================
; Save / Load UI & Slot Peeking Helpers
; ============================================================================

; Draw Save Slots menu matching core/6502/save_slot_menu.s layout (80-col centered).
ovl_storage_draw_slot_menu:
    CALL screen_hard_clear
    LD   B, 9
    LD   C, 34
    LD   E, COL_WHITE
    LD   HL, ovl_storage_str_slots_hdr
    CALL screen_put_str

    XOR  A
    LD   (ovl_storage_slot_exist_mask), A
    LD   B, 0                   ; B = slot index 0..3
.peek_loop:
    PUSH BC
    CALL ovl_storage_peek_one_slot
    POP  BC
    INC  B
    LD   A, B
    CP   SAVE_SLOT_COUNT
    JR   C, .peek_loop

    LD   B, 16
    LD   C, 32
    LD   E, COL_WHITE
    LD   HL, ovl_storage_str_pick_slot
    CALL screen_put_str
    CALL screen_flush
    RET

; Peek SAVE{B}.SAV record 0 into CPM_DMA_BUF_BASE and print row 11 + B at col 30.
ovl_storage_peek_one_slot:
    LD   A, B
    LD   (ovl_storage_tmp_slot), A

    ; Row = 11 + slot
    ADD  A, 11
    LD   (ovl_storage_tmp_row), A

    ; Print "1) " .. "4) " with '*' marker on active save_slot_selected
    LD   B, A
    LD   C, 30
    LD   A, (ovl_storage_tmp_slot)
    ADD  A, '1'
    LD   E, COL_WHITE
    CALL screen_put_char
    LD   A, (ovl_storage_tmp_row)
    LD   B, A
    LD   C, 31
    LD   A, ')'
    LD   E, COL_WHITE
    CALL screen_put_char
    LD   A, (ovl_storage_tmp_row)
    LD   B, A
    LD   C, 32
    LD   A, ' '
    LD   E, COL_WHITE
    CALL screen_put_char
    LD   A, (save_slot_selected)
    LD   HL, ovl_storage_tmp_slot
    CP   (HL)
    LD   A, ' '
    JR   NZ, .put_star
    LD   A, '*'
.put_star:
    PUSH AF
    LD   A, (ovl_storage_tmp_row)
    LD   B, A
    POP  AF
    LD   C, 33
    LD   E, COL_WHITE
    CALL screen_put_char

    CALL bdos_reset_dma_default
    LD   A, (ovl_storage_tmp_slot)
    CALL ovl_storage_init_slot_fcb
    LD   DE, FCB_SAVE_ADDR
    CALL bdos_open
    JR   NC, .peek_read_rec0

    ; File missing -> "Empty"
.peek_empty:
    LD   A, (ovl_storage_tmp_row)
    LD   B, A
    LD   C, 34
    LD   E, COL_WHITE
    LD   HL, ovl_storage_str_empty
    JP   screen_put_str

.peek_read_rec0:
    XOR  A
    LD   (FCB_SAVE_ADDR + 32), A
    LD   C, BDOS_READSEQ
    LD   DE, FCB_SAVE_ADDR
    CALL bdos_call
    PUSH AF
    LD   DE, FCB_SAVE_ADDR
    CALL bdos_close
    POP  AF

    ; Record present bit even if invalid so Save confirms overwrite and Load rejects corrupt
    PUSH AF
    LD   A, (ovl_storage_tmp_slot)
    CALL ovl_storage_slot_bit_a
    LD   HL, ovl_storage_slot_exist_mask
    OR   (HL)
    LD   (HL), A
    POP  AF

    OR   A
    JR   NZ, .peek_empty

    ; Check magic header in CPM_DMA_BUF_BASE[0..7]
    LD   HL, CPM_DMA_BUF_BASE
    LD   DE, ovl_storage_magic
    LD   B, 8
.peek_cmp_hdr:
    LD   A, (DE)
    CP   (HL)
    JR   NZ, .peek_empty
    INC  HL
    INC  DE
    DJNZ .peek_cmp_hdr

    ; Copy up to 16 chars of PL_NAME into line_buf
    LD   DE, line_buf
    LD   HL, CPM_DMA_BUF_BASE + 8 + PL_NAME
    LD   B, 16
.peek_name:
    LD   A, (HL)
    OR   A
    JR   Z, .peek_name_done
    CP   0x20
    JR   C, .peek_name_done
    LD   (DE), A
    INC  HL
    INC  DE
    DJNZ .peek_name
.peek_name_done:
    LD   A, (line_buf)
    OR   A
    JR   Z, .peek_empty
    XOR  A
    LD   (DE), A
    LD   A, (ovl_storage_tmp_row)
    LD   B, A
    LD   C, 34
    LD   E, COL_WHITE
    LD   HL, line_buf
    JP   screen_put_str

; ============================================================================
; Save V2 Atomic Stream Writer (17,164 B = 135 recs via SAVE{A}.TMP -> .SAV)
; ============================================================================
ovl_storage_write_slot:
    LD   (ovl_storage_tmp_slot), A
    LD   A, HSTR_SAVE_IOERR
    LD   (ovl_storage_last_huff), A

    LD   A, (abi_save_drive)
    CALL bdos_probe_drive
    JR   NC, .wr_drv_ok
    LD   A, HSTR_SAVE_NOT_READY
    LD   (ovl_storage_last_huff), A
    SCF
    RET

.wr_drv_ok:
    ; Populate temp_str_buf with "SAVE{slot}   TMP" and create FCB_TMP_ADDR
    LD   HL, ovl_storage_slot_tmp_tmpl
    LD   DE, temp_str_buf
    LD   BC, 11
    LDIR
    LD   A, (ovl_storage_tmp_slot)
    ADD  A, '0'
    LD   (temp_str_buf + 4), A

    CALL ovl_storage_prep_tmp_write
    JR   NC, .wr_make_ok
    LD   A, HSTR_SAVE_DISK_FULL
    LD   (ovl_storage_last_huff), A
    LD   A, (abi_program_drive)
    CALL bdos_reset_disk_recover
    SCF
    RET

.wr_make_ok:
    LD   HL, 0
    LD   (ovl_storage_cksum), HL

    ; 1. Write 8-byte header ("MORIA01" + 0x22)
    LD   HL, ovl_storage_magic
    LD   BC, 8
    CALL ovl_storage_write_mem_ck
    JR   C, .wr_abort_write

    ; 2. Write head descriptor blocks (2,508 B)
    LD   HL, ovl_sav_desc_head
    LD   B, OVL_SAV_HEAD_ENTRIES
    CALL ovl_storage_write_desc_tbl
    JR   C, .wr_abort_write

    ; 3. Write floor items (462 B = 11 * 42 in exact platforms/shared/save.s order)
    CALL ovl_storage_write_floor_items
    JR   C, .wr_abort_write

    ; 4. Write tail descriptor blocks (recall_data 1,116 + MAP_BASE 13,068 = 14,184 B)
    LD   HL, ovl_sav_desc_tail
    LD   B, OVL_SAV_TAIL_ENTRIES
    CALL ovl_storage_write_desc_tbl
    JR   C, .wr_abort_write

    ; 5. Write trailing 2-byte LE checksum (NOT accumulated into checksum!)
    LD   A, (ovl_storage_cksum)
    CALL ovl_storage_put_raw_byte
    JR   C, .wr_abort_write
    LD   A, (ovl_storage_cksum + 1)
    CALL ovl_storage_put_raw_byte
    JR   C, .wr_abort_write

    ; 6. Flush final partial record (zero-pad remainder of 135th record)
    CALL ovl_storage_flush_dma_zero_pad
    JR   C, .wr_abort_write

    ; 7. Commit SAVE{slot}.TMP -> SAVE{slot}.SAV (preserving old .SAV until rename)
    ; Save temp_str_buf in FCB_TMP_ADDR already; init FCB_SAVE_ADDR without
    ; clobbering temp_str_buf! (Use bdos_init_fcb_name directly with line_buf!)
    LD   A, (ovl_storage_tmp_slot)
    CALL ovl_storage_init_slot_fcb_preserve_tmp
    CALL ovl_storage_commit_tmp
    JR   C, .wr_fail_done

    OR   A
    RET

.wr_abort_write:
    CALL ovl_storage_abort_tmp
.wr_fail_done:
    LD   A, HSTR_SAVE_IOERR
    LD   (ovl_storage_last_huff), A
    SCF
    RET

; ============================================================================
; Save V2 Two-Pass Verifier & Loader (LDIR-chunked)
; ============================================================================

; Pass 1: Verify magic, version, length, and 16-bit checksum BEFORE modifying RAM.
ovl_storage_verify_slot:
    LD   (ovl_storage_tmp_slot), A
    LD   A, HSTR_SAVE_CORRUPT
    LD   (ovl_storage_last_huff), A

    CALL bdos_reset_dma_default
    LD   A, (ovl_storage_tmp_slot)
    CALL ovl_storage_init_slot_fcb
    LD   DE, FCB_SAVE_ADDR
    CALL bdos_open
    JR   NC, .vfy_opened
    LD   A, HSTR_SAVE_NOTFOUND
    LD   (ovl_storage_last_huff), A
    SCF
    RET

.vfy_opened:
    XOR  A
    LD   (FCB_SAVE_ADDR + 32), A
    LD   A, CPM_RECORD_SIZE
    LD   (ovl_storage_dma_pos), A
    LD   HL, 0
    LD   (ovl_storage_cksum), HL

    ; Verify 7-byte magic "MORIA01" (accumulating checksum)
    LD   HL, ovl_storage_magic
    LD   B, 7
.vfy_magic:
    CALL ovl_storage_get_byte_ck
    JR   C, .vfy_io_close
    CP   (HL)
    JR   NZ, .vfy_bad_magic
    INC  HL
    DJNZ .vfy_magic

    ; Verify version byte == SAVE_VERSION (0x22)
    CALL ovl_storage_get_byte_ck
    JR   C, .vfy_io_close
    CP   SAVE_VERSION
    JR   NZ, .vfy_bad_ver

    ; Stream remaining payload bytes directly from DMA records via inline sum,
    ; validating door_state_count (<= MAX_DOOR_STATES) during Pass 1 before touching RAM
    LD   BC, OVL_SAV_PRE_DOORS_BYTES
    CALL ovl_storage_verify_body_ck
    JR   C, .vfy_corrupt_close
    CALL ovl_storage_get_byte_ck
    JR   C, .vfy_corrupt_close
    CP   MAX_DOOR_STATES + 1
    JR   NC, .vfy_corrupt_close
    LD   BC, SAVE_STREAM_BYTES - 2 - 8 - OVL_SAV_PRE_DOORS_BYTES - 1
    CALL ovl_storage_verify_body_ck
    JR   C, .vfy_corrupt_close

    ; Save computed checksum in DE, read trailing 2-byte checksum into HL
    LD   DE, (ovl_storage_cksum)
    CALL ovl_storage_get_raw_byte
    JR   C, .vfy_corrupt_close
    LD   L, A
    CALL ovl_storage_get_raw_byte
    JR   C, .vfy_corrupt_close
    LD   H, A

    OR   A
    SBC  HL, DE
    JR   NZ, .vfy_corrupt_close

    LD   DE, FCB_SAVE_ADDR
    CALL bdos_close
    OR   A
    RET

.vfy_bad_magic:
    LD   A, HSTR_SAVE_CORRUPT
    LD   (ovl_storage_last_huff), A
    JR   .vfy_close_err
.vfy_bad_ver:
    LD   A, HSTR_SAVE_UNSUPPORTED
    LD   (ovl_storage_last_huff), A
    JR   .vfy_close_err
.vfy_io_close:
    LD   A, HSTR_SAVE_IOERR
    LD   (ovl_storage_last_huff), A
    JR   .vfy_close_recover
.vfy_corrupt_close:
    LD   A, HSTR_SAVE_CORRUPT
    LD   (ovl_storage_last_huff), A
.vfy_close_err:
    LD   DE, FCB_SAVE_ADDR
    CALL bdos_close
    SCF
    RET
.vfy_close_recover:
    LD   A, (abi_program_drive)
    CALL bdos_reset_disk_recover
    SCF
    RET

; Pass 2: Read verified Save V2 file directly into RAM via LDIR chunks.
ovl_storage_apply_slot:
    LD   (ovl_storage_tmp_slot), A
    LD   A, HSTR_SAVE_IOERR
    LD   (ovl_storage_last_huff), A

    CALL bdos_reset_dma_default
    LD   A, (ovl_storage_tmp_slot)
    CALL ovl_storage_init_slot_fcb
    LD   DE, FCB_SAVE_ADDR
    CALL bdos_open
    JR   C, .app_fail_recover

    XOR  A
    LD   (FCB_SAVE_ADDR + 32), A
    LD   A, CPM_RECORD_SIZE
    LD   (ovl_storage_dma_pos), A

    ; Skip 8-byte verified header
    LD   B, 8
.app_skip_hdr:
    CALL ovl_storage_get_raw_byte
    JR   C, .app_fail_recover
    DJNZ .app_skip_hdr

    ; Read head descriptors (2,508 B)
    LD   HL, ovl_sav_desc_head
    LD   B, OVL_SAV_HEAD_ENTRIES
    CALL ovl_storage_read_desc_tbl
    JR   C, .app_fail_recover

    ; Read floor items (462 B)
    CALL ovl_storage_read_floor_items
    JR   C, .app_fail_recover

    ; Read tail descriptors (recall_data + MAP_BASE = 14,184 B)
    LD   HL, ovl_sav_desc_tail
    LD   B, OVL_SAV_TAIL_ENTRIES
    CALL ovl_storage_read_desc_tbl
    JR   C, .app_fail_recover

    LD   DE, FCB_SAVE_ADDR
    CALL bdos_close
    OR   A
    RET

.app_fail_recover:
    LD   A, (abi_program_drive)
    CALL bdos_reset_disk_recover
    SCF
    RET

; ============================================================================
; Floor-Item Serializer & Deserializer (462 B = 11 x 42 B exact save.s order)
; Order: fi_item_id, fi_x, fi_y, fi_qty, fi_meta_hi,
;        qty_hi, p1, fi_meta, fi_to_hit, fi_to_dam, fi_to_ac.
; ============================================================================
ovl_storage_write_floor_items:
    LD   HL, fi_item_id
    LD   BC, MAX_FLOOR_ITEMS * 4
    CALL ovl_storage_write_mem_ck
    RET  C
    LD   HL, fi_meta_hi
    LD   BC, MAX_FLOOR_ITEMS
    CALL ovl_storage_write_mem_ck
    RET  C

    ; 6. qty_hi[0..41]: fi_p1[i] for Page-0 gold, else 0
    LD   C, 0
.wfi_qty_hi:
    CALL ovl_storage_is_floor_gold
    LD   A, 0
    JR   NC, .wfi_qty_emit
    LD   HL, fi_p1
    LD   B, 0
    ADD  HL, BC
    LD   A, (HL)
.wfi_qty_emit:
    CALL ovl_storage_put_byte
    RET  C
    INC  C
    LD   A, C
    CP   MAX_FLOOR_ITEMS
    JR   C, .wfi_qty_hi

    ; 7. p1[0..41]: 0 for Page-0 gold, else fi_p1[i]
    LD   C, 0
.wfi_p1:
    CALL ovl_storage_is_floor_gold
    LD   A, 0
    JR   C, .wfi_p1_emit
    LD   HL, fi_p1
    LD   B, 0
    ADD  HL, BC
    LD   A, (HL)
.wfi_p1_emit:
    CALL ovl_storage_put_byte
    RET  C
    INC  C
    LD   A, C
    CP   MAX_FLOOR_ITEMS
    JR   C, .wfi_p1

    ; 8. fi_meta[0..41]
    LD   HL, fi_meta
    LD   BC, MAX_FLOOR_ITEMS
    CALL ovl_storage_write_mem_ck
    RET  C

    ; 9..11. fi_to_hit, fi_to_dam, fi_to_ac (3 * 42 = 126 B contiguous)
    LD   HL, fi_to_hit
    LD   BC, MAX_FLOOR_ITEMS * 3
    JP   ovl_storage_write_mem_ck

ovl_storage_read_floor_items:
    LD   HL, fi_item_id
    LD   BC, MAX_FLOOR_ITEMS * 4
    CALL ovl_storage_read_mem_raw
    RET  C
    LD   HL, fi_meta_hi
    LD   BC, MAX_FLOOR_ITEMS
    CALL ovl_storage_read_mem_raw
    RET  C

    ; 6. Read qty_hi[0..41] into fi_p1[0..41]
    LD   HL, fi_p1
    LD   BC, MAX_FLOOR_ITEMS
    CALL ovl_storage_read_mem_raw
    RET  C

    ; 7. Read p1[0..41]: preserve fi_p1[i] if Page-0 gold, else store incoming byte
    LD   C, 0
.rfi_p1:
    CALL ovl_storage_get_raw_byte
    RET  C
    LD   E, A
    CALL ovl_storage_is_floor_gold
    JR   C, .rfi_next_p1
    LD   HL, fi_p1
    LD   B, 0
    ADD  HL, BC
    LD   (HL), E
.rfi_next_p1:
    INC  C
    LD   A, C
    CP   MAX_FLOOR_ITEMS
    JR   C, .rfi_p1

    ; 8. fi_meta[0..41]
    LD   HL, fi_meta
    LD   BC, MAX_FLOOR_ITEMS
    CALL ovl_storage_read_mem_raw
    RET  C

    ; 9..11. fi_to_hit, fi_to_dam, fi_to_ac
    LD   HL, fi_to_hit
    LD   BC, MAX_FLOOR_ITEMS * 3
    JP   ovl_storage_read_mem_raw

; CF = 1 iff floor slot C (0..41) is Page-0 gold (id <= ITEM_SLOT_GOLD_MITHRIL, !ITEM_PAGE_BIT)
; Preserves BC, DE.
ovl_storage_is_floor_gold:
    LD   B, 0
    LD   HL, fi_meta_hi
    ADD  HL, BC
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    JR   NZ, .not_gold
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   ITEM_SLOT_GOLD_MITHRIL + 1
    RET                         ; CF=1 iff A <= 19
.not_gold:
    OR   A                      ; CF=0
    RET

; ============================================================================
; Low-Level Atomic Temp-File & LDIR-Chunked Streaming Helpers
; ============================================================================

; Delete stale .TMP, re-init FCB_TMP_ADDR from temp_str_buf[0..10], BDOS 22 MAKE.
; Output: CF=0 ready at CR=0 / dma_pos=0, CF=1 MAKE error.
ovl_storage_prep_tmp_write:
    CALL bdos_reset_dma_default
    CALL .init_tmp
    LD   C, BDOS_DELETE
    LD   DE, FCB_TMP_ADDR
    CALL bdos_call
    CALL .init_tmp
    LD   C, BDOS_MAKE
    LD   DE, FCB_TMP_ADDR
    CALL bdos_call
    CP   0xFF
    JR   Z, .make_fail
    XOR  A
    LD   (FCB_TMP_ADDR + 32), A
    LD   (ovl_storage_dma_pos), A
    OR   A
    RET
.make_fail:
    SCF
    RET
.init_tmp:
    LD   HL, FCB_TMP_ADDR
    LD   DE, temp_str_buf
    LD   A, (abi_save_drive)
    INC  A
    JP   bdos_init_fcb_name

; Commit closed FCB_TMP_ADDR (temp_str_buf = old 11-char name) -> FCB_SAVE_ADDR target.
; Input: temp_str_buf[0..10] = .TMP 8.3 name, FCB_SAVE_ADDR initialized to final name.
ovl_storage_commit_tmp:
    LD   DE, FCB_TMP_ADDR
    CALL bdos_close
    JR   C, ovl_storage_abort_tmp

    ; Delete old target file strictly before BDOS 23 rename
    LD   C, BDOS_DELETE
    LD   DE, FCB_SAVE_ADDR
    CALL bdos_call

    ; Construct CP/M 2.2 rename FCB in FCB_TMP_ADDR (+0..+11 old, +16..+27 new)
    LD   HL, FCB_TMP_ADDR
    LD   DE, temp_str_buf
    LD   A, (abi_save_drive)
    INC  A
    CALL bdos_init_fcb_name

    LD   HL, FCB_SAVE_ADDR
    LD   DE, FCB_TMP_ADDR + 16
    LD   BC, 12
    LDIR

    LD   DE, FCB_TMP_ADDR
    CALL bdos_rename
    RET  NC

; Close & delete .TMP on failure and run bdos_reset_disk_recover, returning CF=1.
ovl_storage_abort_tmp:
    LD   DE, FCB_TMP_ADDR
    CALL bdos_close
    LD   HL, FCB_TMP_ADDR
    LD   DE, temp_str_buf
    LD   A, (abi_save_drive)
    INC  A
    CALL bdos_init_fcb_name
    LD   C, BDOS_DELETE
    LD   DE, FCB_TMP_ADDR
    CALL bdos_call
    LD   A, (abi_program_drive)
    CALL bdos_reset_disk_recover
    SCF
    RET

; Write B descriptor entries (DW addr, DW len) from HL with checksum
ovl_storage_write_desc_tbl:
.wd_loop:
    PUSH BC
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    INC  HL
    LD   C, (HL)
    INC  HL
    LD   B, (HL)
    INC  HL
    PUSH HL
    EX   DE, HL                 ; HL = src addr, BC = byte len
    CALL ovl_storage_write_mem_ck
    POP  HL
    POP  BC
    RET  C
    DJNZ .wd_loop
    OR   A
    RET

; Read B descriptor entries (DW addr, DW len) from HL into RAM
ovl_storage_read_desc_tbl:
.rd_loop:
    PUSH BC
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    INC  HL
    LD   C, (HL)
    INC  HL
    LD   B, (HL)
    INC  HL
    PUSH HL
    EX   DE, HL                 ; HL = dst addr, BC = byte len
    CALL ovl_storage_read_mem_raw
    POP  HL
    POP  BC
    RET  C
    DJNZ .rd_loop
    OR   A
    RET

; Compute A = min(BC, CPM_RECORD_SIZE - dma_pos) in 1..128. Preserves BC, HL; clobbers E.
ovl_storage_chunk_len:
    LD   A, (ovl_storage_dma_pos)
    LD   E, A
    LD   A, CPM_RECORD_SIZE
    SUB  E
    LD   E, A
    LD   A, B
    OR   A
    LD   A, E
    RET  NZ
    LD   A, C
    CP   E
    RET  C
    LD   A, E
    RET

; Accumulate B (1..128) bytes from HL into (ovl_storage_cksum).
; Clobbers AF, B, DE, HL.
ovl_storage_accum_chunk:
    LD   DE, (ovl_storage_cksum)
.ac_lp:
    LD   A, E
    ADD  A, (HL)
    LD   E, A
    JR   NC, .ac_nc
    INC  D
.ac_nc:
    INC  HL
    DJNZ .ac_lp
    LD   (ovl_storage_cksum), DE
    RET

; Write BC bytes (BC >= 1) from HL into FCB_TMP_ADDR via 128-B LDIR chunks + checksum
ovl_storage_write_mem_ck:
.wmk_loop:
    CALL ovl_storage_chunk_len  ; A = chunk (1..128)
    PUSH BC
    PUSH HL
    PUSH AF
    LD   B, A
    CALL ovl_storage_accum_chunk
    POP  AF
    POP  HL
    PUSH AF

    PUSH HL
    LD   A, (ovl_storage_dma_pos)
    LD   E, A
    LD   D, 0
    LD   HL, CPM_DMA_BUF_BASE
    ADD  HL, DE
    EX   DE, HL                 ; DE = CPM_DMA_BUF_BASE + dma_pos
    POP  HL
    POP  AF
    PUSH AF
    LD   C, A
    LD   B, 0
    LDIR                        ; HL = next src

    POP  AF
    POP  BC
    LD   E, A
    LD   A, C
    SUB  E
    LD   C, A
    LD   A, B
    SBC  A, 0
    LD   B, A

    LD   A, (ovl_storage_dma_pos)
    ADD  A, E
    LD   (ovl_storage_dma_pos), A
    CP   CPM_RECORD_SIZE
    JR   C, .wmk_next

    XOR  A
    LD   (ovl_storage_dma_pos), A
    PUSH HL
    PUSH BC
    LD   C, BDOS_WRITESEQ
    LD   DE, FCB_TMP_ADDR
    CALL bdos_call
    POP  BC
    POP  HL
    OR   A
    JR   Z, .wmk_next
    SCF
    RET
.wmk_next:
    LD   A, B
    OR   C
    JR   NZ, .wmk_loop
    OR   A
    RET

; Read BC bytes (BC >= 1) from FCB_SAVE_ADDR into HL via 128-B LDIR chunks
ovl_storage_read_mem_raw:
.rmr_loop:
    LD   A, (ovl_storage_dma_pos)
    CP   CPM_RECORD_SIZE
    JR   C, .rmr_have_rec
    PUSH HL
    PUSH BC
    LD   C, BDOS_READSEQ
    LD   DE, FCB_SAVE_ADDR
    CALL bdos_call
    POP  BC
    POP  HL
    OR   A
    JR   Z, .rmr_refilled
    SCF
    RET
.rmr_refilled:
    XOR  A
    LD   (ovl_storage_dma_pos), A
.rmr_have_rec:
    CALL ovl_storage_chunk_len  ; A = chunk (1..128)
    PUSH BC
    PUSH HL
    PUSH AF

    LD   A, (ovl_storage_dma_pos)
    LD   E, A
    LD   D, 0
    LD   HL, CPM_DMA_BUF_BASE
    ADD  HL, DE                 ; HL = DMA src
    POP  AF
    POP  DE                     ; DE = dst
    PUSH AF
    LD   C, A
    LD   B, 0
    LDIR                        ; DE = next dst
    EX   DE, HL                 ; HL = next dst

    POP  AF
    POP  BC
    LD   E, A
    LD   A, C
    SUB  E
    LD   C, A
    LD   A, B
    SBC  A, 0
    LD   B, A

    LD   A, (ovl_storage_dma_pos)
    ADD  A, E
    LD   (ovl_storage_dma_pos), A
    LD   A, B
    OR   C
    JR   NZ, .rmr_loop
    OR   A
    RET

; Verify BC bytes directly from FCB_SAVE_ADDR DMA buffer accumulating checksum
ovl_storage_verify_body_ck:
.vbc_loop:
    LD   A, (ovl_storage_dma_pos)
    CP   CPM_RECORD_SIZE
    JR   C, .vbc_have_rec
    PUSH BC
    LD   C, BDOS_READSEQ
    LD   DE, FCB_SAVE_ADDR
    CALL bdos_call
    POP  BC
    OR   A
    JR   Z, .vbc_refilled
    SCF
    RET
.vbc_refilled:
    XOR  A
    LD   (ovl_storage_dma_pos), A
.vbc_have_rec:
    CALL ovl_storage_chunk_len  ; A = chunk (1..128)
    PUSH BC
    PUSH AF
    LD   A, (ovl_storage_dma_pos)
    LD   E, A
    LD   D, 0
    LD   HL, CPM_DMA_BUF_BASE
    ADD  HL, DE
    POP  AF
    PUSH AF
    LD   B, A
    CALL ovl_storage_accum_chunk

    POP  AF
    POP  BC
    LD   E, A
    LD   A, C
    SUB  E
    LD   C, A
    LD   A, B
    SBC  A, 0
    LD   B, A

    LD   A, (ovl_storage_dma_pos)
    ADD  A, E
    LD   (ovl_storage_dma_pos), A
    LD   A, B
    OR   C
    JR   NZ, .vbc_loop
    OR   A
    RET

; Accumulate A into 16-bit LE ovl_storage_cksum, then emit single raw byte to FCB_TMP_ADDR
ovl_storage_put_byte:
    PUSH HL
    PUSH DE
    LD   E, A
    LD   D, 0
    LD   HL, (ovl_storage_cksum)
    ADD  HL, DE
    LD   (ovl_storage_cksum), HL
    LD   A, E
    POP  DE
    POP  HL
ovl_storage_put_raw_byte:
    PUSH HL
    PUSH DE
    PUSH BC
    LD   E, A
    LD   A, (ovl_storage_dma_pos)
    LD   C, A
    LD   B, 0
    LD   HL, CPM_DMA_BUF_BASE
    ADD  HL, BC
    LD   (HL), E
    INC  A
    LD   (ovl_storage_dma_pos), A
    CP   CPM_RECORD_SIZE
    JR   C, .put_ok
    XOR  A
    LD   (ovl_storage_dma_pos), A
    LD   C, BDOS_WRITESEQ
    LD   DE, FCB_TMP_ADDR
    CALL bdos_call
    OR   A
    JR   Z, .put_ok
    POP  BC
    POP  DE
    POP  HL
    SCF
    RET
.put_ok:
    POP  BC
    POP  DE
    POP  HL
    OR   A
    RET

; Zero-pad remaining bytes of current DMA record and flush FCB_TMP_ADDR if dma_pos != 0
ovl_storage_flush_dma_zero_pad:
    LD   A, (ovl_storage_dma_pos)
    OR   A
    RET  Z
.pad_loop:
    LD   C, A
    LD   B, 0
    LD   HL, CPM_DMA_BUF_BASE
    ADD  HL, BC
    XOR  A
    LD   (HL), A
    LD   A, C
    INC  A
    CP   CPM_RECORD_SIZE
    JR   C, .pad_loop

    XOR  A
    LD   (ovl_storage_dma_pos), A
    LD   C, BDOS_WRITESEQ
    LD   DE, FCB_TMP_ADDR
    CALL bdos_call
    OR   A
    RET  Z
    SCF
    RET

; Read next byte into A with checksum accumulation (CF=1 on error/EOF)
ovl_storage_get_byte_ck:
    CALL ovl_storage_get_raw_byte
    RET  C
    PUSH HL
    PUSH DE
    LD   E, A
    LD   D, 0
    LD   HL, (ovl_storage_cksum)
    ADD  HL, DE
    LD   (ovl_storage_cksum), HL
    LD   A, E
    POP  DE
    POP  HL
    OR   A
    RET

; Read next byte from CPM_DMA_BUF_BASE, refilling via BDOS 20 (READSEQ) as needed
ovl_storage_get_raw_byte:
    PUSH HL
    PUSH DE
    PUSH BC
    LD   A, (ovl_storage_dma_pos)
    CP   CPM_RECORD_SIZE
    JR   C, .have_byte
    LD   C, BDOS_READSEQ
    LD   DE, FCB_SAVE_ADDR
    CALL bdos_call
    OR   A
    JR   NZ, .get_err
    XOR  A
.have_byte:
    LD   C, A
    LD   B, 0
    LD   HL, CPM_DMA_BUF_BASE
    ADD  HL, BC
    INC  A
    LD   (ovl_storage_dma_pos), A
    LD   A, (HL)
    POP  BC
    POP  DE
    POP  HL
    OR   A
    RET
.get_err:
    POP  BC
    POP  DE
    POP  HL
    SCF
    RET

; ============================================================================
; FCB, Normalization, String & Utility Helpers
; ============================================================================

; Init FCB_SAVE_ADDR for SAVE{A}.SAV with DR = (abi_save_drive) + 1 (NEVER 0)
ovl_storage_init_slot_fcb:
    PUSH AF
    LD   HL, ovl_storage_slot_tmpl
    LD   DE, temp_str_buf
    LD   BC, 11
    LDIR
    POP  AF
    ADD  A, '0'
    LD   (temp_str_buf + 4), A
    LD   HL, FCB_SAVE_ADDR
    LD   DE, temp_str_buf
    LD   A, (abi_save_drive)
    INC  A
    JP   bdos_init_fcb_name

; Init FCB_SAVE_ADDR for SAVE{A}.SAV via line_buf so temp_str_buf (.TMP) stays intact
ovl_storage_init_slot_fcb_preserve_tmp:
    PUSH AF
    LD   HL, ovl_storage_slot_tmpl
    LD   DE, line_buf
    LD   BC, 11
    LDIR
    POP  AF
    ADD  A, '0'
    LD   (line_buf + 4), A
    LD   HL, FCB_SAVE_ADDR
    LD   DE, line_buf
    LD   A, (abi_save_drive)
    INC  A
    JP   bdos_init_fcb_name

; Init FCB_SAVE_ADDR for HISCORE.DAT with DR = (abi_save_drive) + 1 (NEVER 0)
ovl_storage_init_hs_fcb:
    LD   HL, FCB_SAVE_ADDR
    LD   DE, ovl_storage_hs_name11
    LD   A, (abi_save_drive)
    INC  A
    JP   bdos_init_fcb_name

; Clamp *(HL) <= B
ovl_storage_clamp_u8:
    LD   A, (HL)
    CP   B
    RET  C
    LD   (HL), B
    RET

; Convert slot A (0..3) to bitmask (1 << A)
ovl_storage_slot_bit_a:
    INC  A
    LD   B, A
    XOR  A
    SCF
.shl_loop:
    RLA
    DJNZ .shl_loop
    RET

; Clear 230-byte hiscore_table
ovl_storage_clear_hiscore_tbl:
    LD   HL, hiscore_table
    LD   DE, hiscore_table + 1
    LD   BC, HISCORE_TABLE_SIZE - 1
    LD   (HL), 0
    LDIR
    RET

; Append ASCIIZ string HL into DE (advancing DE to new NUL position)
ovl_storage_append_str:
    LD   A, (HL)
    OR   A
    RET  Z
    LD   (DE), A
    INC  HL
    INC  DE
    JR   ovl_storage_append_str

; Decode Huffman string A into line_buf and draw at INPUT_ROW col 2 with attr E
ovl_storage_show_status_huff:
    PUSH DE
    PUSH AF
    LD   B, INPUT_ROW
    CALL screen_clear_row
    POP  AF
    LD   DE, line_buf
    CALL huff_decode_string
    POP  DE
    LD   B, INPUT_ROW
    LD   C, 2
    JP   screen_put_str

; Sanitize loaded 9-bit item IDs matching save_sanitize_*_ids in platforms/shared/save.s
ovl_storage_sanitize_all_ids:
    LD   HL, inv_item_id
    LD   DE, inv_ego
    LD   B, TOTAL_INV_SLOTS
    CALL .san_tbl
    LD   HL, fi_item_id
    LD   DE, fi_meta_hi
    LD   B, MAX_FLOOR_ITEMS
    CALL .san_tbl
    LD   HL, si_item_id
    LD   DE, si_meta_hi
    LD   B, STORE_TOTAL_SLOTS
.san_tbl:
    LD   A, (DE)
    AND  ITEM_PAGE_BIT
    JR   NZ, .san_p1
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .san_nx
    CP   ITEM_PAGE_SIZE
    JR   C, .san_nx
    JR   .san_clr
.san_p1:
    LD   A, (HL)
    CP   (ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)
    JR   C, .san_nx
.san_clr:
    LD   (HL), FI_EMPTY
    XOR  A
    LD   (DE), A
.san_nx:
    INC  HL
    INC  DE
    DJNZ .san_tbl
    RET

ovl_storage_recount_monsters:
    LD   HL, monster_table + MX_TYPE
    LD   DE, MONSTER_ENTRY_SIZE
    LD   B, MAX_MONSTERS
    LD   C, 0
.rcm_lp:
    LD   A, (HL)
    CP   EMPTY_SLOT
    JR   Z, .rcm_nx
    INC  C
.rcm_nx:
    ADD  HL, DE
    DJNZ .rcm_lp
    LD   A, C
    LD   (zp_mon_count), A
    RET

ovl_storage_recount_floor_items:
    LD   HL, fi_item_id
    LD   B, MAX_FLOOR_ITEMS
    LD   C, 0
.rcf_lp:
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .rcf_nx
    INC  C
.rcf_nx:
    INC  HL
    DJNZ .rcf_lp
    LD   A, C
    LD   (zp_item_count), A
    RET

; ============================================================================
; Save Format V2 Block Descriptor Tables & Compile-Time Byte Verification
; ============================================================================
OVL_SAV_LEN_PLAYER      EQU PL_STRUCT_SIZE                      ; 114
OVL_SAV_LEN_BG          EQU PL_BG_SIZE                          ; 160
OVL_SAV_LEN_ZP          EQU ZP_STATE_SIZE                       ; 32
OVL_SAV_LEN_FEAR        EQU 1                                   ; 1
OVL_SAV_LEN_RNG         EQU 4                                   ; 4
OVL_SAV_LEN_INV         EQU (8 * TOTAL_INV_SLOTS)               ; 272
OVL_SAV_LEN_IDKNOWN     EQU ID_KNOWN_BYTES                      ; 47
OVL_SAV_LEN_FLAVOUR     EQU FLAVOUR_COUNT                       ; 174
OVL_SAV_LEN_STORE       EQU (8 * STORE_TOTAL_SLOTS)             ; 1024
OVL_SAV_LEN_STAIRS      EQU 7                                   ; 7
OVL_SAV_LEN_ROOMS       EQU (1 + MAX_ROOMS * 6)                 ; 127
OVL_SAV_LEN_TRAPS       EQU (1 + MAX_TRAPS * 3)                 ; 49
OVL_SAV_LEN_MONSTERS    EQU (MAX_MONSTERS * MONSTER_ENTRY_SIZE) ; 384
OVL_SAV_LEN_DOORS       EQU (1 + MAX_DOOR_STATES * 3)           ; 49
OVL_SAV_PRE_DOORS_BYTES EQU (OVL_SAV_LEN_PLAYER + OVL_SAV_LEN_BG + OVL_SAV_LEN_ZP + OVL_SAV_LEN_FEAR + OVL_SAV_LEN_RNG + OVL_SAV_LEN_INV + OVL_SAV_LEN_IDKNOWN + OVL_SAV_LEN_FLAVOUR + OVL_SAV_LEN_STORE + OVL_SAV_LEN_STAIRS + OVL_SAV_LEN_ROOMS + OVL_SAV_LEN_TRAPS + OVL_SAV_LEN_MONSTERS)
OVL_SAV_LEN_CATSLOTS    EQU (CAT_SLOTS * 2)                     ; 64
OVL_SAV_HEAD_SUM        EQU (OVL_SAV_LEN_PLAYER + OVL_SAV_LEN_BG + OVL_SAV_LEN_ZP + OVL_SAV_LEN_FEAR + OVL_SAV_LEN_RNG + OVL_SAV_LEN_INV + OVL_SAV_LEN_IDKNOWN + OVL_SAV_LEN_FLAVOUR + OVL_SAV_LEN_STORE + OVL_SAV_LEN_STAIRS + OVL_SAV_LEN_ROOMS + OVL_SAV_LEN_TRAPS + OVL_SAV_LEN_MONSTERS + OVL_SAV_LEN_DOORS + OVL_SAV_LEN_CATSLOTS)

OVL_SAV_LEN_RECALL      EQU RECALL_DATA_SIZE                    ; 1116
OVL_SAV_LEN_MAP         EQU MAP_SIZE                            ; 13068
OVL_SAV_TAIL_SUM        EQU (OVL_SAV_LEN_RECALL + OVL_SAV_LEN_MAP)

ovl_sav_desc_head:
    DW player_data,       OVL_SAV_LEN_PLAYER
    DW player_background, OVL_SAV_LEN_BG
    DW zp_state,          OVL_SAV_LEN_ZP
    DW eff_fear_timer,    OVL_SAV_LEN_FEAR
    DW abi_rng_seed,      OVL_SAV_LEN_RNG
    DW inv_item_id,       OVL_SAV_LEN_INV
    DW id_known_bits,     OVL_SAV_LEN_IDKNOWN
    DW potion_shuffle,    OVL_SAV_LEN_FLAVOUR
    DW si_item_id,        OVL_SAV_LEN_STORE
    DW stairs_up_x,       OVL_SAV_LEN_STAIRS
    DW room_count,        OVL_SAV_LEN_ROOMS
    DW trap_count,        OVL_SAV_LEN_TRAPS
    DW monster_table,     OVL_SAV_LEN_MONSTERS
    DW door_state_count,  OVL_SAV_LEN_DOORS
    DW cat_slot_id_lo,    OVL_SAV_LEN_CATSLOTS
ovl_sav_desc_head_end:
OVL_SAV_HEAD_ENTRIES EQU ((ovl_sav_desc_head_end - ovl_sav_desc_head) / 4)

ovl_sav_desc_tail:
    DW recall_data,       OVL_SAV_LEN_RECALL
    DW MAP_BASE,          OVL_SAV_LEN_MAP
ovl_sav_desc_tail_end:
OVL_SAV_TAIL_ENTRIES EQU ((ovl_sav_desc_tail_end - ovl_sav_desc_tail) / 4)

    ; Compile-time proof that Save V2 blocks + 8-B header + 462-B floor items + 2-B cksum == 17,164 B
    ASSERT OVL_SAV_HEAD_ENTRIES == 15
    ASSERT OVL_SAV_TAIL_ENTRIES == 2
    ASSERT (8 + OVL_SAV_HEAD_SUM + (MAX_FLOOR_ITEMS * 11) + OVL_SAV_TAIL_SUM + 2) == SAVE_STREAM_BYTES

; ============================================================================
; Static Strings & Small Scalar Work Variables (zero 128-B buffers in .ovl)
; ============================================================================
ovl_storage_magic:          DB "MORIA01", SAVE_VERSION
    ASSERT ($ - ovl_storage_magic) == 8
ovl_storage_slot_tmpl:      DB "SAVE0   SAV"
    ASSERT ($ - ovl_storage_slot_tmpl) == 11
ovl_storage_slot_tmp_tmpl:  DB "SAVE0   TMP"
    ASSERT ($ - ovl_storage_slot_tmp_tmpl) == 11
ovl_storage_hs_name11:      DB "HISCORE DAT"
    ASSERT ($ - ovl_storage_hs_name11) == 11
ovl_storage_hs_tmp_name11:  DB "HISCORE TMP"
    ASSERT ($ - ovl_storage_hs_tmp_name11) == 11
ovl_storage_str_slots_hdr:  DB "Save Slots:", 0
ovl_storage_str_disk_hdr:   DB "Disk Setup", 0
ovl_storage_str_prog_drv:   DB "Program: ", 0
ovl_storage_str_save_drv:   DB "Save:    ", 0
ovl_storage_str_ds_opt1:    DB "1) Same as program", 0
ovl_storage_str_ds_opt2:    DB "2) Pick save drive", 0
ovl_storage_str_ds_opt3:    DB "3) Done", 0
ovl_storage_str_ds_optq:    DB "Q) Back", 0
ovl_storage_str_disk_hint:  DB "Save drive (A-P): ", 0
ovl_storage_str_pick_slot:  DB "Select Slot 1-4", 0
ovl_storage_str_empty:      DB "Empty", 0

ovl_storage_cur_slot:        DB 0
ovl_storage_tmp_slot:        DB 0
ovl_storage_tmp_row:         DB 0
ovl_storage_tmp_drv:         DB 0
ovl_storage_slot_exist_mask: DB 0
ovl_storage_dma_pos:         DB 0
ovl_storage_last_huff:       DB 0
ovl_storage_hs_tmp_cnt:      DB 0
ovl_storage_cksum:           DW 0

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end

    SAVEBIN "ovl_storage.ovl", ovl_start, ovl_end - ovl_start
