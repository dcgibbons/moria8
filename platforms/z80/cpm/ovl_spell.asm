; ovl_spell.asm — Moria8 CP/M Mage Spell & Priest Prayer UI, Learning & Mana Overlay
; (OVL_SPELL = 8, DAT slot 7)
;
; Fixed vector jump table at OVL_WINDOW_BASE (0x5600):
;   +0:  JP ovl_spell_cast            ('m' command)
;   +3:  JP ovl_spell_pray            ('p' command)
;   +6:  JP ovl_spell_gain            ('f' command)
;   +9:  JP ovl_spell_recalc_levelup  (TRN-008 levelup_magic_pending)
;
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax, DEVICE NOSLOT64K).
; All public entry vectors preserve IX and IY.
; No live state is kept in overlay-local RAM across any tramp_* call.

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "item_ids_z80.inc"
    DEFINE HUFF_CONSTS_ONLY 1
    INCLUDE "huff_ascii.inc"
    UNDEFINE HUFF_CONSTS_ONLY
    INCLUDE "main_exp.inc"

    ORG  OVL_WINDOW_BASE        ; 0x5600

ovl_start:
    JP   ovl_spell_cast
    JP   ovl_spell_pray
    JP   ovl_spell_gain
    JP   ovl_spell_recalc_levelup

; ============================================================================
; +0: ovl_spell_cast ('m') / +3: ovl_spell_pray ('p')
; Output: CF = 1 if turn consumed (cast or fizzled / overcast faint), CF = 0 cancelled
; ============================================================================
ovl_spell_cast:
    PUSH IX
    PUSH IY
    LD   A, SPELL_MAGE
    JR   ovl_spell_cast_common

ovl_spell_pray:
    PUSH IX
    PUSH IY
    LD   A, SPELL_PRIEST

ovl_spell_cast_common:
    LD   (pm_spell_type), A
    XOR  A
    LD   (pm_mode), A               ; 0 = cast/pray mode

    ; Check class spell type matches command
    LD   A, (player_data + PL_SPELL_TYPE)
    LD   HL, pm_spell_type
    CP   (HL)
    JR   Z, .type_ok
    LD   A, (pm_spell_type)
    CP   SPELL_MAGE
    LD   A, HSTR_PM_NO_CAST
    JR   Z, .no_msg
    LD   A, HSTR_PM_NO_PRAY
.no_msg:
    CALL msg_print_huff
    OR   A
    POP  IY
    POP  IX
    RET

.type_ok:
    ; Check minimum spell level for class
    CALL ovl_spell_get_class_meta ; B=min_lvl, C=total, A=table_idx (0..4)
    LD   A, (abi_player_lvl)
    CP   B
    JR   NC, .lvl_min_ok
    LD   A, HSTR_PM_NO_EXP
    JR   .no_msg

.lvl_min_ok:
    ; Select matching spell/prayer book from inventory (no blind/confuse pre-gate on 6502)
    CALL ovl_spell_pick_book    ; CF=1 -> pm_book_idx, pm_book_slot set
    JR   C, .have_book
    OR   A
    POP  IY
    POP  IX
    RET

.have_book:
    ; Build list of known spells in selected book -> pm_spell_list / pm_spell_count
    LD   A, 0                   ; mode 0 = cast/pray (learnt only)
    CALL ovl_spell_build_list
    LD   A, (pm_spell_count)
    OR   A
    JR   NZ, .have_spells
    LD   A, HSTR_PM_NOT_KNOWN
    CALL msg_print_huff
    OR   A
    POP  IY
    POP  IX
    RET

.have_spells:
    ; Prompt user for spell index (0..pm_spell_count-1) with '?' modal list support
    CALL ovl_spell_choose_from_list ; CF=1 -> A=list_idx (modal restored if opened)
    JR   C, .chosen
    OR   A
    POP  IY
    POP  IX
    RET

.chosen:
    ; Resolve pm_spell_list[A] -> spell_idx (C)
    LD   E, A
    LD   D, 0
    LD   HL, pm_spell_list
    ADD  HL, DE
    LD   C, (HL)                ; C = spell_idx (0..30)
    LD   A, C
    LD   (pm_spell_idx), A

    ; Fetch level, mana -> B=lvl, D=mana
    CALL ovl_spell_get_entry    ; Input C=spell_idx -> B=lvl, D=mana, A=fail_base, E=exp_q
    LD   A, (abi_player_lvl)
    CP   B
    JR   NC, .can_lvl
    LD   A, HSTR_PM_NO_EXP
    CALL msg_print_huff
    OR   A
    POP  IY
    POP  IX
    RET

.can_lvl:
    ; Save D=mana, C=spell_idx on CPU stack across fail/execute
    PUSH BC                     ; SP+2: C=spell_idx
    PUSH DE                     ; SP+0: D=mana

    LD   A, C
    CALL ovl_spell_calc_fail    ; A = fail% (5..95)
    LD   B, A
    LD   A, 100
    CALL rng_range              ; A = 0..99
    CP   B
    JR   NC, .cast_success

    ; Spell failed! (6502 uses HSTR_PM_FAIL for both mage and priest)
    LD   A, HSTR_PM_FAIL
    CALL msg_print_huff
    POP  DE                     ; D = mana
    POP  BC
    LD   A, D
    CALL ovl_spell_consume_mana
    SCF                         ; Failed cast consumes turn
    POP  IY
    POP  IX
    RET

.cast_success:
    ; Execute spell effect via OVL_SPELL_EFF (tramp_spell_eff_execute).
    ; 6502 parity: even if target/item prompt aborted, mana + worked + turn still spend.
    CALL tramp_spell_eff_execute
    POP  DE                     ; D = mana
    POP  BC                     ; C = spell_idx

    ; Mark PL_SPELLS_WORKED bit (zero first-cast XP on 6502)
    PUSH DE
    LD   A, C
    LD   HL, player_data + PL_SPELLS_WORKED_0
    CALL ovl_spell_set_bit
    POP  DE

    LD   A, D
    CALL ovl_spell_consume_mana
    SCF
    POP  IY
    POP  IX
    RET

