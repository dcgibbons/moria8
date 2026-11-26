; ovl_start.asm — Moria8 CP/M Character Creation & New-World Init Overlay (OVL_START, DAT slot 0).
;
; Fixed jump vectors at OVL_WINDOW_BASE (0x5600):
;   +0: JP ovl_start_player_create   -> interactive chargen (CF=0 created, CF=1 cancelled)
;   +3: JP ovl_start_init_new_world  -> starting kit/gold/flavours/stores restock init
;
; Reuses BSS tier_name_pool (832 B, unused during chargen) for temporary 200-byte
; background text accumulation so zero large DS buffers live inside ovl_start.ovl.
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax, DEVICE NOSLOT64K).

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "item_ids_z80.inc"
    INCLUDE "main_exp.inc"

    ORG  OVL_WINDOW_BASE        ; 0x5600

ovl_start:
    JP   ovl_start_player_create
    JP   ovl_start_init_new_world

OVL_START_BG_SCRATCH    EQU tier_name_pool
OVL_START_BG_BUF_MAX    EQU 199
OVL_START_BG_LINE_W     EQU 38
OVL_START_BG_STRIDE     EQU 40
OVL_START_START_FOOD    EQU 2000

; ===========================================================================
; ovl_start_player_create — Interactive 6-step Moria8 character creation.
; Output: CF = 0 if character & new world initialized; CF = 1 if cancelled (ESC).
; Preserves: IX, IY
; ===========================================================================
ovl_start_player_create:
    PUSH IX
    PUSH IY

    CALL player_init
    CALL inv_init

    ; Initialize PL_SPELL_ORDER (32 bytes) to 99 (empty)
    LD   HL, player_data + PL_SPELL_ORDER
    LD   B, 32
    LD   A, 99
.init_ord:
    LD   (HL), A
    INC  HL
    DJNZ .init_ord

    CALL ovl_start_select_race
    CALL ovl_start_roll_stats
    CALL ovl_start_select_class
    CALL ovl_start_enter_name
    CALL ovl_start_select_gender

    CALL ovl_start_gen_background
    CALL ovl_start_bake_and_vitals
    CALL ovl_start_init_gold_only
    CALL tramp_ui_character
    CALL ovl_start_init_new_world

    OR   A                      ; CF = 0 (created)
    POP  IY
    POP  IX
    RET

; ===========================================================================
; Step 1: Race Selection ("Choose your race")
; ===========================================================================
ovl_start_select_race:
    CALL screen_hard_clear

    LD   B, 0
    LD   C, 11
    LD   E, COL_WHITE
    LD   HL, ovl_start_str_race_title
    CALL screen_put_str

    LD   D, 0                   ; race index 0..7
.race_row:
    LD   A, D
    ADD  A, 2
    LD   B, A                   ; row = 2 + idx
    LD   C, 3
    LD   A, D
    ADD  A, 'a'
    LD   E, COL_LGREY
    CALL ovl_start_put_char
    LD   C, 4
    LD   A, ')'
    CALL ovl_start_put_char
    LD   C, 5
    LD   A, ' '
    CALL ovl_start_put_char

    ; Race name
    LD   A, D
    LD   HL, ovl_start_race_names
    CALL ovl_start_tbl_ptr
    LD   A, D
    ADD  A, 2
    LD   B, A
    LD   C, 6
    LD   E, COL_WHITE
    CALL ovl_start_put_str

    INC  D
    LD   A, D
    CP   RACE_COUNT
    JR   C, .race_row

    LD   B, 12
    LD   C, 3
    LD   E, COL_LGREY
    LD   HL, ovl_start_str_choose_race
    CALL screen_put_str
    CALL screen_flush
    LD   B, 12
    LD   C, 16
    CALL screen_set_cursor

.race_key:
    CALL input_get_key
    CALL ovl_start_to_lower
    SUB  'a'
    JR   C, .race_key
    CP   RACE_COUNT
    JR   NC, .race_key
    LD   (player_data + PL_RACE), A
    OR   A
    RET

; ===========================================================================
; Step 2: Stat Rolling ("Roll Statistics", d3+d4+d5+5, sum 73..84)
; ===========================================================================
ovl_start_roll_stats:
.reroll:
    CALL screen_hard_clear

    LD   B, 0
    LD   C, 12
    LD   E, COL_WHITE
    LD   HL, ovl_start_str_stats_title
    CALL screen_put_str

.reroll_all:
    LD   C, 0                   ; C = sum of 6 base stats
    LD   B, 0                   ; B = stat index 0..5
.roll_one:
    PUSH BC
    LD   A, 3
    CALL rng_range
    INC  A
    LD   D, A                   ; d3 (1..3)
    LD   A, 4
    CALL rng_range
    INC  A
    ADD  A, D
    LD   D, A                   ; d3 + d4
    LD   A, 5
    CALL rng_range
    INC  A
    ADD  A, D
    ADD  A, 5                   ; 8..17
    POP  BC

    LD   E, A                   ; E = rolled stat
    LD   A, C
    ADD  A, E
    LD   C, A                   ; sum += stat

    LD   HL, player_data + PL_STR_BASE
    LD   A, B
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   (HL), E

    INC  B
    LD   A, B
    CP   STAT_COUNT
    JR   C, .roll_one

    LD   A, C
    CP   73
    JR   C, .reroll_all
    CP   85
    JR   NC, .reroll_all

    ; Display all 6 stats: "STR: 14 (16)"
    LD   D, 0
.disp_stat:
    LD   A, D
    ADD  A, 2
    LD   B, A
    LD   C, 3
    LD   A, D
    LD   HL, ovl_start_stat_names
    CALL ovl_start_tbl_ptr
    LD   E, COL_LGREY
    CALL ovl_start_put_str

    LD   C, 6
    LD   A, ':'
    CALL ovl_start_put_char

    ; Base stat
    LD   HL, player_data + PL_STR_BASE
    LD   A, D
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)
    PUSH BC
    PUSH DE
    LD   DE, line_buf
    CALL status_put_stat_val_full
    POP  DE
    POP  BC
    LD   C, 7
    LD   E, COL_WHITE
    LD   HL, line_buf
    CALL ovl_start_put_str

    ; Race-modified preview: " (" + CYAN val + ")"
    LD   C, 10
    LD   A, '('
    LD   E, COL_LGREY
    CALL ovl_start_put_char
    LD   A, D
    CALL ovl_start_calc_race_stat
    PUSH BC
    PUSH DE
    LD   DE, line_buf
    CALL status_put_stat_val_full
    POP  DE
    POP  BC
    LD   C, 11
    LD   E, COL_CYAN
    LD   HL, line_buf
    PUSH HL
    CALL ovl_start_put_str
    POP  HL
    LD   C, 11
.rp_col:
    LD   A, (HL)
    OR   A
    JR   Z, .put_rp
    INC  HL
    INC  C
    JR   .rp_col
