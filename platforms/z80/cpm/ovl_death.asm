; ovl_death.asm — Moria8 CP/M Death / Score / High Scores / Royal / Recall
; (OVL_DEATH = 3, DAT slot 2)
;
; Fixed vector jump table at OVL_WINDOW_BASE (0x5600):
;   +0: JP ovl_death_screen
;   +3: JP ovl_death_hiscores
;   +6: JP ovl_death_recall
;   +9: JP ovl_death_royal
;
; hiscore_table (230 B, 10 x 23 B matching ovl_storage.asm & core/6502/score.s):
;   +0..+15 : Name (16 B, space-padded)
;   +16..+18: 24-bit Score (LE)
;   +19     : PL_LEVEL
;   +20     : PL_MAX_DLVL
;   +21     : PL_RACE
;   +22     : PL_CLASS | (GAME_FLAG_WINNER ? 0x80 : 0x00)
;
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax, DEVICE NOSLOT64K).
; All public entry vectors preserve IX and IY.

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "main_exp.inc"

    ORG  OVL_WINDOW_BASE        ; 0x5600

ovl_start:
    JP   ovl_death_screen
    JP   ovl_death_hiscores
    JP   ovl_death_recall
    JP   ovl_death_royal

ROYAL_COL_BASE      EQU 20      ; (80 - 40) / 2
SDS_COL_BASE        EQU 20      ; (80 - 40) / 2
SDS_INFO_COL        EQU 21
SDS_DIED_COL        EQU 31
SDS_VALUE_COL       EQU 42
SDS_WIZARD_COL      EQU 29
SDS_HISCORE_HDR_COL EQU 24
SDS_HISCORE_ROW_COL EQU 21
SDS_HISCORE_PAD_COL EQU 50
SDS_ANYKEY_COL      EQU 33

; ============================================================================
; +9: ovl_death_royal — Apply retirement bonus + draw 6502 royal crown screen
; ============================================================================
ovl_death_royal:
    PUSH IX
    PUSH IY

    CALL player_sync_from_abi

    ; winner_apply_retirement_bonus: +40 levels if <= 40; +250,000 AU; +5,000,000 XP
    LD   A, (player_data + PL_LEVEL)
    CP   41
    JR   NC, .gold
    ADD  A, 40
    LD   (player_data + PL_LEVEL), A
.gold:
    LD   HL, player_data + PL_GOLD_0
    LD   DE, ovl_death_retire_gold
    CALL ovl_death_add24_ptr_sat
    LD   HL, player_data + PL_XP_0
    LD   DE, ovl_death_retire_xp
    CALL ovl_death_add24_ptr_sat
    CALL player_sync_to_abi

    ; Draw royal.s screen
    CALL screen_hard_clear
    LD   HL, ovl_death_crown_lines
    LD   B, 2
.cr_lp:
    PUSH BC
    PUSH HL
    LD   C, ROYAL_COL_BASE
    LD   E, COL_YELLOW
    CALL screen_put_str
    POP  HL
    LD   DE, 37
    ADD  HL, DE
    POP  BC
    INC  B
    LD   A, B
    CP   9
    JR   C, .cr_lp

    LD   B, 12
    LD   C, ROYAL_COL_BASE
    LD   E, COL_WHITE
    LD   HL, ovl_death_str_win_veni
    CALL screen_put_str

    LD   B, 14
    LD   C, ROYAL_COL_BASE
    LD   E, COL_WHITE
    LD   HL, ovl_death_str_win_conq
    CALL screen_put_str

    LD   B, 16
    LD   C, ROYAL_COL_BASE
    LD   E, COL_WHITE
    LD   HL, ovl_death_str_win_hail
    CALL screen_put_str

    LD   DE, line_buf
    LD   HL, player_data + PL_NAME
    CALL ovl_death_copy_name16
    LD   B, 17
    LD   C, ROYAL_COL_BASE + 12
    LD   E, COL_WHITE
    LD   HL, line_buf
    CALL screen_put_str

    LD   B, 23
    LD   C, ROYAL_COL_BASE
    LD   E, COL_LGREY
    LD   HL, ovl_death_str_royal_press
    CALL screen_put_str

    CALL screen_flush
    CALL input_wait_any_key

    POP  IY
    POP  IX
    RET

; Add 24-bit LE at (DE) into 24-bit LE at (HL), saturating at 0xFFFFFF.
ovl_death_add24_ptr_sat:
    PUSH HL
    LD   A, (DE)
    ADD  A, (HL)
    LD   (HL), A
    INC  HL
    INC  DE
    LD   A, (DE)
    ADC  A, (HL)
    LD   (HL), A
    INC  HL
    INC  DE
    LD   A, (DE)
    ADC  A, (HL)
    LD   (HL), A
    POP  HL
    RET  NC
    LD   A, 0xFF
    LD   (HL), A
    INC  HL
    LD   (HL), A
    INC  HL
    LD   (HL), A
    RET

; ============================================================================
; +0: ovl_death_screen — Single-screen score.s layout + HISCORE update
; ============================================================================
ovl_death_screen:
    PUSH IX
    PUSH IY

    CALL player_sync_from_abi

    ; Snapshot effective flags (D) and death source (E) on stack across overlay swaps
    LD   A, (abi_game_flags)
    LD   HL, zp_game_flags
    OR   (HL)
    LD   D, A

    LD   A, (abi_death_source)
    OR   A
    JR   NZ, .have_dsrc
    LD   A, (zp_death_source)
.have_dsrc:
    LD   E, A

    PUSH DE
    CALL tramp_hiscore_load
    POP  DE

    LD   A, D
    LD   (ovl_death_eff_flags), A
    LD   A, E
    LD   (ovl_death_eff_src), A
    LD   A, 0xFF
    LD   (ovl_death_new_rank), A

    ; Compute 24-bit score = PL_XP + PL_GOLD + PL_MAX_DLVL * 50
    CALL ovl_death_calc_score

    ; Update HISCORE.DAT unless Wizard Mode active
    LD   A, (ovl_death_eff_flags)
    BIT  1, A                   ; GAME_FLAG_WIZARD
    JR   NZ, .skip_save
    CALL ovl_death_hiscore_insert
    CP   HISCORE_MAX_ENTRIES
    JR   NC, .skip_save
    LD   HL, (ovl_death_eff_flags) ; L = eff_flags, H = eff_src
    PUSH HL
    PUSH AF                     ; save new_rank across OVL_STORAGE swap
    CALL tramp_hiscore_save
    POP  AF
    POP  HL
    LD   (ovl_death_new_rank), A
    LD   (ovl_death_eff_flags), HL
    CALL ovl_death_calc_score