; ============================================================================
; +6: ovl_spell_gain ('G' / 'f') — Learn new spell/prayer when PL_NEW_SPELLS > 0
; Output: CF = 1 if learned (turn consumed), CF = 0 otherwise
; ============================================================================
ovl_spell_gain:
    PUSH IX
    PUSH IY

    LD   A, (player_data + PL_SPELL_TYPE)
    OR   A
    JR   NZ, .has_magic
    LD   A, HSTR_IGS_NO_MAGIC
    CALL msg_print_huff
    OR   A
    POP  IY
    POP  IX
    RET

.has_magic:
    LD   (pm_spell_type), A
    LD   A, 1
    LD   (pm_mode), A               ; 1 = study mode

    LD   A, (player_data + PL_NEW_SPELLS)
    OR   A
    JR   NZ, .has_slots
    LD   A, HSTR_IGS_NO_NEW
    CALL msg_print_huff
    OR   A
    POP  IY
    POP  IX
    RET

.has_slots:
    CALL ovl_spell_pick_book
    JR   C, .g_have_book
    OR   A
    POP  IY
    POP  IX
    RET

.g_have_book:
    ; Build learnable list (!learnt && spell_lvl <= abi_player_lvl)
    LD   A, 1                   ; mode 1 = learnable only
    CALL ovl_spell_build_list
    LD   A, (pm_spell_count)
    OR   A
    JR   NZ, .g_avail
    LD   A, HSTR_IGS_NO_NEW
    CALL msg_print_huff
    OR   A
    POP  IY
    POP  IX
    RET

.g_avail:
    LD   A, (pm_spell_type)
    CP   SPELL_MAGE
    JR   NZ, .g_priest_rand

    ; Mage/Rogue/Ranger opens "Study" modal immediately and picks on single key (6502 player_gain_spell_impl.s)
    CALL ovl_spell_show_modal   ; restores screen and returns key in A
    CP   KEY_ESC
    JR   Z, .g_cancel
    CP   KEY_SPACE
    JR   Z, .g_cancel
    CP   0x03
    JR   Z, .g_cancel
    CALL ovl_spell_pick_letter
    JR   C, .g_picked
.g_cancel:
    OR   A
    POP  IY
    POP  IX
    RET

.g_priest_rand:
    ; Priest/Paladin gets random learnable prayer from selected book
    LD   A, (pm_spell_count)
    CALL rng_range              ; A = 0..count-1

.g_picked:
    LD   E, A
    LD   D, 0
    LD   HL, pm_spell_list
    ADD  HL, DE
    LD   C, (HL)                ; C = chosen spell_idx (0..30)
    LD   A, C
    LD   (pm_spell_idx), A

    ; Set learnt bit, clear forgotten bit
    PUSH BC
    LD   A, C
    LD   HL, player_data + PL_SPELLS_LEARNT_0
    CALL ovl_spell_set_bit
    POP  BC
    PUSH BC
    LD   A, C
    LD   HL, player_data + PL_SPELLS_FORGOTTEN_0
    CALL ovl_spell_clr_bit
    POP  BC

    ; Deduplicate then append spell_idx C at first 99 in PL_SPELL_ORDER[0..31]
    LD   HL, player_data + PL_SPELL_ORDER
    LD   B, 32
.ord_lp:
    LD   A, (HL)
    CP   C
    JR   Z, .ord_done
    CP   99
    JR   Z, .ord_put
    INC  HL
    DJNZ .ord_lp
    JR   .ord_done
.ord_put:
    LD   (HL), C
.ord_done:
    LD   HL, player_data + PL_NEW_SPELLS
    LD   A, (HL)
    OR   A
    JR   Z, .g_msg
    DEC  (HL)
.g_msg:
    LD   A, HSTR_IGS_SUCCESS
    CALL msg_print_huff

    SCF
    POP  IY
    POP  IX
    RET

; ============================================================================
; +9: ovl_spell_recalc_levelup — TRN-008 recalc PL_MAX_MANA, PL_MANA, PL_NEW_SPELLS
; Called when levelup_magic_pending != 0 (and safe for any stat/level recalc).
; ============================================================================
ovl_spell_recalc_levelup:
    PUSH IX
    PUSH IY

    XOR  A
    LD   (levelup_magic_pending), A

    LD   A, (player_data + PL_SPELL_TYPE)
    OR   A
    JR   NZ, .r_magic
.r_zero_all:
    XOR  A
    LD   (player_data + PL_MAX_MANA), A
    LD   (player_data + PL_MANA), A
    LD   (player_data + PL_NEW_SPELLS), A
    LD   (abi_player_mp), A
    LD   (abi_player_mmp), A
    CALL status_mark_dirty
    POP  IY
    POP  IX
    RET

.r_magic:
    LD   (pm_spell_type), A
    XOR  A
    LD   (pm_mode), A
    CALL ovl_spell_get_class_meta ; B = min_lvl, C = spell_total
    LD   A, (abi_player_lvl)
    CP   B
    JR   C, .r_zero_all
    SUB  B
    INC  A                      ; D = levels = abi_player_lvl - min_lvl + 1
    LD   D, A

    PUSH BC
    PUSH DE
    CALL ovl_spell_get_stat_adj ; E = stat_adj (0..7)
    LD   A, E
    POP  DE
    POP  BC                     ; B=min_lvl, C=total, D=levels, A=stat_adj
    LD   E, A

    ; --- 1. Max Mana = (levels * halves) / 2 + 1 (0 if stat_adj == 0), clamped 255 ---
    OR   A
    JR   NZ, .calc_mp
    XOR  A
    JR   .store_mmp
.calc_mp:
    PUSH BC
    PUSH DE
    LD   HL, ovl_spell_mrm_halves
    LD   B, 0
    LD   C, E
    ADD  HL, BC
    LD   A, (HL)                ; halves
    LD   L, D
    LD   H, 0
    CALL mul_hl_a               ; HL = levels * halves
    SRL  H
    RR   L                      ; HL /= 2
    INC  HL                     ; + 1
    LD   A, H
    OR   A
    JR   Z, .mp_fits
    LD   L, 255
.mp_fits:
    LD   A, L
    POP  DE
    POP  BC
.store_mmp:
    LD   (player_data + PL_MAX_MANA), A
    LD   (abi_player_mmp), A
    LD   HL, player_data + PL_MANA
    CP   (HL)
    JR   NC, .mp_sync
    LD   (HL), A                ; clamp current MP <= max MP