.put_rp:
    LD   A, ')'
    LD   E, COL_LGREY
    CALL ovl_start_put_char

    INC  D
    LD   A, D
    CP   STAT_COUNT
    JR   C, .disp_stat

    LD   B, 10
    LD   C, 3
    LD   E, COL_LGREY
    LD   HL, ovl_start_str_reroll
    CALL screen_put_str
    CALL screen_flush
    LD   B, 10
    LD   C, 29
    CALL screen_set_cursor

.stat_key:
    CALL input_get_key
    CP   KEY_CR
    JR   Z, .stat_accept
    CALL ovl_start_to_lower
    CP   'r'
    JP   Z, .reroll
    JR   .stat_key
.stat_accept:
    OR   A
    RET

; Calculate race-modified stat preview for stat A (0..5) -> A
ovl_start_calc_race_stat:
    PUSH BC
    PUSH DE
    PUSH HL
    LD   C, A                   ; C = stat index
    LD   HL, player_data + PL_STR_BASE
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)
    LD   (ovl_start_stat_work), A

    LD   A, (player_data + PL_RACE)
    ADD  A, A
    LD   B, A
    ADD  A, A
    ADD  A, B                   ; race * 6
    ADD  A, C                   ; + stat_idx
    LD   HL, ovl_start_race_stat_adj
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)
    CALL ovl_start_apply_modifier
    LD   A, (ovl_start_stat_work)
    POP  HL
    POP  DE
    POP  BC
    RET

; ===========================================================================
; Step 3: Class Selection ("Choose your class", filtered by race_class_flags)
; ===========================================================================
ovl_start_select_class:
    CALL screen_hard_clear

    LD   B, 0
    LD   C, 10
    LD   E, COL_WHITE
    LD   HL, ovl_start_str_class_title
    CALL screen_put_str

    LD   A, (player_data + PL_RACE)
    LD   HL, ovl_start_race_class_flags
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)
    LD   (ovl_start_tmp0), A    ; allowed bitmask

    XOR  A
    LD   (ovl_start_tmp1), A    ; valid count
    LD   D, 0                   ; class index 0..5
    LD   C, 1                   ; rotating bit mask
.cls_loop:
    LD   A, (ovl_start_tmp0)
    AND  C
    JR   Z, .cls_next

    PUSH BC
    PUSH DE
    LD   A, (ovl_start_tmp1)
    LD   E, A
    LD   HL, ovl_start_class_map
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   (HL), D                ; class_map[valid] = class_idx

    LD   A, E
    ADD  A, 2
    LD   B, A
    LD   C, 3
    LD   A, E
    ADD  A, 'a'
    LD   E, COL_LGREY
    CALL ovl_start_put_char
    LD   C, 4
    LD   A, ')'
    CALL ovl_start_put_char
    LD   C, 5
    LD   A, ' '
    CALL ovl_start_put_char

    LD   A, D
    LD   HL, ovl_start_class_names
    CALL ovl_start_tbl_ptr
    LD   C, 6
    LD   E, COL_WHITE
    CALL ovl_start_put_str

    LD   HL, ovl_start_tmp1
    INC  (HL)
    POP  DE
    POP  BC

.cls_next:
    SLA  C
    INC  D
    LD   A, D
    CP   CLASS_COUNT
    JR   C, .cls_loop

    ; Prompt row = valid_count + 3
    LD   A, (ovl_start_tmp1)
    ADD  A, 3
    LD   B, A
    LD   C, 3
    LD   E, COL_LGREY
    LD   HL, ovl_start_str_choose_cls
    CALL screen_put_str

    LD   A, (ovl_start_tmp1)
    ADD  A, 3
    LD   B, A
    LD   C, 13
    LD   A, (ovl_start_tmp1)
    DEC  A
    ADD  A, 'a'
    LD   E, COL_LGREY
    CALL ovl_start_put_char
    LD   C, 14
    LD   A, ')'
    CALL ovl_start_put_char

    CALL screen_flush
    LD   A, (ovl_start_tmp1)
    ADD  A, 3
    LD   B, A
    LD   C, 16
    CALL screen_set_cursor

.cls_key:
    CALL input_get_key
    CALL ovl_start_to_lower
    SUB  'a'
    JR   C, .cls_key
    LD   HL, ovl_start_tmp1
    CP   (HL)
    JR   NC, .cls_key

    LD   HL, ovl_start_class_map
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)
    LD   (player_data + PL_CLASS), A
    OR   A
    RET

; ===========================================================================
; Step 4: Name Entry ("Enter your name", row 4 col 3, <= 16 chars, blank=default)
; ===========================================================================
ovl_start_enter_name:
    CALL screen_hard_clear

    LD   B, 0
    LD   C, 10
    LD   E, COL_WHITE
    LD   HL, ovl_start_str_name_title
    CALL screen_put_str

    LD   B, 2
    LD   C, 3
    LD   E, COL_LGREY
    LD   HL, ovl_start_str_name_prompt
    CALL screen_put_str

    XOR  A
    LD   (ovl_start_tmp0), A    ; current length (0..16)
    LD   (player_data + PL_NAME), A

.name_redraw_cursor:
    CALL screen_flush
    LD   A, (ovl_start_tmp0)
    ADD  A, 3
    LD   C, A
    LD   B, 4
    CALL screen_set_cursor

.name_key:
    CALL input_get_key
    CP   KEY_CR
    JR   Z, .name_done
    CP   KEY_BS
    JR   Z, .name_bs
    CP   KEY_DEL
    JR   Z, .name_bs

    ; Allow letters, digits, space, hyphen (no apostrophe, matching player_create.s)
    CP   ' '
    JR   Z, .name_add
    CP   '-'
    JR   Z, .name_add
    CP   '0'
    JR   C, .name_key
    CP   '9' + 1
    JR   C, .name_add
    CP   'A'
    JR   C, .name_key
    CP   'Z' + 1
    JR   C, .name_add
    CP   'a'
    JR   C, .name_key
    CP   'z' + 1
    JR   NC, .name_key

.name_add:
    LD   B, A
    LD   A, (ovl_start_tmp0)
    CP   PL_NAME_MAX
    JR   NC, .name_key

    LD   E, A
    LD   D, 0
    LD   HL, player_data + PL_NAME
    ADD  HL, DE
    LD   (HL), B
    INC  HL
    LD   (HL), 0
    INC  A
    LD   (ovl_start_tmp0), A

    LD   A, E
    ADD  A, 3
    LD   C, A
    LD   A, B
    LD   B, 4
    LD   E, COL_WHITE
    CALL screen_put_char
    JP   .name_redraw_cursor

.name_bs:
    LD   A, (ovl_start_tmp0)
    OR   A
    JR   Z, .name_key
    DEC  A
    LD   (ovl_start_tmp0), A
    LD   E, A
    LD   D, 0
    LD   HL, player_data + PL_NAME
    ADD  HL, DE
    LD   (HL), 0

    LD   A, E
    ADD  A, 3
    LD   C, A
    LD   B, 4
    LD   A, ' '
    LD   E, COL_WHITE
    CALL screen_put_char
    JP   .name_redraw_cursor