.skip_save:

    CALL ovl_death_draw_score_screen
    CALL screen_flush
    CALL input_wait_any_key

    CALL screen_hard_clear
    CALL status_mark_dirty
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    POP  IY
    POP  IX
    RET

; ============================================================================
; +3: ovl_death_hiscores — High score list (kept for fixed vector +3 compatibility)
; ============================================================================
ovl_death_hiscores:
    PUSH IX
    PUSH IY

    CALL tramp_hiscore_load
    LD   A, 0xFF
    LD   (ovl_death_new_rank), A
    CALL screen_hard_clear
    LD   B, 1
    LD   C, SDS_HISCORE_HDR_COL
    LD   E, COL_CYAN
    LD   HL, ovl_death_str_hs_hdr
    CALL screen_put_str
    LD   B, 3
    CALL ovl_death_draw_hiscore_rows
    LD   B, SCREEN_ROWS - 1
    LD   C, SDS_ANYKEY_COL
    LD   E, COL_LGREY
    LD   HL, ovl_death_str_press
    CALL screen_put_str
    CALL screen_flush
    CALL input_wait_any_key

    CALL screen_hard_clear
    CALL status_mark_dirty
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    POP  IY
    POP  IX
    RET

; ============================================================================
; +6: ovl_death_recall — 279-species single-page Recall viewer (ui_recall.s parity)
; Input:  A = ASCII query symbol ('a'..'z' or 'A'..'Z')
; Output: CF = 1 if matching encountered (or Wizard) creature displayed
;         CF = 0 if no matching creature found (screen untouched)
; Preserves: IX, IY
; ============================================================================
    IFNDEF CATALOG_COUNT
    DEFINE MONSTER_IDX_CONSTS_ONLY 1
    INCLUDE "monster_idx_z80.inc"
    UNDEFINE MONSTER_IDX_CONSTS_ONLY
    ENDIF

ovl_death_recall:
    PUSH IX
    PUSH IY

    LD   (ovl_death_rcl_query), A
    LD   (recall_query_sc), A

    ; Determine starting catalog ID (0..278)
    LD   HL, recall_last_sc
    CP   (HL)
    JR   NZ, .start_zero
    LD   DE, (recall_last_cat_lo)
    CALL .inc_wrap_de
    JR   .search_start
.start_zero:
    LD   DE, 0

.search_start:
    LD   (ovl_death_rcl_id_lo), DE
    LD   HL, CATALOG_COUNT
    LD   (ovl_death_rcl_rem_lo), HL

.search_loop:
    LD   DE, (ovl_death_rcl_id_lo)
    ; Check encountered (6502 catalog_recall_match_and_fill: requires nonzero even in Wizard Mode)
    LD   H, D
    LD   L, E
    ADD  HL, HL
    ADD  HL, HL                 ; DE * 4
    LD   BC, recall_data
    ADD  HL, BC
    LD   A, (HL)
    INC  HL
    OR   (HL)
    INC  HL
    OR   (HL)
    INC  HL
    OR   (HL)
    JR   Z, .next_id

.read_cat:
    LD   DE, (ovl_death_rcl_id_lo)
    CALL catalog_read_record    ; DE=id -> CF=0, HL=cpm_dma_buf+(E&1)*57
    JR   C, .next_id
    PUSH HL
    LD   BC, CAT_REC_CR_DISPLAY
    ADD  HL, BC
    LD   A, (HL)
    POP  HL
    LD   B, A
    LD   A, (ovl_death_rcl_query)
    CP   B
    JR   Z, .matched

.next_id:
    LD   DE, (ovl_death_rcl_id_lo)
    CALL .inc_wrap_de
    LD   (ovl_death_rcl_id_lo), DE
    LD   HL, (ovl_death_rcl_rem_lo)
    DEC  HL
    LD   (ovl_death_rcl_rem_lo), HL
    LD   A, H
    OR   L
    JR   NZ, .search_loop

    ; No match found across all 279 entries -> return CF=0 without clearing screen
    XOR  A
    LD   (recall_last_sc), A
    POP  IY
    POP  IX
    OR   A
    RET

.matched:
    LD   DE, ovl_death_rcl_rec
    LD   BC, CATALOG_RECORD_SIZE
    LDIR

    LD   A, (ovl_death_rcl_query)
    LD   (recall_last_sc), A
    LD   DE, (ovl_death_rcl_id_lo)
    LD   (recall_last_cat_lo), DE

    CALL _ovl_death_render_recall
    CALL screen_flush
    CALL input_wait_any_key

    POP  IY
    POP  IX
    SCF
    RET

.inc_wrap_de:
    INC  DE
    LD   A, D
    OR   A
    RET  Z
    CP   (CATALOG_COUNT >> 8)
    RET  C
    JR   NZ, .wrap0
    LD   A, E
    CP   (CATALOG_COUNT & 0xFF)
    RET  C
.wrap0:
    LD   DE, 0
    RET

; ----------------------------------------------------------------------------
; _ovl_death_render_recall — core/6502/ui_recall.s 1:1 80-col layout
; ----------------------------------------------------------------------------
_ovl_death_render_recall:
    CALL screen_hard_clear

    ; Row 0: "Recall" at col 33 (URCL_TITLE_COL = (80-14)/2 = 33)
    LD   B, 0
    LD   C, 33
    LD   E, COL_WHITE
    LD   HL, ovl_death_str_rcl_hdr
    CALL screen_put_str

    ; Row 2: [<colored sym>] <Name>
    LD   B, 2
    LD   C, 2
    LD   E, COL_WHITE
    LD   A, '['
    CALL screen_put_char
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_COLOR)
    OR   A
    JR   NZ, .col_ok
    LD   A, COL_WHITE