.mp_sync:
    LD   A, (HL)
    LD   (abi_player_mp), A

    ; --- 2. Allowed spells = levels * mult[stat_adj], capped at spell_total (C) ---
    ; stat_adj in E: 0->0, 1..3->1x, 4..5->3/2x, 6->2x, 7->5/2x
    LD   A, E
    OR   A
    JR   NZ, .chk_adj_13
    XOR  A
    JR   .cap_allowed
.chk_adj_13:
    CP   4
    JR   NC, .chk_adj_45
    LD   A, D
    JR   .cap_allowed
.chk_adj_45:
    CP   6
    JR   NC, .chk_adj_6
    ; (levels * 3) >> 1
    LD   L, D
    LD   H, 0
    ADD  HL, HL
    LD   E, D
    LD   D, 0
    ADD  HL, DE
    SRL  H
    RR   L
    LD   A, L
    JR   .cap_allowed
.chk_adj_6:
    JR   NZ, .adj_7
    LD   A, D
    ADD  A, A
    JR   NC, .cap_allowed
    LD   A, 255
    JR   .cap_allowed
.adj_7:
    ; (levels * 5) >> 1
    LD   L, D
    LD   H, 0
    ADD  HL, HL
    ADD  HL, HL
    LD   E, D
    LD   D, 0
    ADD  HL, DE
    SRL  H
    RR   L
    LD   A, H
    OR   A
    JR   Z, .cap_7
    LD   L, 255
.cap_7:
    LD   A, L
.cap_allowed:
    CP   C
    JR   C, .allowed_ok
    LD   A, C
.allowed_ok:
    LD   D, A                   ; D = allowed (0..31)

    ; --- 3. Count known spells; compute rem = max(0, allowed - known) (no forgetting on 6502) ---
    CALL ovl_spell_count_learnt ; E = known_count
    LD   A, D
    SUB  E
    JR   NC, .rem_ok
    XOR  A
.rem_ok:
    ; Cap rem by number of currently unlearnt spells <= player_lvl
    LD   D, A                   ; D = rem
    CALL ovl_spell_count_avail  ; E = avail count
    LD   A, D
    CP   E
    JR   C, .set_new
    LD   A, E
.set_new:
    LD   (player_data + PL_NEW_SPELLS), A

.recalc_done:
    CALL status_mark_dirty
    POP  IY
    POP  IX
    RET

; ============================================================================
; Internal Helpers (no IX/IY mutation)
; ============================================================================

; Pick spellbook or prayerbook via tramp_item_mgt_select_inv
; Sets pm_book_idx (0..7) and pm_book_slot, CF=1 on pick; CF=0 cancel
ovl_spell_pick_book:
    LD   A, (pm_mode)
    OR   A
    LD   B, HSTR_IGS_PROMPT
    JR   NZ, .book_filter
    LD   A, (pm_spell_type)
    CP   SPELL_MAGE
    LD   B, HSTR_PM_YOU_CAST
    JR   Z, .book_filter
    LD   B, HSTR_PM_YOU_PRAY
.book_filter:
    LD   A, (pm_spell_type)
    CP   SPELL_MAGE
    LD   A, PIW_FILTER_MAGE_BOOK
    JR   Z, .call_sel
    LD   A, PIW_FILTER_PRAYER_BOOK
.call_sel:
    LD   HL, 0                  ; resolve prompt directly from HSTR in B
    CALL tramp_item_mgt_select_inv
    RET  NC                     ; Cancelled or none carried

    ; Map inv slot A -> book_idx 0..7
    LD   (pm_book_slot), A
    LD   E, A
    LD   D, 0
    LD   HL, inv_ego
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    JR   NZ, .bad_book          ; All 8 books live on page 0

    LD   HL, inv_item_id
    ADD  HL, DE
    LD   A, (HL)
    SUB  ITEM_SLOT_SPELLBOOK_BEGINNERS_MAGICK
    CP   BOOK_COUNT
    JR   NC, .bad_book
    LD   (pm_book_idx), A
    SCF
    RET
.bad_book:
    LD   A, HSTR_IGS_WRONG_TYPE
    CALL msg_print_huff
    OR   A
    RET

; Build pm_spell_list for book (pm_book_idx), mode A (0=cast, 1=gain, 2=browse)
ovl_spell_build_list:
    LD   (bss_scratch + 0), A   ; build mode
    XOR  A
    LD   (pm_spell_count), A

    LD   A, (pm_book_idx)
    ADD  A, A
    ADD  A, A                   ; book_idx * 4
    LD   E, A
    LD   D, 0
    LD   HL, ovl_spell_book_masks
    ADD  HL, DE                 ; HL -> 4-byte bitmask for this book
    ; Copy 4-byte mask into bss_scratch + 1..4
    LD   DE, bss_scratch + 1
    LD   BC, 4
    LDIR

    LD   C, 0                   ; C = spell_idx 0..30
.loop:
    LD   A, C
    LD   HL, bss_scratch + 1
    CALL ovl_spell_test_bit
    JR   Z, .next

    ; Check class spell level != 99
    PUSH BC
    CALL ovl_spell_get_entry    ; B=lvl, D=mana, A=fail_base, E=exp_q
    LD   A, B
    POP  BC
    CP   99
    JR   NZ, .check_mode
    ; Only include lvl==99 in mode 2 (browse) so player sees whole book
    LD   A, (bss_scratch + 0)
    CP   2
    JR   NZ, .next
    JR   .append

.check_mode:
    LD   A, (bss_scratch + 0)
    OR   A
    JR   NZ, .not_cast_m
    ; Mode 0 (cast): must be learnt
    PUSH BC
    LD   A, C
    LD   HL, player_data + PL_SPELLS_LEARNT_0
    CALL ovl_spell_test_bit
    POP  BC
    JR   Z, .next
    JR   .append

.not_cast_m:
    CP   1
    JR   NZ, .append            ; Mode 2 = all in book
    ; Mode 1 (gain): must NOT be learnt and lvl <= abi_player_lvl
    PUSH BC
    LD   A, C
    LD   HL, player_data + PL_SPELLS_LEARNT_0
    CALL ovl_spell_test_bit
    POP  BC
    JR   NZ, .next
    PUSH BC
    CALL ovl_spell_get_entry    ; B = spell_lvl
    LD   A, (abi_player_lvl)
    CP   B
    POP  BC
    JR   C, .next

.append:
    LD   A, (pm_spell_count)
    CP   16
    JR   NC, .next
    LD   E, A
    LD   D, 0
    LD   HL, pm_spell_list
    ADD  HL, DE
    LD   (HL), C
    INC  A
    LD   (pm_spell_count), A