.name_done:
    LD   A, (ovl_start_tmp0)
    OR   A
    JR   Z, .name_key           ; Forbid blank name (player_create.s)
    RET

; ===========================================================================
; Step 5: Gender Selection ("Choose your sex")
; ===========================================================================
ovl_start_select_gender:
    CALL screen_hard_clear

    LD   B, 0
    LD   C, 10
    LD   E, COL_WHITE
    LD   HL, ovl_start_str_gender_title
    CALL screen_put_str

    LD   B, 2
    LD   C, 3
    LD   E, COL_LGREY
    LD   HL, ovl_start_str_gender_m
    CALL screen_put_str

    LD   B, 3
    LD   C, 3
    LD   E, COL_LGREY
    LD   HL, ovl_start_str_gender_f
    CALL screen_put_str

    CALL screen_flush
    LD   B, 5
    LD   C, 3
    CALL screen_set_cursor

.gen_key:
    CALL input_get_key
    CALL ovl_start_to_lower
    CP   'a'
    JR   Z, .male
    CP   'b'
    JR   Z, .female
    JR   .gen_key
.male:
    LD   A, PLF_MALE
    LD   (player_data + PL_FLAGS), A
    OR   A
    RET
.female:
    XOR  A
    LD   (player_data + PL_FLAGS), A
    OR   A
    RET

; ===========================================================================
; Step 6: Background Generation & Word-Wrap into player_background (4 x 40)
; ===========================================================================
ovl_start_gen_background:
    ; Social class = rng_range(4) + 1 (1..4) in HL (16-bit signed accumulator)
    LD   A, 4
    CALL rng_range
    INC  A
    LD   L, A
    LD   H, 0
    LD   (ovl_start_sc_accum), HL

    XOR  A
    LD   (ovl_start_bg_len), A
    LD   (OVL_START_BG_SCRATCH), A

    LD   A, (player_data + PL_RACE)
    LD   HL, ovl_start_bg_race_start
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)                ; chart ID

.chain_loop:
    OR   A
    JP   Z, .chain_done
    LD   C, A                   ; C = target chart ID
    LD   B, 0                   ; index 0..71
    LD   HL, ovl_start_bg_chart
.find_chart:
    LD   A, (HL)
    CP   C
    JR   Z, .found_chart
    INC  HL
    INC  B
    LD   A, B
    CP   OVL_START_BG_COUNT
    JR   C, .find_chart
    JR   .chain_done

.found_chart:
    LD   A, B
    PUSH AF                     ; save start index
    LD   A, 100
    CALL rng_range
    INC  A
    LD   C, A                   ; C = d100 roll (1..100)
    POP  AF
    LD   B, A                   ; B = start index

.roll_scan:
    LD   HL, ovl_start_bg_roll
    LD   A, B
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)
    CP   C
    JR   NC, .roll_match        ; bg_roll[idx] >= roll
    INC  B
    LD   A, B
    CP   OVL_START_BG_COUNT
    JR   C, .roll_scan
    JR   .chain_done

.roll_match:
    ; Expand compressed string bg_str_idx[B] to OVL_START_BG_SCRATCH
    PUSH BC                     ; B = matched index
    LD   E, B
    LD   D, 0
    LD   HL, ovl_start_bg_str_idx
    ADD  HL, DE
    LD   A, (HL)                ; string index 0..60
    LD   HL, ovl_start_bg_strings
    CALL ovl_start_nth_str      ; HL = compressed string

    LD   A, (ovl_start_bg_len)
    LD   E, A
    LD   D, 0
    LD   IX, OVL_START_BG_SCRATCH
    ADD  IX, DE                 ; IX = write cursor
    LD   C, A                   ; C = current len (0..199)
    CALL ovl_start_emit_bg_hl
    LD   (IX + 0), 0
    LD   A, C
    LD   (ovl_start_bg_len), A
    POP  BC                     ; B = matched index

    ; Accumulate social class: sc += bonus[B] - 50
    LD   HL, ovl_start_bg_bonus
    LD   A, B
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)
    SUB  50                     ; signed delta (-40..+100)
    LD   E, A
    ADD  A, A
    SBC  A, A
    LD   D, A                   ; DE = sign-extended delta
    LD   HL, (ovl_start_sc_accum)
    ADD  HL, DE
    LD   (ovl_start_sc_accum), HL

    ; Next chart
    LD   HL, ovl_start_bg_next
    LD   A, B
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)
    JP   .chain_loop

.chain_done:
    ; Clamp social class to [1, 100]
    LD   HL, (ovl_start_sc_accum)
    BIT  7, H
    JR   NZ, .sc_min
    LD   A, H
    OR   A
    JR   NZ, .sc_max
    LD   A, L
    OR   A
    JR   Z, .sc_min
    CP   101
    JR   C, .sc_ok
.sc_max:
    LD   A, 100
    JR   .sc_ok
.sc_min:
    LD   A, 1
.sc_ok:
    LD   (player_data + PL_SOCIAL_CLASS), A

    ; Clear player_background (160 B) before wrapping
    LD   HL, player_background
    LD   DE, player_background + 1
    LD   BC, PL_BG_SIZE - 1
    LD   (HL), 0
    LDIR

    ; Word-wrap OVL_START_BG_SCRATCH into 4 x 40 lines of player_background
    LD   HL, OVL_START_BG_SCRATCH
    LD   DE, player_background
    LD   B, 0                   ; line 0..3
.wrap_line:
    LD   A, B
    CP   4
    RET  NC
.skip_sp:
    LD   A, (HL)
    OR   A
    RET  Z
    CP   ' '
    JR   NZ, .count_rem
    INC  HL
    JR   .skip_sp

.count_rem:
    PUSH HL
    LD   C, 0
.cnt_lp:
    LD   A, (HL)
    OR   A
    JR   Z, .cnt_done
    INC  HL
    INC  C
    LD   A, C
    CP   OVL_START_BG_LINE_W + 1
    JR   C, .cnt_lp
.cnt_done:
    POP  HL                     ; HL = start of line text

    LD   A, C
    CP   OVL_START_BG_LINE_W + 1
    JR   C, .copy_tail          ; remaining <= 38 chars

    ; Scan backward from HL + 38 for space
    PUSH HL
    LD   A, OVL_START_BG_LINE_W
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A                   ; HL = start + 38
    LD   C, OVL_START_BG_LINE_W
.scan_back:
    DEC  HL
    DEC  C
    LD   A, (HL)
    CP   ' '
    JR   Z, .found_sp
    LD   A, C
    OR   A
    JR   NZ, .scan_back
    ; No space: hard break at 38
    POP  HL
    LD   C, OVL_START_BG_LINE_W
    JR   .copy_chunk
