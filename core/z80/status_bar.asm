; status_bar.asm — 80-column Moria8 bottom status bar renderer (rows 21..23).
;
; Matches core/6502/ui_status.s + platforms/commodore/c128/hal/layout.s:
;   Row 21: Name [States]                             LV:<lvl> DL:<dlvl>
;   Row 22: ST:<18/xx> IN:<..> WI:<..> DX:<..> CO:<..> CH:<..>
;   Row 23: HP:<hp/mhp> MP:<mp/mmp> AC:<ac> AU:<gold24>
;
; Resident core module included once by platforms/z80/cpm/main.asm.
; Uses pure 0xNN hex syntax for sjasmplus v1.24.0 (DEVICE NOSLOT64K).
; All public entry points preserve IX and IY.

    IFNDEF CORE_Z80_STATUS_BAR_ASM
    DEFINE CORE_Z80_STATUS_BAR_ASM 1

    EXPORT status_draw
    EXPORT status_mark_dirty
    EXPORT status_put_stat_val
    EXPORT status_put_stat_val_full
    EXPORT status_fmt_u24

STS_R21_NAME_COL    EQU 1
STS_R21_LV_COL      EQU 58
STS_R21_DL_COL      EQU 66
STS_R22_STEP        EQU 13
STS_R23_HP_COL      EQU 1
STS_R23_MP_COL      EQU 16
STS_R23_AC_COL      EQU 31
STS_R23_AU_COL      EQU 44

; ============================================================
; status_mark_dirty — Invalidate diff cache & force full status redraw (rows 21..23).
; Preserves: AF, BC, DE, HL, IX, IY
; ============================================================
status_mark_dirty:
    PUSH AF
    XOR  A
    LD   (status_cache_valid), A
    LD   A, (zp_ui_dirty)
    OR   UI_DIRTY_STATUS | UI_DIRTY_FORCE
    LD   (zp_ui_dirty), A
    POP  AF
    RET

; ============================================================
; status_put_stat_val — Format status-bar stat A (capped at 18) into DE (NUL-terminated).
; Input:  A = stat (3..118), DE = dest buffer
; Output: DE = NUL byte ptr (e.g. " 8", "18")
; Preserves: IX, IY (clobbers AF, BC, HL)
; ============================================================
status_put_stat_val:
    CP   19
    JR   C, .ok
    LD   A, 18                  ; Cap 18/xx display to 18 (matching 6502 ui_status.s)
.ok:
    CP   10
    JR   NC, .normal
    PUSH AF
    LD   A, ' '
    LD   (DE), A
    INC  DE
    POP  AF
.normal:
    JP   fmt_u8_dec

; ============================================================
; status_put_stat_val_full — Format full stat A (3..118 -> "18/xx", "18/00") into DE.
; Input:  A = stat (3..118), DE = dest buffer
; Output: DE = NUL byte ptr
; Preserves: IX, IY (clobbers AF, BC, HL)
; ============================================================
status_put_stat_val_full:
    CP   19
    JR   C, status_put_stat_val
    PUSH AF
    LD   A, '1'
    LD   (DE), A
    INC  DE
    LD   A, '8'
    LD   (DE), A
    INC  DE
    LD   A, '/'
    LD   (DE), A
    INC  DE
    POP  AF
    CP   118
    JR   NZ, .sub18
    XOR  A
    JR   .tens
.sub18:
    SUB  18
.tens:
    LD   B, '0'
.t_lp:
    CP   10
    JR   C, .t_done
    SUB  10
    INC  B
    JR   .t_lp
.t_done:
    LD   C, A
    LD   A, B
    LD   (DE), A
    INC  DE
    LD   A, C
    ADD  A, '0'
    LD   (DE), A
    INC  DE
    XOR  A
    LD   (DE), A
    RET

; ============================================================
; status_fmt_u24 — Format 24-bit unsigned (E:HL) into ASCII decimal at BC.
; Input:  HL = low 16 bits, E = high 8 bits, BC = dest buffer (>= 9 B)
; Output: HL = dest buffer start, B = digit count (1..8)
; Preserves: IX, IY (clobbers AF, DE, HL, BC)
; ============================================================
status_fmt_u24:
    PUSH BC                     ; SP+4: dest_buf
    PUSH IX                     ; SP+2: caller IX
    PUSH IY                     ; SP+0: caller IY
    PUSH BC
    POP  IY                     ; IY = dest_ptr
    LD   IX, .pow24_tbl
    LD   C, E                   ; C = val_hi, HL = val_lo16
    LD   D, 7                   ; D = 7 powers of 10 (10^7 .. 10^1)
    LD   E, 0                   ; E = bit7 started | low4 len