.col_ok:
    LD   E, A
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_DISPLAY)
    LD   B, 2
    LD   C, 3
    CALL screen_put_char
    LD   B, 2
    LD   C, 4
    LD   E, COL_WHITE
    LD   A, ']'
    CALL screen_put_char
    LD   DE, line_buf
    LD   A, ' '
    LD   (DE), A
    INC  DE
    LD   HL, ovl_death_rcl_rec + CAT_REC_NAME
    CALL _rcl_append_str
    XOR  A
    LD   (DE), A
    LD   B, 2
    LD   C, 5
    LD   E, COL_WHITE
    LD   HL, line_buf
    CALL screen_put_str

    ; Row 4: LV (col 2), AC (col 10), HP (col 18)
    LD   B, 4
    LD   C, 2
    LD   HL, ovl_death_str_rcl_lv
    CALL _rcl_put_lbl
    LD   DE, line_buf
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_LEVEL)
    CALL fmt_u8_dec
    XOR  A
    LD   (DE), A
    LD   B, 4
    LD   C, 5
    CALL _rcl_put_line_w_at

    LD   B, 4
    LD   C, 10
    LD   HL, ovl_death_str_rcl_ac
    CALL _rcl_put_lbl
    LD   DE, line_buf
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_AC)
    CALL fmt_u8_dec
    XOR  A
    LD   (DE), A
    LD   B, 4
    LD   C, 13
    CALL _rcl_put_line_w_at

    LD   B, 4
    LD   C, 18
    LD   HL, ovl_death_str_rcl_hp
    CALL _rcl_put_lbl
    LD   DE, line_buf
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_HD_NUM)
    CALL fmt_u8_dec
    LD   A, 'D'
    LD   (DE), A
    INC  DE
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_HD_SIDES)
    CALL fmt_u8_dec
    XOR  A
    LD   (DE), A
    LD   B, 4
    LD   C, 21
    CALL _rcl_put_line_w_at

    ; Row 6: Atk: (up to 4 attacks separated by 2 spaces, skip 0D0 ATK_NORMAL)
    LD   B, 6
    LD   C, 2
    LD   HL, ovl_death_str_rcl_atk
    CALL _rcl_put_lbl
    LD   DE, line_buf
    XOR  A
    LD   (ovl_death_rcl_cnt), A
    LD   HL, ovl_death_rcl_rec + CAT_REC_CR_ATK0_TYPE
    CALL _rcl_fmt_atk_slot
    LD   HL, ovl_death_rcl_rec + CAT_REC_CR_ATK1_TYPE
    CALL _rcl_fmt_atk_slot
    LD   HL, ovl_death_rcl_rec + CAT_REC_CR_ATK2_TYPE
    CALL _rcl_fmt_atk_slot
    LD   HL, ovl_death_rcl_rec + CAT_REC_CR_ATK3_TYPE
    CALL _rcl_fmt_atk_slot
    LD   A, (ovl_death_rcl_cnt)
    OR   A
    JR   NZ, .atk_put
    LD   HL, ovl_death_str_none
    CALL _rcl_append_str
.atk_put:
    LD   B, 6
    LD   C, 7
    CALL _rcl_put_line_w_at

    ; Row 8: Spl: Yes / None (gated on recall_data[id*4+3] or WIZARD)
    LD   B, 8
    LD   C, 2
    LD   HL, ovl_death_str_rcl_spl
    CALL _rcl_put_lbl
    LD   HL, (ovl_death_rcl_id_lo)
    ADD  HL, HL
    ADD  HL, HL
    LD   BC, recall_data + 3
    ADD  HL, BC
    LD   A, (HL)
    OR   A
    JR   NZ, .spl_yes
    LD   A, (zp_game_flags)
    AND  GAME_FLAG_WIZARD
    JR   Z, .spl_no
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_SPELL_CHANCE)
    AND  MS_FREQ_MASK
    JR   Z, .spl_no
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_SPELL_FLAGS2)
    AND  0x1F
    LD   B, A
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_SPELL_FLAGS)
    OR   B
    JR   NZ, .spl_yes
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_SPELL_CHANCE)
    BIT  7, A
    JR   Z, .spl_no
.spl_yes:
    LD   HL, ovl_death_str_yes
    JR   .spl_put
.spl_no:
    LD   HL, ovl_death_str_none
.spl_put:
    LD   B, 8
    LD   C, 7
    LD   E, COL_WHITE
    CALL screen_put_str

    ; Row 10: Hurt: FIR CLD ACD PSN LIT STN
    LD   B, 10
    LD   C, 2
    LD   HL, ovl_death_str_rcl_hrt
    CALL _rcl_put_lbl
    LD   DE, line_buf
    XOR  A
    LD   (ovl_death_rcl_cnt), A
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_CDEFENSE)
    LD   C, A
    LD   HL, ovl_death_hurt_tbl
    CALL _rcl_emit_masked_tags
    LD   A, (ovl_death_rcl_cnt)
    OR   A
    JR   NZ, .hrt_put
    LD   HL, ovl_death_str_none
    CALL _rcl_append_str
.hrt_put:
    LD   B, 10
    LD   C, 8
    CALL _rcl_put_line_w_at

    ; Row 12: Traits: INVIS PHASE NO-SLP UNDEAD EVIL
    LD   B, 12
    LD   C, 2
    LD   HL, ovl_death_str_rcl_trt
    CALL _rcl_put_lbl
    LD   DE, line_buf
    XOR  A
    LD   (ovl_death_rcl_cnt), A
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_CDEFENSE)
    BIT  7, A                   ; CD_INVISIBLE
    JR   Z, .tr_ph
    LD   HL, ovl_death_tr_invis
    CALL _rcl_emit_tag_hl
.tr_ph:
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_SPELL_FLAGS2)
    BIT  5, A                   ; CM2_PHASE
    JR   Z, .tr_ns
    LD   HL, ovl_death_tr_phase
    CALL _rcl_emit_tag_hl