.found_sp:
    ; Break after space at offset C + 1
    INC  C
    POP  HL

.copy_chunk:
    PUSH DE                     ; line dest
    LD   A, C
    OR   A
    JR   Z, .trim_done
.copy_ch_lp:
    LD   A, (HL)
    OR   A
    JR   Z, .trim_back
    LD   (DE), A
    INC  HL
    INC  DE
    DEC  C
    JR   NZ, .copy_ch_lp
.trim_back:
    POP  IX                     ; IX = line dest start
    PUSH HL
    ; Trim trailing spaces back toward IX
    EX   DE, HL                 ; HL = end ptr
.tb_lp:
    PUSH HL
    OR   A
    PUSH IX
    POP  DE
    SBC  HL, DE
    POP  HL
    JR   Z, .tb_term
    DEC  HL
    LD   A, (HL)
    CP   ' '
    JR   Z, .tb_lp
    INC  HL
.tb_term:
    LD   (HL), 0
    POP  HL                     ; HL = next line source
    ; Recompute DE = IX + 40
    PUSH IX
    POP  DE
    PUSH HL
    LD   HL, OVL_START_BG_STRIDE
    ADD  HL, DE
    EX   DE, HL
    POP  HL
    INC  B
    JR   .wrap_line

.copy_tail:
    PUSH DE
    LD   A, (HL)
    OR   A
    JR   Z, .tail_done
.tail_lp:
    LD   A, (HL)
    OR   A
    JR   Z, .tail_done
    LD   (DE), A
    INC  HL
    INC  DE
    JR   .tail_lp
.tail_done:
    POP  BC                     ; BC = line dest start
    EX   DE, HL                 ; HL = end ptr
.tail_tb_lp:
    PUSH HL
    OR   A
    SBC  HL, BC
    POP  HL
    JR   Z, .tail_term
    DEC  HL
    LD   A, (HL)
    CP   ' '
    JR   Z, .tail_tb_lp
    INC  HL
.tail_term:
    LD   (HL), 0
    RET
.trim_done:
    POP  DE
    RET

; ===========================================================================
; Step 7: Bake Creation Stats, Age/Height/Weight, HP, Mana
; ===========================================================================
ovl_start_bake_and_vitals:
    LD   A, 1
    LD   (player_data + PL_LEVEL), A

    ; Bake 6 stats with randomized 18/xx stepping
    LD   A, (player_data + PL_RACE)
    ADD  A, A
    LD   B, A
    ADD  A, A
    ADD  A, B
    LD   (ovl_start_tmp0), A    ; race * 6

    LD   A, (player_data + PL_CLASS)
    ADD  A, A
    LD   B, A
    ADD  A, A
    ADD  A, B
    LD   (ovl_start_tmp1), A    ; class * 6

    LD   D, 0                   ; stat index 0..5
.bake_lp:
    LD   HL, player_data + PL_STR_BASE
    LD   A, D
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)
    LD   (ovl_start_stat_work), A

    ; Race adj
    LD   A, (ovl_start_tmp0)
    ADD  A, D
    LD   HL, ovl_start_race_stat_adj
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)
    CALL ovl_start_apply_modifier

    ; Class adj
    LD   A, (ovl_start_tmp1)
    ADD  A, D
    LD   HL, ovl_start_class_stat_adj
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)
    CALL ovl_start_apply_modifier

    LD   A, (ovl_start_stat_work)
    LD   HL, player_data + PL_STR_BASE
    LD   C, D
    LD   B, 0
    ADD  HL, BC
    LD   (HL), A                ; PL_*_BASE
    LD   BC, STAT_COUNT
    ADD  HL, BC
    LD   (HL), A                ; PL_*_CUR

    INC  D
    LD   A, D
    CP   STAT_COUNT
    JR   C, .bake_lp

    ; Combined Level-1 HP = race_HD + class_HD (PL_AGE/HEIGHT/WEIGHT remain 0, matching 6502)
    CALL ovl_start_calc_level1_vitals
    RET

; Compute Level-1 MHP=HP and Mana/SpellType (also usable by init_new_world fallback)
ovl_start_calc_level1_vitals:
    LD   A, (player_data + PL_RACE)
    LD   H, 0
    LD   L, A
    LD   A, 10
    CALL mul_hl_a
    LD   BC, ovl_start_race_props
    ADD  HL, BC
    LD   C, (HL)                ; race HD (mul_hl_a preserves C)

    LD   A, (player_data + PL_CLASS)
    LD   H, 0
    LD   L, A
    LD   A, 10
    CALL mul_hl_a
    LD   DE, ovl_start_class_props
    ADD  HL, DE
    LD   A, (HL)                ; class HD
    ADD  A, C
    LD   L, A
    LD   H, 0
    LD   (player_data + PL_HP_LO), HL
    LD   (player_data + PL_MHP_LO), HL

    ; Spell type & Level-1 Mana
    LD   A, (player_data + PL_CLASS)
    LD   H, 0
    LD   L, A
    LD   A, 10
    CALL mul_hl_a
    LD   BC, ovl_start_class_props + 1
    ADD  HL, BC
    LD   A, (HL)                ; spell_type (0=none, 1=mage, 2=priest)
    LD   (player_data + PL_SPELL_TYPE), A
    OR   A
    JR   Z, .no_mana

    LD   A, (player_data + PL_CLASS)
    LD   HL, ovl_start_class_spell_min
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (player_data + PL_LEVEL)
    CP   (HL)
    JR   C, .no_mana

    LD   A, (player_data + PL_SPELL_TYPE)
    CP   1                      ; SPELL_MAGE
    JR   NZ, .priest_mana
    LD   A, (player_data + PL_INT_CUR)
    JR   .calc_mana_band
.priest_mana:
    LD   A, (player_data + PL_WIS_CUR)
.calc_mana_band:
    LD   C, A                   ; C = INT or WIS stat value
    LD   HL, ovl_start_mana_min
    LD   B, 0
.mana_lp:
    LD   A, C
    CP   (HL)
    JR   C, .mana_got_band
    INC  HL
    INC  B
    LD   A, B
    CP   4
    JR   C, .mana_lp
.mana_got_band:
    LD   A, B
    OR   A
    JR   Z, .set_mana
    INC  A
.set_mana:
    LD   (player_data + PL_MANA), A
    LD   (player_data + PL_MAX_MANA), A
    JR   .mana_done
.no_mana:
    XOR  A
    LD   (player_data + PL_MANA), A
    LD   (player_data + PL_MAX_MANA), A
.mana_done:
    ; Starting learned spells for level-1 casters
    LD   A, (player_data + PL_CLASS)
    CP   CLASS_MAGE
    JR   NZ, .chk_priest_sp
    LD   A, 0x0F
    LD   B, 4
    JR   .set_sp
.chk_priest_sp:
    CP   CLASS_PRIEST
    JR   Z, .priest_sp
    CP   CLASS_PALADIN
    RET  NZ