.p24_loop:
    LD   B, '0'
.p24_sub:
    PUSH HL
    PUSH BC
    LD   A, L
    SUB  (IX + 0)
    LD   L, A
    LD   A, H
    SBC  A, (IX + 1)
    LD   H, A
    LD   A, C
    SBC  A, (IX + 2)
    JR   C, .p24_borrow
    LD   C, A
    POP  AF
    POP  AF
    INC  B
    JR   .p24_sub
.p24_borrow:
    POP  BC
    POP  HL
    LD   A, B
    CP   '0'
    JR   NZ, .p24_emit
    BIT  7, E
    JR   Z, .p24_next
.p24_emit:
    SET  7, E
    LD   (IY + 0), A
    INC  IY
    INC  E
.p24_next:
    INC  IX
    INC  IX
    INC  IX
    DEC  D
    JR   NZ, .p24_loop

    LD   A, L
    ADD  A, '0'
    LD   (IY + 0), A
    INC  IY
    XOR  A
    LD   (IY + 0), A
    LD   A, E
    AND  0x0F
    INC  A
    LD   B, A
    POP  IY
    POP  IX
    POP  HL
    RET

.pow24_tbl:
    DB   0x80, 0x96, 0x98       ; 10,000,000
    DB   0x40, 0x42, 0x0F       ; 1,000,000
    DB   0xA0, 0x86, 0x01       ; 100,000
    DB   0x10, 0x27, 0x00       ; 10,000
    DB   0xE8, 0x03, 0x00       ; 1,000
    DB   0x64, 0x00, 0x00       ; 100
    DB   0x0A, 0x00, 0x00       ; 10

; ============================================================
; status_draw — Draw changed status bar rows 21..23 (all rows if cache cold or forced).
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
status_draw:
    CALL _status_row_dirty_mask ; sets (status_dirty_rows) bit0/1/2
    LD   A, (status_dirty_rows)
    OR   A
    JR   Z, .clear_dirty

    LD   B, INPUT_ROW
    CALL screen_clear_row

    LD   A, (status_dirty_rows)
    BIT  0, A
    CALL NZ, _status_draw_row21
    LD   A, (status_dirty_rows)
    BIT  1, A
    CALL NZ, _status_draw_row22
    LD   A, (status_dirty_rows)
    BIT  2, A
    CALL NZ, _status_draw_row23

    CALL _status_update_cache
.clear_dirty:
    LD   A, (zp_ui_dirty)
    AND  0xFF ^ (UI_DIRTY_STATUS | UI_DIRTY_FORCE)
    LD   (zp_ui_dirty), A
    RET

; Build bitmask of dirty rows in status_dirty_rows (bit0=row21, bit1=row22, bit2=row23)
_status_row_dirty_mask:
    LD   A, (zp_ui_dirty)
    AND  UI_DIRTY_FORCE
    JR   NZ, .all_dirty
    LD   A, (status_cache_valid)
    OR   A
    JR   NZ, .chk_rows
.all_dirty:
    LD   A, 0x07
    LD   (status_dirty_rows), A
    RET
.chk_rows:
    XOR  A
    LD   (status_dirty_rows), A
    ; Row 21: lvl, dlvl, hunger, status_state
    LD   A, (player_data + PL_LEVEL)
    LD   HL, status_prev_lvl
    CP   (HL)
    JR   NZ, .r21
    LD   A, (player_data + PL_DLEVEL)
    LD   HL, status_prev_dlvl
    CP   (HL)
    JR   NZ, .r21
    LD   A, (zp_hunger_state)
    LD   HL, status_prev_hunger
    CP   (HL)
    JR   NZ, .r21
    CALL _status_pack_state
    LD   HL, status_prev_state
    CP   (HL)
    JR   Z, .chk_r22
.r21:
    LD   A, 0x01
    LD   (status_dirty_rows), A