.tr_ns:
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_CDEFENSE)
    BIT  6, A                   ; CD_NO_SLEEP
    JR   Z, .tr_un
    LD   HL, ovl_death_tr_noslp
    CALL _rcl_emit_tag_hl
.tr_un:
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_MFLAGS)
    BIT  1, A                   ; CF_UNDEAD
    JR   Z, .tr_ev
    LD   HL, ovl_death_tr_undead
    CALL _rcl_emit_tag_hl
.tr_ev:
    LD   A, (ovl_death_rcl_rec + CAT_REC_CR_MFLAGS)
    BIT  2, A                   ; CF_EVIL
    JR   Z, .tr_chk
    LD   HL, ovl_death_tr_evil
    CALL _rcl_emit_tag_hl
.tr_chk:
    LD   A, (ovl_death_rcl_cnt)
    OR   A
    JR   NZ, .trt_put
    LD   HL, ovl_death_str_none
    CALL _rcl_append_str
.trt_put:
    LD   B, 12
    LD   C, 10
    CALL _rcl_put_line_w_at

    ; Row 14: K: <k>  D: <d> (cols 2 and 16)
    LD   B, 14
    LD   C, 2
    LD   HL, ovl_death_str_rcl_k
    CALL _rcl_put_lbl
    LD   HL, (ovl_death_rcl_id_lo)
    ADD  HL, HL
    ADD  HL, HL
    LD   BC, recall_data
    ADD  HL, BC
    PUSH HL
    LD   DE, line_buf
    LD   A, (HL)
    CALL fmt_u8_dec
    XOR  A
    LD   (DE), A
    LD   B, 14
    LD   C, 5
    CALL _rcl_put_line_w_at

    LD   B, 14
    LD   C, 16
    LD   HL, ovl_death_str_rcl_d
    CALL _rcl_put_lbl
    POP  HL
    INC  HL
    LD   DE, line_buf
    LD   A, (HL)
    CALL fmt_u8_dec
    XOR  A
    LD   (DE), A
    LD   B, 14
    LD   C, 19
    CALL _rcl_put_line_w_at

    ; Row 16: "Press any key" at col 33 (URCL_FOOTER_COL)
    LD   B, 16
    LD   C, 33
    LD   E, COL_LGREY
    LD   HL, ovl_death_str_press
    JP   screen_put_str

_rcl_put_lbl:
    LD   E, COL_LGREY
    JP   screen_put_str

_rcl_put_line_w_at:
    XOR  A
    LD   (DE), A
    LD   E, COL_WHITE
    LD   HL, line_buf
    JP   screen_put_str

_rcl_emit_tag_hl:
    PUSH HL
    LD   HL, ovl_death_rcl_cnt
    LD   A, (HL)
    INC  (HL)
    OR   A
    JR   Z, .no_sp
    LD   A, ' '
    LD   (DE), A
    INC  DE
.no_sp:
    POP  HL
    JP   _rcl_append_str

; Emit tags from table HL = { DB mask, "TAG", 0 ... DB 0 } against byte C.
_rcl_emit_masked_tags:
.lp:
    LD   A, (HL)
    INC  HL
    OR   A
    RET  Z
    AND  C
    JR   NZ, .emit
.skp:
    LD   A, (HL)
    INC  HL
    OR   A
    JR   NZ, .skp
    JR   .lp
.emit:
    PUSH BC
    CALL _rcl_emit_tag_hl
    INC  HL                     ; past NUL
    POP  BC
    JR   .lp

_rcl_append_str:
    LD   A, (HL)
    OR   A
    RET  Z
    LD   (DE), A
    INC  HL
    INC  DE
    JR   _rcl_append_str

; Format attack slot HL -> (+0 type, +1 dice, +2 sides)
_rcl_fmt_atk_slot:
    LD   A, (HL)
    INC  HL
    AND  ATK_TYPE_MASK
    OR   A
    RET  Z                      ; ATK_NONE
    CP   25
    RET  NC
    LD   B, (HL)                ; dice
    INC  HL
    LD   A, (HL)
    AND  ATK_SIDES_MASK
    LD   C, A                   ; sides
    DEC  HL
    DEC  HL
    LD   A, (HL)
    AND  ATK_TYPE_MASK
    DEC  A                      ; 0..23
    ; Suppress 0D0 ATK_NORMAL (type==1 -> A==0)
    OR   A
    JR   NZ, .emit_atk
    LD   A, B
    OR   A
    JR   Z, .zero_atk
    LD   A, C
    OR   A
    JR   Z, .zero_atk
    XOR  A
    JR   .emit_atk
.zero_atk:
    RET
.emit_atk:
    PUSH BC
    PUSH HL
    LD   L, A
    LD   H, 0
    ADD  A, A
    ADD  A, L                   ; * 3
    LD   L, A
    LD   BC, ovl_death_atk_tags
    ADD  HL, BC
    PUSH HL
    LD   A, (ovl_death_rcl_cnt)
    OR   A
    JR   Z, .no_sp
    LD   A, ' '
    LD   (DE), A
    INC  DE
    LD   (DE), A
    INC  DE
.no_sp:
    LD   HL, ovl_death_rcl_cnt
    INC  (HL)
    POP  HL
    LD   B, 3
.t3:
    LD   A, (HL)
    LD   (DE), A
    INC  HL
    INC  DE
    DJNZ .t3
    POP  HL
    POP  BC
    LD   A, B
    OR   A
    RET  Z
    LD   A, C
    OR   A
    RET  Z
    LD   A, ' '
    LD   (DE), A
    INC  DE
    LD   A, B
    PUSH BC
    CALL fmt_u8_dec
    POP  BC
    LD   A, 'D'
    LD   (DE), A
    INC  DE
    LD   A, C
    JP   fmt_u8_dec

ovl_death_rcl_query:   DB 0
ovl_death_rcl_cnt:     DB 0
ovl_death_rcl_id_lo:   DB 0
ovl_death_rcl_id_hi:   DB 0
ovl_death_rcl_rem_lo:  DB 0
ovl_death_rcl_rem_hi:  DB 0
ovl_death_rcl_rec:     DS CATALOG_RECORD_SIZE