.priest_sp:
    LD   A, 0x07
    LD   B, 3
.set_sp:
    LD   (player_data + PL_SPELLS_LEARNT_0), A
    LD   HL, player_data + PL_SPELL_ORDER
    LD   C, 0
.sp_ord:
    LD   (HL), C
    INC  HL
    INC  C
    DJNZ .sp_ord
    RET

ovl_start_init_gold_only:
    LD   A, 1
    LD   (player_data + PL_LEVEL), A
    CALL ovl_start_calc_gold
    JP   player_sync_to_abi

; ===========================================================================
; ovl_start_init_new_world — Vector +3: Initialize gold (if unset), kit, flavours, stores.
; Preserves: IX, IY
; ===========================================================================
ovl_start_init_new_world:
    PUSH IX
    PUSH IY

    ; Ensure level >= 1 and vitals valid if called standalone
    LD   A, (player_data + PL_LEVEL)
    OR   A
    JR   NZ, .lvl_ok
    LD   A, 1
    LD   (player_data + PL_LEVEL), A
    CALL ovl_start_calc_level1_vitals
.lvl_ok:
    ; Zero zp_state (32 B) and transient counters
    LD   HL, zp_state
    LD   DE, zp_state + 1
    LD   BC, ZP_STATE_SIZE - 1
    LD   (HL), 0
    LDIR
    LD   A, 0xFF
    LD   (zp_run_dir), A
    LD   (save_slot_selected), A

    XOR  A
    LD   (eff_fear_timer), A
    LD   (trap_count), A
    LD   (door_state_count), A
    LD   (room_count), A
    LD   (active_dungeon_count), A
    LD   (zp_msg_flags), A
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    LD   A, UI_DIRTY_FORCE | UI_DIRTY_STATUS | UI_DIRTY_MAP
    LD   (zp_ui_dirty), A

    ; Clear hg_kicked (8 B); preserve recall_data across New Game (matching 6502!)
    LD   HL, hg_kicked
    LD   DE, hg_kicked + 1
    LD   BC, STORE_COUNT - 1
    LD   (HL), 0
    LDIR

    ; Clear ALL 128 store/home slots (including Home 112..127!)
    LD   HL, si_item_id
    LD   DE, si_item_id + 1
    LD   BC, STORE_TOTAL_SLOTS - 1
    LD   (HL), FI_EMPTY
    LDIR

    ; Experience factor = race_xp% + class_xp%
    LD   A, (player_data + PL_RACE)
    LD   H, 0
    LD   L, A
    LD   A, 10
    CALL mul_hl_a
    LD   BC, ovl_start_race_props + 2
    ADD  HL, BC
    LD   C, (HL)                ; race XP% (mul_hl_a preserves C)

    LD   A, (player_data + PL_CLASS)
    LD   H, 0
    LD   L, A
    LD   A, 10
    CALL mul_hl_a
    LD   DE, ovl_start_class_props + 2
    ADD  HL, DE
    LD   A, (HL)
    ADD  A, C
    LD   (player_data + PL_EXPFACT), A

    ; Zero XP / Max XP, set Town dlvl = 0, food = 2000, light = 1
    XOR  A
    LD   (player_data + PL_DLEVEL), A
    LD   (player_data + PL_MAX_DLVL), A
    LD   (player_data + PL_XP_0), A
    LD   (player_data + PL_XP_1), A
    LD   (player_data + PL_XP_2), A
    LD   (player_data + PL_MAX_XP_0), A
    LD   (player_data + PL_MAX_XP_1), A
    LD   (player_data + PL_MAX_XP_2), A
    LD   (player_data + PL_HUNGER), A
    LD   HL, OVL_START_START_FOOD
    LD   (player_data + PL_FOOD_LO), HL
    LD   A, 1
    LD   (player_data + PL_LIGHT_RAD), A
    LD   (zp_light_radius), A

    ; Pseudo-ID rate
    LD   A, (player_data + PL_CLASS)
    LD   HL, ovl_start_pid_rate
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)
    LD   (player_data + PL_RESERVED), A

    ; Starting Gold if not already computed by ovl_start_player_create
    LD   HL, (player_data + PL_GOLD_0)
    LD   A, (player_data + PL_GOLD_2)
    OR   H
    OR   L
    CALL Z, ovl_start_calc_gold

    ; Starting Kit (matching starting_kit_cold.s: slot 0=rations, slot 1=book if caster, slot 2=torches)
    CALL inv_init
    ; Slot 0: 5 Rations of Food
    LD   A, ITEM_SLOT_RATION_OF_FOOD
    LD   (inv_item_id + 0), A
    LD   A, 5
    LD   (inv_qty + 0), A
    ; Slot 1 (if caster): starting spellbook / prayerbook
    LD   A, (player_data + PL_SPELL_TYPE)
    OR   A
    JR   Z, .no_book_kit
    CP   1
    LD   A, ITEM_SLOT_SPELLBOOK_BEGINNERS_MAGICK
    JR   Z, .put_book
    LD   A, ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_BEGINNERS_HANDBOOK
.put_book:
    LD   (inv_item_id + 1), A
    LD   A, 1
    LD   (inv_qty + 1), A
.no_book_kit:
    ; Slot 2: 4 Wooden Torches (p1 = 134)
    LD   A, ITEM_SLOT_WOODEN_TORCH
    LD   (inv_item_id + 2), A
    LD   A, 4
    LD   (inv_qty + 2), A
    LD   A, 134
    LD   (inv_p1 + 2), A

    ; Equipment: Torch (EQUIP_LIGHT), Dagger (EQUIP_WEAPON), Leather Armor (EQUIP_BODY)
    LD   A, ITEM_SLOT_WOODEN_TORCH
    LD   (inv_item_id + EQUIP_LIGHT), A
    LD   A, 1
    LD   (inv_qty + EQUIP_LIGHT), A
    LD   A, 134
    LD   (inv_p1 + EQUIP_LIGHT), A

    LD   A, ITEM_SLOT_DAGGER
    LD   (inv_item_id + EQUIP_WEAPON), A
    LD   A, 1
    LD   (inv_qty + EQUIP_WEAPON), A
    LD   A, ITEM_PAGE_DAGGER
    LD   (inv_ego + EQUIP_WEAPON), A

    LD   A, ITEM_SLOT_LEATHER_ARMOR
    LD   (inv_item_id + EQUIP_BODY), A
    LD   A, 1
    LD   (inv_qty + EQUIP_BODY), A

    ; Flavour shuffles & fixed known items (id_init_flavours calls id_refresh_fixed_known)
    CALL id_init_flavours

    CALL inv_calc_weight
    CALL player_calc_combat
    CALL player_sync_to_abi

    ; Stock all 7 town stores (A == 0 = initial full clear & restock)
    XOR  A
    CALL tramp_town_restock_all

    OR   A
    POP  IY
    POP  IX
    RET

; ===========================================================================
; Stat Modifier & Gold Formula Helpers (exact Umoria / player_create.s parity)
; ===========================================================================