.chk_r22:
    LD   HL, player_data + PL_STR_CUR
    LD   DE, status_prev_stats
    LD   B, STAT_COUNT
.s_cmp:
    LD   A, (DE)
    CP   (HL)
    JR   NZ, .r22
    INC  HL
    INC  DE
    DJNZ .s_cmp
    JR   .chk_r23
.r22:
    LD   HL, status_dirty_rows
    SET  1, (HL)
.chk_r23:
    ; Check HP/MHP/MP/MMP/AC (7 B) and GOLD (3 B)
    LD   HL, player_data + PL_HP_LO
    LD   DE, status_prev_hp
    LD   B, 7
.v_cmp1:
    LD   A, (DE)
    CP   (HL)
    JR   NZ, .r23
    INC  HL
    INC  DE
    DJNZ .v_cmp1
    LD   HL, player_data + PL_GOLD_0
    LD   B, 3
.v_cmp2:
    LD   A, (DE)
    CP   (HL)
    JR   NZ, .r23
    INC  HL
    INC  DE
    DJNZ .v_cmp2
    RET
.r23:
    LD   HL, status_dirty_rows
    SET  2, (HL)
    RET

_status_update_cache:
    LD   A, (player_data + PL_LEVEL)
    LD   (status_prev_lvl), A
    LD   A, (player_data + PL_DLEVEL)
    LD   (status_prev_dlvl), A
    LD   A, (zp_hunger_state)
    LD   (status_prev_hunger), A
    CALL _status_pack_state
    LD   (status_prev_state), A
    LD   HL, player_data + PL_STR_CUR
    LD   DE, status_prev_stats
    LD   BC, STAT_COUNT
    LDIR
    LD   HL, player_data + PL_HP_LO
    LD   DE, status_prev_hp
    LD   BC, 7
    LDIR
    LD   HL, player_data + PL_GOLD_0
    LD   BC, 3
    LDIR
    LD   A, 1
    LD   (status_cache_valid), A
    RET

; Pack poison/search/rest into 1 byte for Row 21 dirty check (matching 6502 ui_status.s)
_status_pack_state:
    LD   A, (player_data + PL_FLAGS)
    AND  (PLF_SEARCHING | PLF_RESTING)
    LD   C, A
    LD   A, (zp_eff_poison)
    OR   A
    JR   Z, .np
    SET  7, C
.np:
    LD   A, C
    RET

; ============================================================
; Row 21: Name [Hunger] [Poisoned] [Search*/Rest*]           LV:nn DL:nn
; ============================================================
_status_draw_row21:
    LD   B, STATUS_ROW0
    CALL screen_clear_row

    ; Name (max 16 chars) at col 1 in COL_WHITE
    LD   HL, player_data + PL_NAME
    LD   B, STATUS_ROW0
    LD   C, STS_R21_NAME_COL
    LD   E, COL_WHITE
    CALL screen_put_str
    LD   HL, player_data + PL_NAME
    CALL _sts_strlen_max16
    ADD  A, STS_R21_NAME_COL
    LD   C, A                   ; C = current col

    ; Urgent status words (each preceded by space if fits before STS_R21_LV_COL - 1)
    LD   A, (zp_hunger_state)
    OR   A
    JR   Z, .chk_pois
    CP   HUNGER_HUNGRY
    LD   HL, _sts_s_hungry
    LD   E, COL_YELLOW
    JR   Z, .put_h
    CP   HUNGER_WEAK
    LD   HL, _sts_s_weak
    LD   E, COL_RED
    JR   Z, .put_h
    LD   HL, _sts_s_faint
.put_h:
    CALL _sts_put_state_word

.chk_pois:
    LD   A, (zp_eff_poison)
    OR   A
    JR   Z, .chk_mode
    LD   HL, _sts_s_poison
    LD   E, COL_RED
    CALL _sts_put_state_word

.chk_mode:
    LD   A, (player_data + PL_FLAGS)
    AND  (PLF_SEARCHING | PLF_RESTING)
    JR   Z, .draw_lv_dl
    AND  PLF_SEARCHING
    LD   HL, _sts_s_search
    JR   NZ, .put_mode
    LD   HL, _sts_s_rest
.put_mode:
    LD   E, COL_YELLOW
    CALL _sts_put_state_word