ovl_death_retire_gold: DB 0x90, 0xD0, 0x03 ; 250,000
ovl_death_retire_xp:   DB 0x40, 0x4B, 0x4C ; 5,000,000

ovl_death_str_rcl_hdr: DB "Recall", 0
ovl_death_str_rcl_lv:  DB "LV ", 0
ovl_death_str_rcl_ac:  DB "AC ", 0
ovl_death_str_rcl_hp:  DB "HP ", 0
ovl_death_str_yes:     DB "Yes", 0
ovl_death_str_none:    DB "None", 0
ovl_death_str_rcl_k:   DB "K: ", 0
ovl_death_str_rcl_d:   DB "D: ", 0
ovl_death_str_rcl_atk: DB "Atk: ", 0
ovl_death_str_rcl_spl: DB "Spl: ", 0
ovl_death_str_rcl_hrt: DB "Hurt: ", 0
ovl_death_str_rcl_trt: DB "Traits: ", 0
ovl_death_tr_invis:    DB "INVIS", 0
ovl_death_tr_phase:    DB "PHASE", 0
ovl_death_tr_noslp:    DB "NO-SLP", 0
ovl_death_tr_undead:   DB "UNDEAD", 0
ovl_death_tr_evil:     DB "EVIL", 0
ovl_death_str_win_veni:  DB "          Veni, Vidi, Vici!         ", 0
ovl_death_str_win_conq:  DB "      I came, I saw, I conquered!   ", 0
ovl_death_str_win_hail:  DB "          All Hail the Mighty       ", 0
ovl_death_str_royal_press: DB "             Press any key          ", 0
ovl_death_hurt_tbl:
    DB CD_FIRE, "FIR", 0
    DB CD_FROST, "CLD", 0
    DB CD_ACID, "ACD", 0
    DB CD_POISON, "PSN", 0
    DB CD_LIGHT, "LIT", 0
    DB CD_STONE, "STN", 0
    DB 0
ovl_death_atk_tags:
    DB "HITSTRCNFFERFIRACDCLDLTGCORBLDPARGLDITMPSNDEXCONINTWISEXPSHRDISFODLITCHG"

; ============================================================================
; Score Math (24-bit unsigned)
; ============================================================================
ovl_death_calc_score:
    ; ovl_death_score = PL_XP
    LD   HL, player_data + PL_XP_0
    LD   DE, ovl_death_score
    LD   BC, 3
    LDIR

    ; + PL_GOLD (saturating 24-bit)
    LD   HL, player_data + PL_GOLD_0
    CALL ovl_death_add24_hl

    ; + PL_MAX_DLVL * 50
    LD   A, (player_data + PL_MAX_DLVL)
    LD   L, A
    LD   H, 0
    LD   A, 50
    CALL mul_hl_a               ; HL = max_dlvl * 50
    LD   (ovl_death_tmp24), HL
    XOR  A
    LD   (ovl_death_tmp24 + 2), A
    LD   HL, ovl_death_tmp24
    JP   ovl_death_add24_hl

; ovl_death_score += 24-bit (HL), saturating at 0xFFFFFF
ovl_death_add24_hl:
    LD   DE, ovl_death_score
    LD   A, (DE)
    ADD  A, (HL)
    LD   (DE), A
    INC  DE
    INC  HL
    LD   A, (DE)
    ADC  A, (HL)
    LD   (DE), A
    INC  DE
    INC  HL
    LD   A, (DE)
    ADC  A, (HL)
    JR   NC, .ok
    LD   A, 0xFF
    LD   (ovl_death_score), A
    LD   (ovl_death_score + 1), A
.ok:
    LD   (ovl_death_score + 2), A
    RET

; Compare ovl_death_score vs 24-bit (HL). Output: CF=1 if score < (HL), CF=0 if score >= (HL).
ovl_death_cmp24_score_vs_hl:
    INC  HL
    INC  HL
    LD   A, (ovl_death_score + 2)
    CP   (HL)
    RET  NZ
    DEC  HL
    LD   A, (ovl_death_score + 1)
    CP   (HL)
    RET  NZ
    DEC  HL
    LD   A, (ovl_death_score)
    CP   (HL)
    RET

; ============================================================================
; hiscore_insert — Insert player sorted descending into hiscore_table
; Output: A = inserted rank (0..9) or 0xFF if didn't qualify
; ============================================================================
ovl_death_hiscore_insert:
    LD   A, (hiscore_count)
    CP   HISCORE_MAX_ENTRIES + 1
    JR   C, .cnt_ok
    LD   A, HISCORE_MAX_ENTRIES
    LD   (hiscore_count), A
.cnt_ok:
    LD   C, 0                   ; idx = 0..count
.find_lp:
    LD   A, (hiscore_count)
    CP   C
    JR   Z, .at_end
    JR   C, .at_end
    LD   A, C
    CALL ovl_death_hs_entry_ptr ; HL = &hiscore_table[C * 23]
    LD   DE, 16
    ADD  HL, DE                 ; HL = &entry.score[0..2]
    CALL ovl_death_cmp24_score_vs_hl
    JR   NC, .insert_here       ; score >= entry.score -> insert at C
    INC  C
    JR   .find_lp

.at_end:
    LD   A, C
    CP   HISCORE_MAX_ENTRIES
    JR   C, .insert_here
    LD   A, 0xFF
    LD   (ovl_death_new_rank), A
    RET

.insert_here:
    ; Grow count if < HISCORE_MAX_ENTRIES
    LD   A, (hiscore_count)
    CP   HISCORE_MAX_ENTRIES
    JR   NC, .no_grow
    INC  A
    LD   (hiscore_count), A
.no_grow:
    ; Shift entries from i = (hiscore_count - 1) down to C + 1
    LD   A, (hiscore_count)
    DEC  A
    LD   B, A                   ; B = dst index
.shift_lp:
    LD   A, B
    CP   C
    JR   Z, .shift_done
    JR   C, .shift_done
    PUSH BC
    LD   A, B
    CALL ovl_death_hs_entry_ptr
    EX   DE, HL                 ; DE = dst
    LD   A, B
    DEC  A
    CALL ovl_death_hs_entry_ptr ; HL = src
    LD   BC, HISCORE_ENTRY_SIZE
    LDIR
    POP  BC
    DEC  B
    JR   .shift_lp