; Apply signed modifier A to ovl_start_stat_work
ovl_start_apply_modifier:
    OR   A
    RET  Z
    BIT  7, A
    JR   NZ, .neg
    LD   B, A
.inc_lp:
    PUSH BC
    LD   A, (ovl_start_stat_work)
    CALL ovl_start_inc_stat
    LD   (ovl_start_stat_work), A
    POP  BC
    DJNZ .inc_lp
    RET
.neg:
    NEG
    LD   B, A
.dec_lp:
    PUSH BC
    LD   A, (ovl_start_stat_work)
    CALL ovl_start_dec_stat
    LD   (ovl_start_stat_work), A
    POP  BC
    DJNZ .dec_lp
    RET

ovl_start_inc_stat:
    CP   18
    JR   NC, .above_17
    INC  A
    RET
.above_17:
    CP   88
    JR   NC, .above_87
    PUSH AF
    LD   A, 15
    CALL rng_range
    ADD  A, 6                   ; 1d15+5 = 6..20
    JR   .add_cap
.above_87:
    CP   108
    JR   NC, .above_107
    PUSH AF
    LD   A, 6
    CALL rng_range
    ADD  A, 3                   ; 1d6+2 = 3..8
.add_cap:
    LD   B, A
    POP  AF
    ADD  A, B
    CP   119
    RET  C
    LD   A, 118
    RET
.above_107:
    INC  A
    CP   119
    RET  C
    LD   A, 118
    RET

ovl_start_dec_stat:
    CP   109
    JR   NC, .sub1
    CP   88
    JR   NC, .r88_108
    CP   19
    JR   NC, .r19_87
    CP   4
    RET  C
.sub1:
    DEC  A
    RET
.r88_108:
    PUSH AF
    LD   A, 6
    CALL rng_range
    ADD  A, 3
    JR   .sub_clamp
.r19_87:
    PUSH AF
    LD   A, 15
    CALL rng_range
    ADD  A, 6
.sub_clamp:
    LD   B, A
    POP  AF
    SUB  B
    CP   19
    RET  NC
    LD   A, 18
    RET

; Starting gold = SC*6 + rng(25) + 326 - 5*(sum5 - CHR) + (female?50:0), min 80
ovl_start_calc_gold:
    LD   A, (player_data + PL_SOCIAL_CLASS)
    LD   L, A
    LD   H, 0
    LD   A, 6
    CALL mul_hl_a                 ; HL = SC * 6
    PUSH HL
    LD   A, 25
    CALL rng_range
    LD   E, A
    LD   D, 0
    POP  HL
    ADD  HL, DE
    LD   DE, 326
    ADD  HL, DE                 ; HL = base gold

    ; Compute net_adj = sum_{0..4}(min(stat,18)-10) - (min(CHR,18)-10)
    PUSH HL
    LD   HL, player_data + PL_STR_CUR
    LD   C, 0                   ; signed 8-bit sum
    LD   B, 5
.cg_lp:
    LD   A, (HL)
    INC  HL
    CP   19
    JR   C, .cg_cap
    LD   A, 18
.cg_cap:
    SUB  10
    ADD  A, C
    LD   C, A
    DJNZ .cg_lp

    LD   A, (HL)                ; PL_CHR_CUR
    CP   19
    JR   C, .cg_chr
    LD   A, 18
.cg_chr:
    SUB  10
    LD   B, A
    LD   A, C
    SUB  B                      ; signed net_adj
    POP  HL                     ; HL = gold

    OR   A
    JR   Z, .cg_female
    BIT  7, A
    JR   NZ, .cg_add5
    ; Subtract 5 * net_adj
    LD   E, A
    LD   D, 0
    PUSH HL
    EX   DE, HL
    LD   A, 5
    CALL mul_hl_a
    EX   DE, HL                 ; DE = 5 * net_adj
    POP  HL
    OR   A
    SBC  HL, DE
    JR   NC, .cg_female
    LD   HL, 0
    JR   .cg_female
.cg_add5:
    NEG
    LD   E, A
    LD   D, 0
    PUSH HL
    EX   DE, HL
    LD   A, 5
    CALL mul_hl_a
    EX   DE, HL
    POP  HL
    ADD  HL, DE
.cg_female:
    LD   A, (player_data + PL_FLAGS)
    AND  PLF_MALE
    JR   NZ, .cg_min
    LD   DE, 50
    ADD  HL, DE
.cg_min:
    LD   A, H
    OR   A
    JR   NZ, .cg_store
    LD   A, L
    CP   80
    JR   NC, .cg_store
    LD   L, 80
.cg_store:
    LD   (player_data + PL_GOLD_0), HL
    XOR  A
    LD   (player_data + PL_GOLD_2), A
    RET

; ===========================================================================
; Small Formatting & Table Helpers
; ===========================================================================
ovl_start_put_char:
    PUSH BC
    PUSH DE
    CALL screen_put_char
    POP  DE
    POP  BC
    RET

ovl_start_put_str:
    PUSH BC
    PUSH DE
    CALL screen_put_str
    POP  DE
    POP  BC
    RET

ovl_start_to_lower:
    CP   'A'
    RET  C
    CP   'Z' + 1
    RET  NC
    OR   0x20
    RET

; Input: A = index, HL = DW pointer table -> Output: HL = string address
ovl_start_tbl_ptr:
    ADD  A, A
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)
    INC  HL
    LD   H, (HL)
    LD   L, A
    RET

; ===========================================================================
; Overlay Local Scratch (tiny variables only — NO DS 128+)
; ===========================================================================
ovl_start_tmp0:         DB 0
ovl_start_tmp1:         DB 0
ovl_start_stat_work:    DB 0
ovl_start_bg_len:       DB 0
ovl_start_sc_accum:     DW 0
ovl_start_class_map:    DS CLASS_COUNT

; ===========================================================================
; Race, Class, Stat, and Background Data Tables
; ===========================================================================
ovl_start_race_stat_adj:
    DB    0,  0,  0,  0,  0,  0         ; Human
    DB   -1,  1,  0,  1, -1,  1         ; Half-Elf
    DB   -1,  2,  1,  1, -2,  1         ; Elf
    DB   -2,  2,  1,  3,  1,  1         ; Halfling
    DB   -1,  2,  0,  2,  1, -2         ; Gnome
    DB    2, -3,  1, -2,  2, -3         ; Dwarf
    DB    2, -1,  0,  0,  1, -4         ; Half-Orc
    DB    4, -4, -2, -4,  3, -6         ; Half-Troll

ovl_start_class_stat_adj:
    DB    5, -2, -2,  2,  2, -1         ; Warrior
    DB   -5,  3,  0,  1, -2,  1         ; Mage
    DB   -3, -3,  3, -1,  0,  2         ; Priest
    DB    2,  1, -2,  3,  1, -1         ; Rogue
    DB    2,  2,  0,  1,  1,  1         ; Ranger
    DB    3, -3,  1,  0,  2,  2         ; Paladin