.draw_lv_dl:
    LD   B, STATUS_ROW0
    LD   C, STS_R21_LV_COL
    LD   E, COL_STATUS
    LD   HL, _sts_s_lv
    CALL screen_put_str
    LD   A, (player_data + PL_LEVEL)
    LD   DE, temp_str_buf
    CALL fmt_u8_dec
    LD   B, STATUS_ROW0
    LD   C, STS_R21_LV_COL + 3
    LD   E, COL_WHITE
    LD   HL, temp_str_buf
    CALL screen_put_str

    LD   B, STATUS_ROW0
    LD   C, STS_R21_DL_COL
    LD   E, COL_STATUS
    LD   HL, _sts_s_dl
    CALL screen_put_str
    LD   A, (player_data + PL_DLEVEL)
    LD   DE, temp_str_buf
    CALL fmt_u8_dec
    LD   B, STATUS_ROW0
    LD   C, STS_R21_DL_COL + 3
    LD   E, COL_WHITE
    LD   HL, temp_str_buf
    JP   screen_put_str

; Append ' ' + HL in color E at row 21 col C if (C + 1 + len < STS_R21_LV_COL).
; Updates C = new column!
_sts_put_state_word:
    CALL _sts_strlen_max16      ; A = len (up to 16)
    LD   B, A                   ; B = len
    INC  A
    ADD  A, C
    RET  C
    CP   STS_R21_LV_COL
    RET  NC
    INC  C
    PUSH BC
    LD   B, STATUS_ROW0
    CALL screen_put_str
    POP  BC
    LD   A, C
    ADD  A, B
    LD   C, A
    RET

_sts_strlen_max16:
    PUSH HL
    LD   B, 0
.lp:
    LD   A, (HL)
    OR   A
    JR   Z, .done
    INC  HL
    INC  B
    LD   A, B
    CP   PL_NAME_MAX
    JR   C, .lp
.done:
    LD   A, B
    POP  HL
    RET

; ============================================================
; Row 22: ST:nn IN:nn WI:nn DX:nn CO:nn CH:nn (cols 1,14,27,40,53,66)
; ============================================================
_status_draw_row22:
    LD   B, STATUS_ROW1
    CALL screen_clear_row
    LD   C, 1                   ; col
    LD   HL, _sts_stat_labels
    LD   DE, player_data + PL_STR_CUR
    LD   B, STAT_COUNT
.s_loop:
    PUSH BC
    PUSH DE
    PUSH HL
    LD   B, STATUS_ROW1
    LD   E, COL_STATUS
    CALL screen_put_str         ; prints "ST:" etc.
    POP  HL
    LD   DE, 4
    ADD  HL, DE                 ; next 4-byte label entry
    POP  DE                     ; DE -> stat byte
    POP  BC
    PUSH HL
    PUSH DE
    PUSH BC
    LD   A, (DE)
    LD   DE, temp_str_buf
    CALL status_put_stat_val
    POP  BC
    PUSH BC
    LD   A, C
    ADD  A, 3
    LD   C, A
    LD   B, STATUS_ROW1
    LD   E, COL_WHITE
    LD   HL, temp_str_buf
    CALL screen_put_str
    POP  BC
    LD   A, C
    ADD  A, STS_R22_STEP
    LD   C, A
    POP  DE
    INC  DE
    POP  HL
    DJNZ .s_loop
    RET