.next:
    INC  C
    LD   A, C
    CP   SPELL_CATALOG_COUNT
    JR   C, .loop
    RET

; Prompt for spell from pm_spell_list (cast/pray mode 0)
; Output: CF=1 -> A=list_idx (0..count-1); CF=0 cancel
ovl_spell_choose_from_list:
.prompt_line:
    LD   A, (pm_spell_type)
    CP   SPELL_MAGE
    LD   A, HSTR_PM_FOOTER_CAST
    JR   Z, .dec_hdr
    LD   A, HSTR_PM_FOOTER_PRAY
.dec_hdr:
    LD   DE, line_buf
    CALL huff_decode_string     ; "Cast which? (a-p, ESC)" / "Pray which? (a-p, ESC)"
    LD   HL, line_buf
.patch_lp:
    LD   A, (HL)
    OR   A
    JR   Z, .show_pr
    CP   '-'
    JR   NZ, .patch_nx
    INC  HL
    LD   A, (pm_spell_count)
    ADD  A, 'a' - 1
    LD   (HL), A
    JR   .show_pr
.patch_nx:
    INC  HL
    JR   .patch_lp
.show_pr:
    CALL msg_clear
    LD   B, MSG_ROW0
    CALL screen_clear_row
    LD   B, MSG_ROW0
    LD   C, 0
    LD   E, COL_PROMPT
    LD   HL, line_buf
    CALL screen_put_str
    CALL screen_flush

    CALL input_get_key
    CP   '?'
    JR   NZ, .direct_key
    CALL ovl_spell_show_modal   ; restores screen and returns key in A
    CP   KEY_ESC
    JR   Z, .cancel
    CP   KEY_SPACE
    JR   Z, .cancel
    CP   0x03
    JR   Z, .cancel
    CALL ovl_spell_pick_letter
    JR   NC, .prompt_line       ; 6502: invalid key from '?' modal re-prompts
    JR   .picked

.direct_key:
    CP   KEY_ESC
    JR   Z, .cancel
    CP   KEY_SPACE
    JR   Z, .cancel
    CP   0x03
    JR   Z, .cancel
    CALL ovl_spell_pick_letter
    JR   NC, .cancel            ; 6502: invalid direct key -> Never mind.

.picked:
    PUSH AF
    CALL msg_clear
    CALL screen_flush
    POP  AF
    SCF
    RET

.cancel:
    LD   A, HSTR_PIW_NEVERMIND
    CALL msg_print_huff
    OR   A
    RET

; Convert key A ('a'..'a'+pm_spell_count-1, case-insensitive) -> CF=1, A=idx; CF=0 invalid
ovl_spell_pick_letter:
    CP   'A'
    JR   C, .not_up
    CP   'Z' + 1
    JR   NC, .not_up
    OR   0x20
.not_up:
    SUB  'a'
    JR   C, .bad
    LD   HL, pm_spell_count
    CP   (HL)
    RET  C
.bad:
    OR   A
    RET

; Full-screen modal spell/prayer list ("Mage Book", "Prayer Book", "Study")
; Reads pm_mode (0=cast/pray, 1=study) & pm_spell_type. Restores dungeon screen & returns key in A.
ovl_spell_show_modal:
    CALL screen_hard_clear

    ; Title at row 0, col 14, COL_WHITE
    LD   A, (pm_mode)
    OR   A
    LD   HL, ovl_spell_str_t_study
    JR   NZ, .put_title
    LD   A, (pm_spell_type)
    CP   SPELL_MAGE
    LD   HL, ovl_spell_str_t_mage
    JR   Z, .put_title
    LD   HL, ovl_spell_str_t_pray
.put_title:
    LD   B, 0
    LD   C, 14
    LD   E, COL_WHITE
    CALL screen_put_str

    ; Column header at row 1, col 1, COL_LGREY
    LD   B, 1
    LD   C, 1
    LD   E, COL_LGREY
    LD   HL, ovl_spell_str_hdr
    CALL screen_put_str

    ; Rows 2..2+count-1 (Name, Mana, Lvl; dim OOM COL_DGREY)
    XOR  A                      ; list index i = 0..pm_spell_count-1
.row_lp:
    LD   HL, pm_spell_count
    CP   (HL)
    JP   NC, .rows_done

    LD   (bss_scratch + 1), A   ; list index i
    LD   E, A
    LD   D, 0
    LD   HL, pm_spell_list
    ADD  HL, DE
    LD   C, (HL)                ; C = spell_idx (0..30)

    ADD  A, 2
    LD   B, A                   ; row = 2 + i
    LD   A, C
    LD   (bss_scratch + 2), A   ; spell_idx
    LD   A, B
    LD   (bss_scratch + 3), A   ; screen row

    CALL ovl_spell_get_entry    ; B=lvl, D=mana
    LD   A, B
    LD   (bss_scratch + 4), A   ; lvl
    LD   A, D
    LD   (bss_scratch + 5), A   ; mana

    ; Color: COL_DGREY if mana > PL_MANA, else COL_LGREY (player_magic_select_overlay.s)
    LD   A, (player_data + PL_MANA)
    CP   D
    LD   E, COL_LGREY
    JR   NC, .row_col_ok
    LD   E, COL_DGREY
.row_col_ok:
    LD   A, E
    LD   (bss_scratch + 6), A

    ; Print "x) " at col 1
    LD   A, (bss_scratch + 1)
    ADD  A, 'a'
    LD   (line_buf), A
    LD   A, ')'
    LD   (line_buf + 1), A
    LD   A, ' '
    LD   (line_buf + 2), A
    XOR  A
    LD   (line_buf + 3), A
    LD   A, (bss_scratch + 3)
    LD   B, A
    LD   C, 1
    LD   HL, line_buf
    CALL screen_put_str

    ; Print spell name at col 4
    LD   A, (bss_scratch + 2)
    CALL ovl_spell_get_name_ptr
    LD   A, (bss_scratch + 3)
    LD   B, A
    LD   C, 4
    LD   A, (bss_scratch + 6)
    LD   E, A
    CALL screen_put_str

    ; Mana at col 30 (RJ2)
    LD   A, (bss_scratch + 5)
    LD   D, A
    LD   A, (bss_scratch + 3)
    LD   B, A
    LD   C, 30
    LD   A, (bss_scratch + 6)
    LD   E, A
    LD   A, D
    CALL ovl_spell_put_rj2

    ; Level at col 35 (RJ2)
    LD   A, (bss_scratch + 4)
    LD   D, A
    LD   A, (bss_scratch + 3)
    LD   B, A
    LD   C, 35
    LD   A, (bss_scratch + 6)
    LD   E, A
    LD   A, D
    CALL ovl_spell_put_rj2

    LD   A, (bss_scratch + 1)
    INC  A
    JP   .row_lp