ovl_start_race_props:
    DB   10,  0, 100,  0,  0,  0,  0,  0,  0,  0
    DB    9,  2, 110,  2,  6,  1, -1, -1,  5,  3
    DB    8,  3, 120,  5,  8,  1, -2, -5, 15,  6
    DB    6,  4, 110, 15, 12,  4, -5,-10, 20, 18
    DB    7,  4, 125, 10,  6,  3, -3, -8, 12, 12
    DB    9,  5, 120,  2,  7, -1,  0, 15,  0,  9
    DB   10,  3, 110, -3,  0, -1,  3, 12, -5, -3
    DB   12,  3, 120, -5, -1, -2,  5, 20,-10, -8

ovl_start_race_class_flags:
    DB   0x3F, 0x3F, 0x1F, 0x0B, 0x0F, 0x05, 0x0D, 0x05

ovl_start_class_props:
    DB    9,  0,  0, 70, 55, 25, 18,  1, 14, 38
    DB    0,  1, 30, 34, 20, 30, 36,  2, 16, 20
    DB    2,  2, 20, 48, 35, 25, 30,  2, 16, 32
    DB    6,  1,  0, 60, 66, 45, 30,  5, 32, 16
    DB    4,  1, 40, 56, 72, 30, 30,  3, 24, 24
    DB    6,  2, 35, 68, 40, 20, 24,  1, 12, 38

ovl_start_class_spell_min:
    DB   0, 1, 1, 5, 3, 1
ovl_start_mana_min:
    DB   8, 68, 108, 118
ovl_start_pid_rate:
    DB   50, 150, 100, 75, 75, 100

ovl_start_race_names:
    DW   .r0, .r1, .r2, .r3, .r4, .r5, .r6, .r7
.r0: DB "Human", 0
.r1: DB "Half-Elf", 0
.r2: DB "Elf", 0
.r3: DB "Halfling", 0
.r4: DB "Gnome", 0
.r5: DB "Dwarf", 0
.r6: DB "Half-Orc", 0
.r7: DB "Half-Troll", 0

ovl_start_class_names:
    DW   .c0, .c1, .c2, .c3, .c4, .c5
.c0: DB "Warrior", 0
.c1: DB "Mage", 0
.c2: DB "Priest", 0
.c3: DB "Rogue", 0
.c4: DB "Ranger", 0
.c5: DB "Paladin", 0

ovl_start_stat_names:
    DW   .s0, .s1, .s2, .s3, .s4, .s5
.s0: DB "STR", 0
.s1: DB "INT", 0
.s2: DB "WIS", 0
.s3: DB "DEX", 0
.s4: DB "CON", 0
.s5: DB "CHR", 0

; UI Strings
ovl_start_str_race_title:   DB "Choose your race", 0
ovl_start_str_choose_race:  DB "Choose (a-h)", 0
ovl_start_str_stats_title:  DB "Roll Statistics", 0
ovl_start_str_reroll:       DB "r) Reroll  RETURN) Accept", 0
ovl_start_str_class_title:  DB "Choose your class", 0
ovl_start_str_choose_cls:   DB "Choose (a-", 0
ovl_start_str_name_title:   DB "Enter your name", 0
ovl_start_str_name_prompt:  DB "Name (16 chars max):", 0
ovl_start_str_gender_title: DB "Choose your sex", 0
ovl_start_str_gender_m:     DB "a) Male", 0
ovl_start_str_gender_f:     DB "b) Female", 0

; ===========================================================================
; Background Charts (72 entries matching core/6502/background_data.s)
; ===========================================================================
OVL_START_BG_COUNT EQU 72

ovl_start_bg_race_start:
    DB   1, 4, 7, 10, 13, 16, 19, 22

ovl_start_bg_chart:
    DB   1,1,1,1, 2,2,2,2,2,2,2, 3,3,3, 4,4,4,4,4,4
    DB   7,7, 8,8,8, 9,9,9,9,9,9, 10,10, 11,11,11,11,11,11,11,11
    DB   13,13, 14,14,14,14,14, 16,16, 17,17,17,17,17,17, 18,18,18
    DB   19,19, 20, 22,22,22,22,22,22, 23,23,23,23

ovl_start_bg_roll:
    DB   10,20,95,100, 40,65,80,90,96,99,100, 20,80,100, 40,75,90,95,98,100
    DB   60,100, 75,95,100, 40,70,87,95,99,100, 85,100, 20,30,40,50,80,95,99,100
    DB   85,100, 20,50,75,95,100, 25,100, 10,25,75,90,99,100, 15,85,100
    DB   25,100, 100, 30,60,75,90,95,100, 5,95,99,100

ovl_start_bg_next:
    DB   2,2,2,2, 3,3,3,3,3,3,3, 0,0,0, 1,1,1,1,1,1
    DB   8,8, 9,9,9, 0,0,0,0,0,0, 11,11, 3,3,3,3,3,3,3,3
    DB   14,14, 3,3,3,3,3, 17,17, 18,18,18,18,18,18, 0,0,0
    DB   20,20, 2, 23,23,23,23,23,23, 0,0,0,0

ovl_start_bg_bonus:
    DB   25,35,45,50, 65,80,90,105,120,130,140, 20,55,60, 50,55,55,60,65,70
    DB   50,55, 50,55,60, 80,90,110,125,140,145, 45,55, 55,80,90,100,110,115,125,140
    DB   45,55, 55,70,85,100,125, 40,50, 60,75,90,110,130,150, 10,50,55
    DB   25,25, 50, 20,25,30,35,40,45, 60,55,65,80

ovl_start_nth_str:
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

ovl_start_emit_bg_hl:
.lp:
    LD   A, (HL)
    INC  HL
    OR   A
    RET  Z
    BIT  7, A
    JR   Z, .literal
    AND  0x7F
    PUSH HL
    LD   HL, ovl_start_bg_tokens
    CALL ovl_start_nth_str
    CALL .lp
    POP  HL
    JR   .lp
.literal:
    LD   B, A
    LD   A, C
    CP   OVL_START_BG_BUF_MAX
    JR   NC, .lp
    LD   (IX + 0), B
    INC  IX
    INC  C
    JR   .lp

ovl_start_bg_str_idx:
    DB    3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14
    DB   15, 16, 17, 18, 19, 20, 21, 22,  5, 23, 24, 25
    DB   26, 27, 28,  0,  1, 29,  2, 30, 31, 32, 33, 34
    DB   35, 36,  0,  1, 37, 38, 39, 40, 41, 42,  0,  1
    DB   43, 44, 45, 46, 47,  0, 48,  2, 14, 15, 16, 49
    DB   50, 51, 52, 53, 54, 55, 56, 57, 58,  0, 59, 60