; ============================================================
; Row 23: HP:hh/mm MP:mm/mm AC:aa AU:ggggggg
; ============================================================
_status_draw_row23:
    LD   B, STATUS_ROW2
    CALL screen_clear_row

    ; "HP:"
    LD   B, STATUS_ROW2
    LD   C, STS_R23_HP_COL
    LD   E, COL_STATUS
    LD   HL, _sts_s_hp
    CALL screen_put_str
    LD   DE, temp_str_buf
    LD   HL, (player_data + PL_HP_LO)
    CALL fmt_u16_dec
    CALL _sts_hp_color          ; E = COL_HP_OK/WARN/CRIT
    LD   C, STS_R23_HP_COL + 3
    CALL _sts_r23_put
    PUSH BC
    LD   HL, temp_str_buf
    LD   (HL), '/'
    LD   DE, temp_str_buf + 1
    LD   HL, (player_data + PL_MHP_LO)
    CALL fmt_u16_dec
    POP  BC
    LD   E, COL_STATUS
    CALL _sts_r23_put

    ; "MP:"
    LD   B, STATUS_ROW2
    LD   C, STS_R23_MP_COL
    LD   E, COL_STATUS
    LD   HL, _sts_s_mp
    CALL screen_put_str
    LD   DE, temp_str_buf
    LD   A, (player_data + PL_MANA)
    CALL fmt_u8_dec
    LD   C, STS_R23_MP_COL + 3
    LD   E, COL_WHITE
    CALL _sts_r23_put
    LD   B, STATUS_ROW2
    LD   E, COL_STATUS
    LD   HL, _sts_s_slash
    PUSH BC
    CALL screen_put_str
    POP  BC
    INC  C
    PUSH BC
    LD   DE, temp_str_buf
    LD   A, (player_data + PL_MAX_MANA)
    CALL fmt_u8_dec
    POP  BC
    LD   B, STATUS_ROW2
    LD   E, COL_WHITE
    LD   HL, temp_str_buf
    CALL screen_put_str

    ; "AC:"
    LD   B, STATUS_ROW2
    LD   C, STS_R23_AC_COL
    LD   E, COL_STATUS
    LD   HL, _sts_s_ac
    CALL screen_put_str
    LD   DE, temp_str_buf
    LD   A, (player_data + PL_AC)
    CALL fmt_u8_dec
    LD   B, STATUS_ROW2
    LD   C, STS_R23_AC_COL + 3
    LD   E, COL_WHITE
    LD   HL, temp_str_buf
    CALL screen_put_str

    ; "AU:"
    LD   B, STATUS_ROW2
    LD   C, STS_R23_AU_COL
    LD   E, COL_YELLOW
    LD   HL, _sts_s_au
    CALL screen_put_str
    LD   HL, (player_data + PL_GOLD_0)
    LD   A, (player_data + PL_GOLD_2)
    LD   E, A
    LD   BC, temp_str_buf
    CALL status_fmt_u24
    LD   B, STATUS_ROW2
    LD   C, STS_R23_AU_COL + 3
    LD   E, COL_YELLOW
    LD   HL, temp_str_buf
    JP   screen_put_str

_sts_r23_put:
    PUSH BC
    LD   B, STATUS_ROW2
    LD   HL, temp_str_buf
    CALL screen_put_str
    POP  BC
    LD   HL, temp_str_buf
.len:
    LD   A, (HL)
    OR   A
    RET  Z
    INC  HL
    INC  C
    JR   .len

; Return E = COL_HP_OK (hp >= mhp), COL_HP_WARN (hp >= mhp/2), else COL_HP_CRIT.
_sts_hp_color:
    PUSH HL
    PUSH DE
    LD   HL, (player_data + PL_HP_LO)
    LD   DE, (player_data + PL_MHP_LO)
    OR   A
    SBC  HL, DE
    JR   NC, .ok
    ; Check hp >= mhp/2
    SRL  D
    RR   E
    LD   HL, (player_data + PL_HP_LO)
    OR   A
    SBC  HL, DE
    POP  DE
    POP  HL
    LD   E, COL_HP_WARN
    RET  NC
    LD   E, COL_HP_CRIT
    RET
.ok:
    POP  DE
    POP  HL
    LD   E, COL_HP_OK
    RET

_sts_stat_labels:
    DB   "ST:", 0, "IN:", 0, "WI:", 0, "DX:", 0, "CO:", 0, "CH:", 0
_sts_s_lv:     DB "LV:", 0
_sts_s_dl:     DB "DL:", 0
_sts_s_hp:     DB "HP:", 0
_sts_s_mp:     DB "MP:", 0
_sts_s_ac:     DB "AC:", 0
_sts_s_au:     DB "AU:", 0
_sts_s_slash:  DB "/", 0
_sts_s_hungry: DB "Hungry", 0
_sts_s_weak:   DB "Weak", 0
_sts_s_faint:  DB "Faint", 0
_sts_s_poison: DB "Poisoned", 0
_sts_s_search: DB "Search*", 0
_sts_s_rest:   DB "Rest*", 0

    ENDIF