.rows_done:
    ; Footer at row 23 (SCREEN_ROWS-1), col 5, COL_WHITE
    LD   A, (pm_mode)
    OR   A
    LD   HL, ovl_spell_str_p_learn
    JR   NZ, .ftr_cp
    LD   A, (pm_spell_type)
    CP   SPELL_MAGE
    LD   HL, ovl_spell_str_p_cast
    JR   Z, .ftr_cp
    LD   HL, ovl_spell_str_p_pray
.ftr_cp:
    LD   DE, line_buf
    CALL ovl_spell_strcpy
    LD   A, (pm_spell_count)
    ADD  A, 'a' - 1
    LD   (DE), A
    INC  DE
    LD   HL, ovl_spell_str_p_tail
    CALL ovl_spell_strcpy
    LD   B, SCREEN_ROWS - 1
    LD   C, 5
    LD   E, COL_WHITE
    LD   HL, line_buf
    CALL screen_put_str
    CALL screen_flush

    CALL input_get_key
    PUSH AF
    CALL screen_hard_clear
    CALL status_mark_dirty
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    CALL game_loop_redraw_fresh
    POP  AF
    RET

ovl_spell_put_rj2:
    PUSH BC
    PUSH DE
    LD   B, 0
.t10:
    CP   10
    JR   C, .t1
    SUB  10
    INC  B
    JR   .t10
.t1:
    ADD  A, '0'
    LD   (temp_str_buf + 1), A
    LD   A, B
    OR   A
    LD   A, ' '
    JR   Z, .sp
    LD   A, B
    ADD  A, '0'
.sp:
    LD   (temp_str_buf), A
    XOR  A
    LD   (temp_str_buf + 2), A
    POP  DE
    POP  BC
    LD   HL, temp_str_buf
    JP   screen_put_str

; Consume A = mana_cost; handles VMS overcast faint + 1/3 CON drain (TRN-013)
ovl_spell_consume_mana:
    OR   A
    RET  Z
    LD   B, A                   ; B = mana cost
    LD   A, (player_data + PL_MANA)
    CP   B
    JR   C, .overcast
    SUB  B
    LD   (player_data + PL_MANA), A
    LD   (abi_player_mp), A
    CALL status_mark_dirty
    RET

.overcast:
    ; diff = cost - current_mp
    LD   C, A
    LD   A, B
    SUB  C
    LD   B, A                   ; B = diff (1..255)
    XOR  A
    LD   (player_data + PL_MANA), A
    LD   (abi_player_mp), A

    ; Print faint message (preserve B = diff across msg_print_huff!)
    PUSH BC
    LD   A, (pm_spell_type)
    CP   SPELL_MAGE
    LD   A, HSTR_PM_FAINT_EFFORT
    JR   Z, .faint_msg
    LD   A, HSTR_PM_NO_MANA      ; "You faint from fatigue!"
.faint_msg:
    CALL msg_print_huff
    POP  BC                     ; B = diff (1..255)

    ; zp_eff_paralyze = rng_range(5 * diff) + 1 (6502 overwrites, does not add)
    LD   L, B
    LD   H, 0
    ADD  HL, HL
    ADD  HL, HL
    LD   E, B
    LD   D, 0
    ADD  HL, DE                 ; HL = 5 * diff
    LD   A, H
    OR   A
    JR   Z, .r5_ok
    LD   L, 255
.r5_ok:
    LD   A, L
    CALL rng_range
    INC  A
    LD   (zp_eff_paralyze), A

    ; 1/3 chance CON damage check (SUST_CON -> HSTR_CHEST_UNAFFECTED; else player_drain_stat_a)
    LD   A, 3
    CALL rng_range
    RRCA
    JR   NC, .oc_more
    LD   A, HSTR_PM_HEALTH_DAMAGED
    CALL msg_print_huff
    LD   A, (player_sust_mask)
    AND  SUST_CON
    JR   Z, .oc_drain
    LD   A, HSTR_CHEST_UNAFFECTED
    CALL msg_print_huff
    JR   .oc_more
.oc_drain:
    LD   A, STAT_CON
    CALL player_drain_stat_a
.oc_more:
    CALL msg_show_more
    CALL input_get_key
    CALL msg_clear
    CALL status_mark_dirty
    JP   status_draw

; Return class magic metadata for (player_data + PL_CLASS)
; Output: A = table_idx (0=Mage, 1=Priest, 2=Rogue, 3=Ranger, 4=Paladin)
;         B = min_level, C = spell_total
ovl_spell_get_class_meta:
    LD   A, (player_data + PL_CLASS)
    OR   A
    JR   Z, .def
    CP   6
    JR   C, .valid
.def:
    LD   A, 1
.valid:
    DEC  A                      ; 0..4
    PUSH AF
    LD   E, A
    LD   D, 0
    LD   HL, ovl_spell_min_lvl_tbl
    ADD  HL, DE
    LD   B, (HL)
    LD   HL, ovl_spell_total_tbl
    ADD  HL, DE
    LD   C, (HL)
    POP  AF
    RET

; Return stat_adj (0..7) in E from INT (Mage) or WIS (Priest)
ovl_spell_get_stat_adj:
    LD   A, (pm_spell_type)
    CP   SPELL_MAGE
    LD   A, (player_data + PL_INT_CUR)
    JR   Z, .scan
    LD   A, (player_data + PL_WIS_CUR)
.scan:
    LD   HL, ovl_spell_stat_thresh
    LD   E, 0
    LD   B, 7
.lp:
    CP   (HL)
    RET  C
    INC  E
    INC  HL
    DJNZ .lp
    RET