ovl_start_bg_tokens:
    DB   "th", 0x99, " was a", 0 ; 0x80
    DB   "You ", 0x98, 0x96, 0 ; 0x81
    DB   ".  ", 0 ; 0x82
    DB   " ch", 0x9B, "d", 0 ; 0x83
    DB   "of a ", 0 ; 0x84
    DB   "Your ", 0 ; 0x85
    DB   0x9E, "sev", 0x99, "al", 0x83, "re", 0x9F, 0 ; 0x86
    DB   "acknowl", 0x9C, "g", 0x9C, 0 ; 0x87
    DB   0x81, "th", 0x96, 0 ; 0x88
    DB   "-Troll ", 0 ; 0x89
    DB   "-Elf", 0 ; 0x8A
    DB   0x80, 0x9F, "Orc, but it is un", 0x87, 0x82, 0 ; 0x8B
    DB   0x85, "mo", 0x80, " ", 0 ; 0x8C
    DB   0x85, "fa", 0x80, " ", 0 ; 0x8D
    DB   0x88, "only", 0xA2, 0 ; 0x8E
    DB   0x99, 0x82, 0 ; 0x8F
    DB   0x88, 0x9B, "legitimat", 0x96, 0 ; 0x90
    DB   " th", 0x96, "fam", 0x9B, "y", 0x82, 0 ; 0x91
    DB   "Gre", 0 ; 0x92
    DB   "an", 0 ; 0x93
    DB   0x84, "Halfl", 0xA1, "g ", 0 ; 0x94
    DB   "High", 0x8A, 0 ; 0x95
    DB   "e ", 0 ; 0x96
    DB   0x84, "Dw", 0x98, "ve", 0x9F, 0 ; 0x97
    DB   "ar", 0 ; 0x98
    DB   "er", 0 ; 0x99
    DB   "m", 0x93, 0x82, 0 ; 0x9A
    DB   "il", 0 ; 0x9B
    DB   "ed", 0 ; 0x9C
    DB   0x92, "en", 0x8A, 0 ; 0x9D
    DB   0x81, "on", 0x96, "of ", 0 ; 0x9E
    DB   "n ", 0 ; 0x9F
    DB   0x84, "Gnom", 0x96, 0 ; 0xA0
    DB   "in", 0 ; 0xA1
    DB   0x83, " ", 0 ; 0xA2
    DB   0x92, "y", 0x8A, 0 ; 0xA3
    DB   "hief", 0x82, 0 ; 0xA4
    DB   "Cave", 0x89, 0 ; 0xA5
    DB   "Wat", 0x99, 0x89, 0 ; 0xA6

ovl_start_bg_strings:
    DB   "W", 0x98, "rior", 0x82, 0 ;  0
    DB   "Mage", 0x82, 0 ;  1
    DB   "K", 0xA1, "g", 0x82, 0 ;  2
    DB   0x90, 0x93, "d un", 0x87, 0xA2, 0 ;  3
    DB   0x90, "but ", 0x87, 0xA2, 0 ;  4
    DB   0x86, 0 ;  5
    DB   0x88, "first", 0xA2, 0 ;  6
    DB   0x84, "S", 0x99, "f", 0x82, 0 ;  7
    DB   0x84, "Yeo", 0x9A, 0 ;  8
    DB   0x84, "Towns", 0x9A, 0 ;  9
    DB   0x84, "Gu", 0x9B, "ds", 0x9A, 0 ; 10
    DB   0x84, "L", 0x93, "d", 0x9C, " Knight", 0x82, 0 ; 11
    DB   0x84, "Titl", 0x9C, " Noble", 0x82, 0 ; 12
    DB   0x84, "Royal Blood L", 0xA1, "e", 0x82, 0 ; 13
    DB   0x88, "black sheep of", 0x91, 0 ; 14
    DB   0x81, "a cr", 0x9C, "it to", 0x91, 0 ; 15
    DB   0x81, "a well lik", 0x9C, 0x83, 0x82, 0 ; 16
    DB   0x8C, 0x9D, 0x82, 0 ; 17
    DB   0x8D, 0x9D, 0x82, 0 ; 18
    DB   0x8C, 0xA3, 0x82, 0 ; 19
    DB   0x8D, 0xA3, 0x82, 0 ; 20
    DB   0x8C, 0x95, 0x82, 0 ; 21
    DB   0x8D, 0x95, 0x82, 0 ; 22
    DB   0x8E, 0 ; 23
    DB   0x84, 0x9D, " ", 0 ; 24
    DB   0x84, 0xA3, " ", 0 ; 25
    DB   0x84, 0x95, " ", 0 ; 26
    DB   "R", 0x93, "g", 0x8F, 0 ; 27
    DB   "Arch", 0x8F, 0 ; 28
    DB   "Pr", 0xA1, "ce", 0x82, 0 ; 29
    DB   0x86, 0x94, 0 ; 30
    DB   0x8E, 0x94, 0 ; 31
    DB   "Bum", 0x82, 0 ; 32
    DB   "Tav", 0x99, 0x9F, "Own", 0x8F, 0 ; 33
    DB   "M", 0x9B, "l", 0x8F, 0 ; 34
    DB   "Hom", 0x96, "Own", 0x8F, 0 ; 35
    DB   "Burgl", 0x98, 0x82, 0 ; 36
    DB   "Cl", 0x93, " Eld", 0x8F, 0 ; 37
    DB   0x86, 0xA0, 0 ; 38
    DB   0x8E, 0xA0, 0 ; 39
    DB   "Begg", 0x98, 0x82, 0 ; 40
    DB   "Bragg", 0x98, "t", 0x82, 0 ; 41
    DB   "Pr", 0x93, "kst", 0x8F, 0 ; 42
    DB   0x9E, "two", 0x83, "re", 0x9F, 0x97, 0 ; 43
    DB   0x8E, 0x97, 0 ; 44
    DB   "T", 0xA4, 0 ; 45
    DB   "Priso", 0x9F, "Gu", 0x98, "d", 0x82, 0 ; 46
    DB   "M", 0xA1, 0x8F, 0 ; 47
    DB   "Priest", 0x82, 0 ; 48
    DB   0x85, "mo", 0x8B, 0 ; 49
    DB   0x85, "fa", 0x8B, 0 ; 50
    DB   0x88, "adopt", 0x9C, 0xA2, 0 ; 51
    DB   0x8C, 0xA5, 0 ; 52
    DB   0x8D, 0xA5, 0 ; 53
    DB   0x8C, "H", 0x9B, "l", 0x89, 0 ; 54
    DB   0x8D, "H", 0x9B, "l", 0x89, 0 ; 55
    DB   0x8C, 0xA6, 0 ; 56
    DB   0x8D, 0xA6, 0 ; 57
    DB   "Cook", 0x82, 0 ; 58
    DB   "Sha", 0x9A, 0 ; 59
    DB   "Cl", 0x93, " C", 0xA4, 0 ; 60

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end

    SAVEBIN "ovl_start.ovl", ovl_start, ovl_end - ovl_start