.shift_done:
    LD   A, C
    LD   (ovl_death_new_rank), A
    CALL ovl_death_hs_entry_ptr ; HL = &hiscore_table[C * 23]
    EX   DE, HL                 ; DE = entry ptr

    ; +0..+15: Name space-padded
    LD   HL, player_data + PL_NAME
    LD   B, 16
.nm_cp:
    LD   A, (HL)
    OR   A
    JR   Z, .nm_pad
    LD   (DE), A
    INC  HL
    INC  DE
    DJNZ .nm_cp
    JR   .nm_done
.nm_pad:
    LD   A, ' '
    LD   (DE), A
    INC  DE
    DJNZ .nm_pad
.nm_done:

    ; +16..+18: 24-bit score LE
    LD   HL, ovl_death_score
    LD   BC, 3
    LDIR

    ; +19: PL_LEVEL
    LD   A, (player_data + PL_LEVEL)
    LD   (DE), A
    INC  DE

    ; +20: PL_MAX_DLVL
    LD   A, (player_data + PL_MAX_DLVL)
    LD   (DE), A
    INC  DE

    ; +21: PL_RACE
    LD   A, (player_data + PL_RACE)
    LD   (DE), A
    INC  DE

    ; +22: PL_CLASS | (winner ? 0x80 : 0)
    LD   A, (ovl_death_eff_flags)
    AND  GAME_FLAG_WINNER
    LD   B, 0
    JR   Z, .not_win
    LD   B, 0x80
.not_win:
    LD   A, (player_data + PL_CLASS)
    OR   B
    LD   (DE), A

    LD   A, (ovl_death_new_rank)
    RET

; Input: A = index (0..9) -> Output: HL = hiscore_table + A * 23. Preserves BC, DE.
ovl_death_hs_entry_ptr:
    PUSH DE
    PUSH BC
    LD   L, A
    LD   H, 0
    LD   A, HISCORE_ENTRY_SIZE
    CALL mul_hl_a
    LD   DE, hiscore_table
    ADD  HL, DE
    POP  BC
    POP  DE
    RET

; ============================================================================
; Single-Screen Score/Death Display (core/6502/score.s 1:1 80-col parity)
; ============================================================================
ovl_death_draw_score_screen:
    CALL screen_hard_clear

    ; Row 1: heading (COL_RED at SDS_DIED_COL=31)
    LD   A, (ovl_death_eff_flags)
    AND  GAME_FLAG_WINNER
    LD   HL, ovl_death_str_died_hdr
    JR   Z, .hdr_set
    LD   HL, ovl_death_str_win_hdr
.hdr_set:
    LD   B, 1
    LD   C, SDS_DIED_COL
    LD   E, COL_RED
    CALL screen_put_str

    ; Row 3: Name (COL_WHITE at SDS_INFO_COL=21)
    LD   DE, line_buf
    LD   HL, player_data + PL_NAME
    CALL ovl_death_copy_name16
    LD   B, 3
    LD   C, SDS_INFO_COL
    LD   E, COL_WHITE
    LD   HL, line_buf
    CALL screen_put_str

    ; Row 4: "<Race> <Class>  Level <PL_LEVEL>" (COL_LGREY)
    LD   DE, line_buf
    LD   A, (player_data + PL_RACE)
    CP   RACE_COUNT
    JR   C, .rc_ok
    XOR  A
.rc_ok:
    LD   HL, ovl_death_race_names
    CALL ovl_death_nth_str
    CALL ovl_death_append_str
    LD   A, ' '
    LD   (DE), A
    INC  DE
    LD   A, (player_data + PL_CLASS)
    CP   CLASS_COUNT
    JR   C, .cl_ok
    XOR  A
.cl_ok:
    LD   HL, ovl_death_class_names
    CALL ovl_death_nth_str
    CALL ovl_death_append_str
    LD   HL, ovl_death_str_lvl
    CALL ovl_death_append_str
    LD   A, (player_data + PL_LEVEL)
    CALL fmt_u8_dec
    XOR  A
    LD   (DE), A
    LD   B, 4
    LD   C, SDS_INFO_COL
    LD   E, COL_LGREY
    LD   HL, line_buf
    CALL screen_put_str

    ; Row 5: "Killed on dungeon level <dlvl>" (COL_LGREY)
    LD   DE, line_buf
    LD   HL, ovl_death_str_dlvl
    CALL ovl_death_append_str
    LD   A, (player_data + PL_DLEVEL)
    CALL fmt_u8_dec
    XOR  A
    LD   (DE), A
    LD   B, 5
    LD   C, SDS_INFO_COL
    LD   E, COL_LGREY
    LD   HL, line_buf
    CALL screen_put_str

    ; Row 7: Cause (COL_ORANGE)
    LD   DE, line_buf
    LD   A, (ovl_death_eff_flags)
    AND  GAME_FLAG_WINNER
    JR   Z, .build_killed
    LD   HL, ovl_death_str_retired
    CALL ovl_death_append_str
    JR   .put_cause
.build_killed:
    LD   HL, ovl_death_str_killed_by
    CALL ovl_death_append_str
    CALL ovl_death_append_cause
.put_cause:
    XOR  A
    LD   (DE), A
    LD   B, 7
    LD   C, SDS_INFO_COL
    LD   E, COL_ORANGE
    LD   HL, line_buf
    CALL screen_put_str

    ; Rows 9..12: Exp, Gold, Depth Bonus, Total Score
    LD   B, 9
    LD   HL, ovl_death_str_exp
    LD   DE, player_data + PL_XP_0
    LD   A, COL_WHITE
    CALL ovl_death_put_24_row

    LD   B, 10
    LD   HL, ovl_death_str_gold
    LD   DE, player_data + PL_GOLD_0
    LD   A, COL_YELLOW
    CALL ovl_death_put_24_row

    LD   A, (player_data + PL_MAX_DLVL)
    LD   L, A
    LD   H, 0
    LD   A, 50
    CALL mul_hl_a
    LD   (ovl_death_tmp24), HL
    XOR  A
    LD   (ovl_death_tmp24 + 2), A
    LD   B, 11
    LD   HL, ovl_death_str_dbonus
    LD   DE, ovl_death_tmp24
    LD   A, COL_WHITE
    CALL ovl_death_put_24_row

    LD   B, 12
    LD   HL, ovl_death_str_total
    LD   DE, ovl_death_score
    LD   A, COL_GREEN
    CALL ovl_death_put_24_row

    ; Row 13: Optional WIZARD badge (COL_YELLOW at SDS_WIZARD_COL=29)
    LD   A, (ovl_death_eff_flags)
    BIT  1, A
    JR   Z, .hs_hdr
    LD   B, 13
    LD   C, SDS_WIZARD_COL
    LD   E, COL_YELLOW
    LD   HL, ovl_death_str_wizard_no
    CALL screen_put_str