; Fetch spell entry for current PL_CLASS and spell_idx C (0..30)
; Output: B = lvl, C = spell_idx (preserved), D = mana, A = base_fail, E = exp_q
ovl_spell_get_entry:
    PUSH BC
    CALL ovl_spell_get_class_meta ; A = 0..4
    POP  BC                     ; C = spell_idx
    ADD  A, A                   ; * 2
    LD   E, A
    LD   D, 0
    LD   HL, ovl_spell_class_ptrs
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)                ; DE = base of 4*31 tables for class
    LD   L, C
    LD   H, 0
    ADD  HL, DE                 ; HL -> lvl[idx]
    LD   B, (HL)                ; B = lvl
    LD   DE, 31
    ADD  HL, DE
    PUSH BC                     ; save C = spell_idx
    LD   C, (HL)                ; C = mana
    ADD  HL, DE
    LD   A, (HL)                ; A = base_fail
    ADD  HL, DE
    LD   E, (HL)                ; E = exp_q
    LD   D, C                   ; D = mana
    POP  HL                     ; L = spell_idx
    LD   C, L                   ; restore C = spell_idx
    RET

; Calc adjusted fail% [5..95] for spell_idx A
ovl_spell_calc_fail:
    LD   C, A
    CALL ovl_spell_get_entry    ; B=lvl, D=mana, A=base_fail
    PUSH BC                     ; B=lvl
    PUSH DE                     ; D=mana
    LD   L, A
    LD   H, 0                   ; HL = base_fail (signed 16)

    ; -= 3 * max(0, abi_player_lvl - spell_lvl) (6502 player_magic_display.s)
    LD   A, (abi_player_lvl)
    SUB  B
    JR   NC, .lvl_diff_ok
    XOR  A
.lvl_diff_ok:
    LD   E, A
    LD   D, 0                   ; DE = max(0, lvl - spell_lvl)
    ; HL -= 3 * DE; intermediate underflow clamps directly to 5 (6502 player_magic_display.s:37-41)
    OR   A
    SBC  HL, DE
    JR   C, .clamp_min
    OR   A
    SBC  HL, DE
    JR   C, .clamp_min
    OR   A
    SBC  HL, DE
    JR   C, .clamp_min

    ; -= 3 * (stat_adj - 1)
    PUSH HL
    CALL ovl_spell_get_stat_adj ; E = 0..7
    POP  HL
    LD   A, E
    DEC  A                      ; -1..6
    LD   E, A
    RLA
    SBC  A, A
    LD   D, A
    OR   A
    SBC  HL, DE
    OR   A
    SBC  HL, DE
    OR   A
    SBC  HL, DE

    ; Unsigned underflow (< 0 -> 5, 0..4 kept, >= 96 -> 95) matching 6502 player_magic_display.s:60-76
    BIT  7, H
    JR   NZ, .clamp_min
    LD   A, H
    OR   A
    JR   NZ, .clamp_max
    LD   A, L
    JR   .chk_hi
.clamp_min:
    LD   A, 5
    JR   .add_oc
.chk_hi:
    CP   96
    JR   C, .add_oc
.clamp_max:
    LD   A, 95

.add_oc:
    POP  DE                     ; D = mana
    POP  BC
    LD   B, A                   ; B = clamped fail
    LD   A, (player_data + PL_MANA)
    CP   D
    LD   A, B
    RET  NC                     ; enough mana -> done
    ; + 5 * (mana - cur_mp)
    LD   C, A                   ; C = base clamped fail
    LD   A, (player_data + PL_MANA)
    LD   B, A
    LD   A, D
    SUB  B                      ; missing = mana - cur_mp
    LD   L, A
    LD   H, 0
    ADD  HL, HL
    ADD  HL, HL
    LD   E, A
    LD   D, 0
    ADD  HL, DE                 ; 5 * missing
    LD   E, C
    ADD  HL, DE                 ; total fail
    LD   A, H
    OR   A
    JR   NZ, .oc_max
    LD   A, L
    CP   96
    RET  C
.oc_max:
    LD   A, 95
    RET

; Count bits in PL_SPELLS_LEARNT_0..3 -> E
ovl_spell_count_learnt:
    LD   E, 0
    LD   C, 0
.lp:
    LD   A, C
    LD   HL, player_data + PL_SPELLS_LEARNT_0
    CALL ovl_spell_test_bit
    JR   Z, .nxt
    INC  E
.nxt:
    INC  C
    LD   A, C
    CP   SPELL_CATALOG_COUNT
    JR   C, .lp
    RET

; Count learnable spells (lvl <= abi_player_lvl && !learnt) -> E
ovl_spell_count_avail:
    LD   E, 0
    LD   C, 0
.lp:
    PUSH DE
    PUSH BC
    CALL ovl_spell_get_entry    ; B = lvl
    LD   A, (abi_player_lvl)
    CP   B
    POP  BC
    POP  DE
    JR   C, .nxt                ; lvl too high (also excludes 99)
    PUSH DE
    LD   A, C
    LD   HL, player_data + PL_SPELLS_LEARNT_0
    CALL ovl_spell_test_bit
    POP  DE
    JR   NZ, .nxt
    INC  E
.nxt:
    INC  C
    LD   A, C
    CP   SPELL_CATALOG_COUNT
    JR   C, .lp
    RET

; Test/Set/Clear bit A (0..31) in 4-byte bitmap at HL
; Preserves C, DE
ovl_spell_bit_addr:
    PUSH AF
    RRCA
    RRCA
    RRCA
    AND  0x03
    PUSH DE
    LD   E, A
    LD   D, 0
    ADD  HL, DE
    POP  DE
    POP  AF
    AND  0x07
    LD   B, A
    INC  B
    LD   A, 0x80
.rot:
    RLCA
    DJNZ .rot
    RET

ovl_spell_test_bit:
    CALL ovl_spell_bit_addr
    AND  (HL)
    RET

ovl_spell_set_bit:
    CALL ovl_spell_bit_addr
    OR   (HL)
    LD   (HL), A
    RET

ovl_spell_clr_bit:
    CALL ovl_spell_bit_addr
    CPL
    AND  (HL)
    LD   (HL), A
    RET

; Get spell/prayer name pointer in HL for spell_idx A (0..30), using pm_spell_type (preserves DE)
ovl_spell_get_name_ptr:
    PUSH DE
    ADD  A, A
    LD   E, A
    LD   D, 0
    LD   A, (pm_spell_type)
    CP   SPELL_MAGE
    LD   HL, ovl_spell_mage_names
    JR   Z, .idx
    LD   HL, ovl_spell_priest_names
.idx:
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    EX   DE, HL
    POP  DE
    RET

ovl_spell_strcpy:
    LD   A, (HL)
    OR   A
    JR   Z, .done
    LD   (DE), A
    INC  HL
    INC  DE
    JR   ovl_spell_strcpy
.done:
    LD   (DE), A
    RET

; ============================================================================
; Authoritative Tables & Names (core/6502/spell_class_data.s, spell_data.s, spell_names.s)
; ============================================================================
ovl_spell_min_lvl_tbl:  DB 1, 1, 5, 3, 1
ovl_spell_total_tbl:    DB 31, 31, 12, 30, 31
ovl_spell_stat_thresh:  DB 8, 15, 18, 68, 88, 108, 118
ovl_spell_mrm_halves:   DB 0, 2, 2, 3, 4, 5, 6, 8

ovl_spell_book_masks:
    DB 0x7F, 0x00, 0x00, 0x00   ; Book 0 (#186 Beginners-Magick): 0..6
    DB 0x80, 0xFF, 0x00, 0x00   ; Book 1 (#187 Magick I): 7..15
    DB 0x00, 0x00, 0xFF, 0x00   ; Book 2 (#188 Magick II): 16..23
    DB 0x00, 0x00, 0x00, 0x7F   ; Book 3 (#189 Guide to Power): 24..30
    DB 0xFF, 0x00, 0x00, 0x00   ; Book 4 (#190 Beginners Handbook): 0..7
    DB 0x00, 0xFF, 0x00, 0x00   ; Book 5 (#191 Words of Wisdom): 8..15
    DB 0x00, 0x00, 0xFF, 0x01   ; Book 6 (#192 Chants & Blessings): 16..24
    DB 0x00, 0x00, 0x00, 0x7E   ; Book 7 (#193 Exorcisms): 25..30

ovl_spell_class_ptrs:
    DW ovl_spell_tbl_mage
    DW ovl_spell_tbl_priest
    DW ovl_spell_tbl_rogue
    DW ovl_spell_tbl_ranger
    DW ovl_spell_tbl_paladin

; Mage (lvl[31], mana[31], fail[31], exp_q[31])
ovl_spell_tbl_mage:
    DB 1,1,1,1,3,3,3,3,5,5,5,5,7,7,7,9,9,9,9,11,11,13,15,17,19,21,23,25,29,33,37
    DB 1,1,2,2,3,3,3,4,4,5,5,5,6,6,6,7,7,7,7,7,7,7,9,9,12,12,12,12,18,21,25
    DB 22,23,24,26,25,25,27,30,30,30,30,35,35,50,40,44,45,75,45,45,99,50,50,50,55,90,60,65,65,80,95
    DB 1,1,1,1,2,1,2,1,6,8,5,6,9,10,12,19,19,22,19,25,19,22,25,31,38,44,50,63,88,125,200

; Priest (lvl[31], mana[31], fail[31], exp_q[31])
ovl_spell_tbl_priest:
    DB 1,1,1,1,3,3,3,3,5,5,5,5,7,7,7,7,9,9,9,11,11,11,13,13,15,15,17,21,25,33,39
    DB 1,2,2,2,2,3,3,3,4,4,4,5,5,5,6,7,6,7,7,8,8,9,10,11,12,14,14,16,20,24,32
    DB 10,15,20,25,25,27,27,28,29,30,32,34,36,38,38,38,38,38,40,42,42,55,45,45,50,50,55,60,70,90,80
    DB 1,1,1,1,1,2,2,3,4,5,5,5,6,7,9,9,10,10,10,10,12,15,15,16,20,22,32,38,75,125,200

; Rogue (lvl[31], mana[31], fail[31], exp_q[31])
ovl_spell_tbl_rogue:
    DB 99,5,7,9,11,13,99,15,99,17,19,21,99,23,99,99,25,27,99,99,29,99,99,99,99,99,99,99,99,99,99
    DB 99,1,2,3,4,5,99,6,99,7,8,9,99,10,99,99,12,15,99,99,18,99,99,99,99,99,99,99,99,99,99
    DB 0,50,55,60,65,70,0,75,0,80,85,90,0,95,0,0,95,99,0,0,99,0,0,0,0,0,0,0,0,0,0
    DB 0,1,1,2,2,3,0,3,0,4,5,6,0,7,0,0,9,11,0,0,19,0,0,0,0,0,0,0,0,0,0

; Ranger (lvl[31], mana[31], fail[31], exp_q[31])
ovl_spell_tbl_ranger:
    DB 3,3,3,5,5,5,7,7,9,9,11,11,13,13,15,15,17,17,21,21,23,23,25,25,27,29,31,33,35,37,99
    DB 1,2,2,3,3,4,5,6,7,8,8,9,10,11,12,13,17,17,17,19,25,20,20,21,21,23,25,25,25,30,99
    DB 30,35,35,35,40,45,40,40,40,45,40,45,45,55,50,50,55,90,55,60,95,60,60,65,65,95,70,75,80,95,0
    DB 1,2,2,2,2,3,6,5,7,8,10,10,12,13,15,15,15,17,17,18,20,20,20,20,22,23,25,38,50,100,0

; Paladin (lvl[31], mana[31], fail[31], exp_q[31])
ovl_spell_tbl_paladin:
    DB 1,2,3,5,5,7,7,9,9,9,11,11,11,13,13,15,15,17,17,19,19,21,23,25,27,29,31,33,35,37,39
    DB 1,2,3,3,4,5,5,7,7,8,9,10,10,10,11,13,15,15,15,15,15,17,17,20,21,22,24,28,32,36,38
    DB 30,35,35,35,35,40,40,40,40,40,40,45,45,45,45,45,50,50,50,50,50,50,50,50,50,50,60,60,70,90,90
    DB 1,2,3,5,5,6,6,7,8,8,10,10,10,12,13,15,15,17,18,19,19,20,20,20,22,24,25,31,38,50,100

; Spell & Prayer Names (62 total, sharing identical strings)
ovl_spell_mage_names:
    DW ovl_spell_nm_m0, ovl_spell_nm_m1, ovl_spell_nm_m2, ovl_spell_nm_m3
    DW ovl_spell_nm_m4, ovl_spell_nm_m5, ovl_spell_nm_m6, ovl_spell_nm_m7
    DW ovl_spell_nm_m8, ovl_spell_nm_m9, ovl_spell_nm_m10, ovl_spell_nm_m11
    DW ovl_spell_nm_m12, ovl_spell_nm_m13, ovl_spell_nm_m14, ovl_spell_nm_m15
    DW ovl_spell_nm_m16, ovl_spell_nm_m17, ovl_spell_nm_m18, ovl_spell_nm_m19
    DW ovl_spell_nm_m20, ovl_spell_nm_m21, ovl_spell_nm_m22, ovl_spell_nm_m23
    DW ovl_spell_nm_m24, ovl_spell_nm_m25, ovl_spell_nm_m26, ovl_spell_nm_m27
    DW ovl_spell_nm_m28, ovl_spell_nm_m29, ovl_spell_nm_m30

ovl_spell_priest_names:
    DW ovl_spell_nm_p0, ovl_spell_nm_m4, ovl_spell_nm_p2, ovl_spell_nm_p3
    DW ovl_spell_nm_p4, ovl_spell_nm_p5, ovl_spell_nm_p6, ovl_spell_nm_p7
    DW ovl_spell_nm_p8, ovl_spell_nm_p9, ovl_spell_nm_p10, ovl_spell_nm_p11
    DW ovl_spell_nm_p12, ovl_spell_nm_m16, ovl_spell_nm_m13, ovl_spell_nm_p15
    DW ovl_spell_nm_p16, ovl_spell_nm_p17, ovl_spell_nm_p18, ovl_spell_nm_p19
    DW ovl_spell_nm_p20, ovl_spell_nm_p21, ovl_spell_nm_p22, ovl_spell_nm_p23
    DW ovl_spell_nm_p24, ovl_spell_nm_p25, ovl_spell_nm_p26, ovl_spell_nm_p27
    DW ovl_spell_nm_p28, ovl_spell_nm_p29, ovl_spell_nm_p30

ovl_spell_nm_m0:  DB "Magic Missile", 0
ovl_spell_nm_m1:  DB "Detect Monsters", 0
ovl_spell_nm_m2:  DB "Phase Door", 0
ovl_spell_nm_m3:  DB "Light Area", 0
ovl_spell_nm_m4:  DB "Cure Light Wounds", 0
ovl_spell_nm_m5:  DB "Find Hidden Traps/Doors", 0
ovl_spell_nm_m6:  DB "Stinking Cloud", 0
ovl_spell_nm_m7:  DB "Confusion", 0
ovl_spell_nm_m8:  DB "Lightning Bolt", 0
ovl_spell_nm_m9:  DB "Trap/Door Destruction", 0
ovl_spell_nm_m10: DB "Sleep I", 0
ovl_spell_nm_m11: DB "Cure Poison", 0
ovl_spell_nm_m12: DB "Teleport Self", 0
ovl_spell_nm_m13: DB "Remove Curse", 0
ovl_spell_nm_m14: DB "Frost Bolt", 0
ovl_spell_nm_m15: DB "Turn Stone to Mud", 0
ovl_spell_nm_m16: DB "Create Food", 0
ovl_spell_nm_m17: DB "Recharge Item I", 0
ovl_spell_nm_m18: DB "Sleep II", 0
ovl_spell_nm_m19: DB "Polymorph Other", 0
ovl_spell_nm_m20: DB "Identify", 0
ovl_spell_nm_m21: DB "Sleep III", 0
ovl_spell_nm_m22: DB "Fire Bolt", 0
ovl_spell_nm_m23: DB "Slow Monster", 0
ovl_spell_nm_m24: DB "Frost Ball", 0
ovl_spell_nm_m25: DB "Recharge Item II", 0
ovl_spell_nm_m26: DB "Teleport Other", 0
ovl_spell_nm_m27: DB "Haste Self", 0
ovl_spell_nm_m28: DB "Fire Ball", 0
ovl_spell_nm_m29: DB "Word of Destruction", 0
ovl_spell_nm_m30: DB "Genocide", 0

ovl_spell_nm_p0:  DB "Detect Evil", 0
ovl_spell_nm_p2:  DB "Bless", 0
ovl_spell_nm_p3:  DB "Remove Fear", 0
ovl_spell_nm_p4:  DB "Call Light", 0
ovl_spell_nm_p5:  DB "Find Traps", 0
ovl_spell_nm_p6:  DB "Detect Doors/Stairs", 0
ovl_spell_nm_p7:  DB "Slow Poison", 0
ovl_spell_nm_p8:  DB "Blind Creature", 0
ovl_spell_nm_p9:  DB "Portal", 0
ovl_spell_nm_p10: DB "Cure Medium Wounds", 0
ovl_spell_nm_p11: DB "Chant", 0
ovl_spell_nm_p12: DB "Sanctuary", 0
ovl_spell_nm_p15: DB "Resist Heat and Cold", 0
ovl_spell_nm_p16: DB "Neutralize Poison", 0
ovl_spell_nm_p17: DB "Orb of Draining", 0
ovl_spell_nm_p18: DB "Cure Serious Wounds", 0
ovl_spell_nm_p19: DB "Sense Invisible", 0
ovl_spell_nm_p20: DB "Protection from Evil", 0
ovl_spell_nm_p21: DB "Earthquake", 0
ovl_spell_nm_p22: DB "Sense Surroundings", 0
ovl_spell_nm_p23: DB "Cure Critical Wounds", 0
ovl_spell_nm_p24: DB "Turn Undead", 0
ovl_spell_nm_p25: DB "Prayer", 0
ovl_spell_nm_p26: DB "Dispel Undead", 0
ovl_spell_nm_p27: DB "Heal", 0
ovl_spell_nm_p28: DB "Dispel Evil", 0
ovl_spell_nm_p29: DB "Glyph of Warding", 0
ovl_spell_nm_p30: DB "Holy Word", 0

ovl_spell_str_t_mage:   DB "Mage Book", 0
ovl_spell_str_t_pray:   DB "Prayer Book", 0
ovl_spell_str_t_study:  DB "Study", 0
ovl_spell_str_hdr:      DB "   Name                      Mana Lvl", 0
ovl_spell_str_p_cast:   DB "Cast which? (a-", 0
ovl_spell_str_p_pray:   DB "Pray which? (a-", 0
ovl_spell_str_p_learn:  DB "Learn which? (a-", 0
ovl_spell_str_p_tail:   DB ", esc)", 0

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end

    SAVEBIN "ovl_spell.ovl", ovl_start, ovl_end - ovl_start