.hs_hdr:
    ; Row 14: High score header (COL_CYAN at SDS_HISCORE_HDR_COL=24)
    LD   B, 14
    LD   C, SDS_HISCORE_HDR_COL
    LD   E, COL_CYAN
    LD   HL, ovl_death_str_hs_hdr
    CALL screen_put_str

    ; Rows 15..22: High score table
    LD   B, 15
    CALL ovl_death_draw_hiscore_rows

    ; Row 23: "Press any key" (COL_LGREY at SDS_ANYKEY_COL=33)
    LD   B, SCREEN_ROWS - 1
    LD   C, SDS_ANYKEY_COL
    LD   E, COL_LGREY
    LD   HL, ovl_death_str_press
    JP   screen_put_str

; Print label HL at (B, SDS_INFO_COL) COL_LGREY and 24-bit LE at (DE) in color A at (B, SDS_VALUE_COL)
ovl_death_put_24_row:
    PUSH AF
    PUSH DE
    PUSH BC
    LD   C, SDS_INFO_COL
    LD   E, COL_LGREY
    CALL screen_put_str
    POP  BC
    POP  HL
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    INC  HL
    LD   A, (HL)
    EX   DE, HL
    LD   E, A
    PUSH BC
    LD   BC, temp_str_buf
    CALL status_fmt_u24
    POP  BC
    POP  AF
    LD   E, A
    LD   C, SDS_VALUE_COL
    JP   screen_put_str

; Append death cause string into DE using ovl_death_eff_src and death_cause_buf
ovl_death_append_cause:
    LD   A, (ovl_death_eff_src)
    CP   DEATH_POISON
    JR   Z, .c_poison
    CP   DEATH_STARVE
    JR   Z, .c_starve
    CP   DEATH_CURSED
    JR   Z, .c_cursed
    CP   DEATH_CHEST_NEEDLE
    JR   Z, .c_needle
    CP   DEATH_CHEST_EXPLOSION
    JR   Z, .c_expl
    CP   DEATH_TRAP_PIT
    JR   C, .c_monster
    CP   DEATH_TRAP_ROCKFALL + 1
    JR   NC, .c_monster
    LD   HL, death_cause_buf
    LD   A, (HL)
    OR   A
    JR   NZ, .c_buf_direct
    LD   A, (ovl_death_eff_src)
    SUB  DEATH_TRAP_PIT
    LD   HL, ovl_death_trap_causes
    CALL ovl_death_nth_str
    JP   ovl_death_append_str

.c_poison:
    LD   HL, ovl_death_str_c_poison
    JP   ovl_death_append_str
.c_starve:
    LD   HL, ovl_death_str_c_starve
    JP   ovl_death_append_str
.c_cursed:
    LD   HL, ovl_death_str_c_cursed
    JP   ovl_death_append_str
.c_needle:
    LD   HL, ovl_death_str_c_needle
    JP   ovl_death_append_str
.c_expl:
    LD   HL, ovl_death_str_c_expl
    JP   ovl_death_append_str

.c_monster:
    LD   HL, death_cause_buf
    LD   A, (HL)
    OR   A
    JR   Z, .c_unknown
    ; Check if already starts with "a " or "an "
    LD   A, (HL)
    OR   0x20
    CP   'a'
    JR   NZ, .emit_a_pref
    INC  HL
    LD   A, (HL)
    DEC  HL
    CP   ' '
    JR   Z, .c_buf_direct
    OR   0x20
    CP   'n'
    JR   NZ, .emit_a_pref
    INC  HL
    INC  HL
    LD   A, (HL)
    DEC  HL
    DEC  HL
    CP   ' '
    JR   Z, .c_buf_direct
.emit_a_pref:
    LD   A, 'a'
    LD   (DE), A
    INC  DE
    LD   A, ' '
    LD   (DE), A
    INC  DE
.c_buf_direct:
    LD   B, 31
    JP   ovl_death_copy_bounded
.c_unknown:
    LD   HL, ovl_death_str_c_unknown
    JP   ovl_death_append_str

; ============================================================================
; High Score Rows Renderer — B = start_row (stops before SCREEN_ROWS - 1)
; ============================================================================
ovl_death_draw_hiscore_rows:
    LD   A, (hiscore_count)
    OR   A
    RET  Z
    CP   HISCORE_MAX_ENTRIES + 1
    JR   C, .cnt_valid
    LD   A, HISCORE_MAX_ENTRIES
.cnt_valid:
    LD   (ovl_death_row_cur), A
    LD   C, 0                   ; C = idx 0..count-1
.hs_loop:
    LD   A, B
    CP   SCREEN_ROWS - 1
    RET  NC
    LD   A, (ovl_death_row_cur)
    CP   C
    RET  Z
    RET  C

    PUSH BC                     ; [row_b, idx_c]
    LD   A, C
    CALL ovl_death_hs_entry_ptr
    PUSH HL
    POP  IX                     ; IX = entry ptr (23 B)

    ; Color: COL_YELLOW if idx == new_rank, else COL_LGREY
    LD   A, (ovl_death_new_rank)
    CP   C
    LD   E, COL_LGREY
    JR   NZ, .clr_ok
    LD   E, COL_YELLOW
.clr_ok:
    PUSH DE                     ; [row_color]
    PUSH BC                     ; [row_b, idx_c]

    LD   DE, line_buf
    ; " N. " (2-char RJ)
    LD   A, C
    INC  A
    CALL .append_rj2
    LD   A, '.'
    LD   (DE), A
    INC  DE
    LD   A, ' '
    LD   (DE), A
    INC  DE

    ; 24-bit decimal score + ' '
    LD   L, (IX + 16)
    LD   H, (IX + 17)
    LD   A, (IX + 18)
    PUSH DE
    LD   E, A
    LD   BC, temp_str_buf
    CALL status_fmt_u24
    POP  DE
    LD   HL, temp_str_buf
    CALL ovl_death_append_str
    LD   A, ' '
    LD   (DE), A
    INC  DE

    ; Up to 12 chars of name, stopping at first space or NUL (score.s:664-672)
    PUSH IX
    POP  HL
    LD   B, 12
.hd_name:
    LD   A, (HL)
    OR   A
    JR   Z, .hd_pad
    CP   ' '
    JR   Z, .hd_pad
    LD   (DE), A
    INC  HL
    INC  DE
    DJNZ .hd_name
.hd_pad:
    ; Pad with spaces until line_buf len >= (SDS_HISCORE_PAD_COL - SDS_HISCORE_ROW_COL) = 29
    LD   HL, line_buf
    LD   A, E
    SUB  L
.pad_lp:
    CP   SDS_HISCORE_PAD_COL - SDS_HISCORE_ROW_COL
    JR   NC, .pad_done
    LD   B, A
    LD   A, ' '
    LD   (DE), A
    INC  DE
    LD   A, B
    INC  A
    JR   .pad_lp
.pad_done:

    ; "LV" + 2-char RJ level + optional " WIN"
    LD   HL, ovl_death_str_lv
    CALL ovl_death_append_str
    LD   A, (IX + 19)
    CALL .append_rj2
    BIT  7, (IX + 22)
    JR   Z, .row_print
    LD   HL, ovl_death_str_win_tag
    CALL ovl_death_append_str
.row_print:
    XOR  A
    LD   (DE), A
    POP  BC                     ; B = row
    POP  DE                     ; E = color
    LD   C, SDS_HISCORE_ROW_COL
    LD   HL, line_buf
    CALL screen_put_str

    POP  BC                     ; B = row, C = idx
    INC  B
    INC  C
    JP   .hs_loop

.append_rj2:
    CP   10
    JR   NC, .rj2_dec
    LD   B, A
    LD   A, ' '
    LD   (DE), A
    INC  DE
    LD   A, B
.rj2_dec:
    JP   fmt_u8_dec

; ============================================================================
; Helpers
; ============================================================================
ovl_death_copy_name16:
    LD   B, PL_NAME_MAX
ovl_death_copy_bounded:
.lp:
    LD   A, (HL)
    OR   A
    JR   Z, .done
    LD   (DE), A
    INC  HL
    INC  DE
    DJNZ .lp
.done:
    XOR  A
    LD   (DE), A
    RET

ovl_death_append_str:
    LD   A, (HL)
    OR   A
    RET  Z
    LD   (DE), A
    INC  HL
    INC  DE
    XOR  A
    LD   (DE), A
    JR   ovl_death_append_str

ovl_death_nth_str:
    OR   A
    RET  Z
    PUSH BC
    LD   B, A
.scan:
    LD   A, (HL)
    INC  HL
    OR   A
    JR   NZ, .scan
    DJNZ .scan
    POP  BC
    RET

; ============================================================================
; Local State & Read-Only Strings
; ============================================================================
ovl_death_eff_flags: DB 0
ovl_death_eff_src:   DB 0
ovl_death_new_rank:  DB 0xFF
ovl_death_row_cur:   DB 0
ovl_death_score:     DB 0, 0, 0
ovl_death_tmp24:     DB 0, 0, 0

ovl_death_crown_lines:
    DB "                 #                  ", 0
    DB "               #####                ", 0
    DB "                 #                  ", 0
    DB "           ,,,  $$$  ,,,            ", 0
    DB "        ,,=$   $$$$$   $=,,         ", 0
    DB "       $$      $$$$$      $$        ", 0
    DB "         *#######*#######*          ", 0

ovl_death_str_died_hdr:  DB "* You have died *", 0
ovl_death_str_win_hdr:   DB "* Total Winner *", 0
ovl_death_str_retired:   DB "Ripe Old Age", 0
ovl_death_str_killed_by: DB "Killed by ", 0
ovl_death_str_lvl:       DB "  Level ", 0
ovl_death_str_dlvl:      DB "Killed on dungeon level ", 0
ovl_death_str_exp:       DB "Experience:", 0
ovl_death_str_gold:      DB "Gold:", 0
ovl_death_str_dbonus:    DB "Depth Bonus:", 0
ovl_death_str_total:     DB "Total Score:", 0
ovl_death_str_wizard_no: DB "WIZARD RUN - NO RANK", 0
ovl_death_str_hs_hdr:    DB "-------- High Scores --------", 0
ovl_death_str_lv:        DB "LV", 0
ovl_death_str_win_tag:   DB " WIN", 0
ovl_death_str_press:     DB "Press any key", 0

ovl_death_str_c_poison:  DB "Poison", 0
ovl_death_str_c_starve:  DB "Starvation", 0
ovl_death_str_c_cursed:  DB "a Cursed Item", 0
ovl_death_str_c_needle:  DB "a poison needle.", 0
ovl_death_str_c_expl:    DB "an exploding chest.", 0
ovl_death_str_c_unknown: DB "Unknown Causes", 0

ovl_death_trap_causes:
    DB "an open pit", 0, "an arrow trap", 0, "a poison dart", 0, "falling rock.", 0

ovl_death_race_names:
    DB "Human", 0, "Half-Elf", 0, "Elf", 0, "Halfling", 0
    DB "Gnome", 0, "Dwarf", 0, "Half-Orc", 0, "Half-Troll", 0

ovl_death_class_names:
    DB "Warrior", 0, "Mage", 0, "Priest", 0, "Rogue", 0, "Ranger", 0, "Paladin", 0

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end

    SAVEBIN "ovl_death.ovl", ovl_start, ovl_end - ovl_start
