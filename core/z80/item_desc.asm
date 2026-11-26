; item_desc.asm — Full ASCII item description formatter (inv, store/home, floor, staged).
;
; Matches core/6502/item_desc_banked.s + quantity prefix ("a /an /N "),
; tool ego prefixes (Orcish/Dwarven/Gnomish), known vs shuffled flavour names,
; identified ego suffixes, (+h,+d) / [base,+a] / (+p1) / (N charges) / (N turns),
; and " (magik)" pseudo-ID markers.
;
; Resident core module included once by platforms/z80/cpm/main.asm.
; Uses pure 0xNN hex syntax for sjasmplus v1.24.0 (DEVICE NOSLOT64K).
; All public entry points preserve IX and IY.

    IFNDEF CORE_Z80_ITEM_DESC_ASM
    DEFINE CORE_Z80_ITEM_DESC_ASM 1

    EXPORT item_format_inv_slot
    EXPORT item_format_store_slot
    EXPORT item_format_floor_slot
    EXPORT item_format_staged
    EXPORT item_get_floor_color_a

; ============================================================
; item_format_inv_slot — Format inventory/equipment slot A into DE.
; Input:  A = slot (0..TOTAL_INV_SLOTS-1), DE = dest buffer
; Output: HL = dest buffer start, DE = NUL ptr, B = byte len
; Preserves: IX, IY
; ============================================================
item_format_inv_slot:
    CP   TOTAL_INV_SLOTS
    JR   NC, _id_empty_out
    PUSH DE
    LD   C, A
    LD   B, 0
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, _id_pop_empty
    LD   DE, TOTAL_INV_SLOTS
    LD   (itemdesc_item_id), A
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_qty), A
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_p1), A
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_to_hit), A
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_to_dam), A
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_to_ac), A
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_flags), A
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_ego), A
    POP  DE
    XOR  A                      ; A = 0 (not floor-gold 16-bit qty)
    JP   _item_format_staged_internal

_id_pop_empty:
    POP  DE
_id_empty_out:
    XOR  A
    LD   (DE), A
    LD   H, D
    LD   L, E
    LD   B, 0
    RET

; ============================================================
; item_format_store_slot — Format absolute store/home slot A into DE.
; Input:  A = abs slot (0..STORE_TOTAL_SLOTS-1), DE = dest buffer
; Output: HL = dest buffer start, DE = NUL ptr, B = byte len
; Preserves: IX, IY
; ============================================================
item_format_store_slot:
    CP   STORE_TOTAL_SLOTS
    JR   NC, _id_empty_out
    PUSH DE
    LD   C, A
    LD   B, 0
    LD   HL, si_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, _id_pop_empty
    LD   DE, STORE_TOTAL_SLOTS
    LD   (itemdesc_item_id), A
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_qty), A
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_p1), A
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_to_hit), A
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_to_dam), A
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_to_ac), A
    ADD  HL, DE
    LD   A, (HL)
    AND  ITEM_META_FLAGS_MASK
    LD   (itemdesc_flags), A
    ADD  HL, DE
    LD   A, (HL)
    LD   (itemdesc_ego), A
    POP  DE
    XOR  A
    JR   _item_format_staged_internal

; ============================================================
; item_format_floor_slot — Format floor slot A into DE.
; Input:  A = floor slot (0..MAX_FLOOR_ITEMS-1), DE = dest buffer
; Output: HL = dest buffer start, DE = NUL ptr, B = byte len
; Preserves: IX, IY
; ============================================================
item_format_floor_slot:
    CP   MAX_FLOOR_ITEMS
    JR   NC, _id_empty_out
    PUSH DE
    LD   C, A
    LD   B, 0
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, _id_pop_empty
    LD   (itemdesc_item_id), A
    LD   DE, MAX_FLOOR_ITEMS
    ADD  HL, DE                 ; fi_x
    ADD  HL, DE                 ; fi_y
    ADD  HL, DE                 ; fi_qty
    LD   A, (HL)
    LD   (itemdesc_qty), A
    ADD  HL, DE                 ; fi_p1
    LD   A, (HL)
    LD   (itemdesc_p1), A
    XOR  A
    LD   (itemdesc_flags), A
    LD   HL, fi_meta_hi
    ADD  HL, BC
    LD   A, (HL)
    AND  ITEM_PAGE_BIT          ; Floor Look uses base/flavour name only (no ego/stats)
    LD   (itemdesc_ego), A
    POP  DE
    LD   A, 1                   ; flag floor-slot base-name + gold qty_16 support
    JR   _item_format_staged_internal

; ============================================================
; item_format_staged — Format item currently staged in itemdesc_* into DE.
; Input:  DE = dest buffer
; Output: HL = dest buffer start, DE = NUL ptr, B = byte len
; Preserves: IX, IY
; ============================================================
item_format_staged:
    LD   A, (itemdesc_item_id)
    CP   FI_EMPTY
    JP   Z, _id_empty_out
    XOR  A
_item_format_staged_internal:
    PUSH AF                     ; [is_floor]
    PUSH DE                     ; [orig_de]

    LD   A, (itemdesc_ego)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A

    LD   A, (itemdesc_item_id)
    CALL item_get_category_a    ; A = category
    LD   C, A                   ; C = category
    PUSH AF                     ; [category]

    ; 1. Decode base/flavour name (plus tool prefix if digging tool) into item_name_decode_buf
    CALL _id_decode_core_name   ; writes item_name_decode_buf, sets B=has_tool_prefix
    POP  AF
    LD   C, A                   ; C = category (B still = has_tool_prefix)

    ; Reconstruct start ptr -> dest DE
    POP  DE                     ; DE = orig_de
    POP  AF                     ; A = is_floor
    PUSH DE                     ; [orig_de]
    PUSH BC                     ; [B=has_tool_prefix, C=category]

    ; 2. Emit quantity prefix ("a ", "an ", or "<N> ")
    OR   A
    JR   Z, .not_floor_gold
    POP  BC
    SET  7, B                   ; bit 7 of B remembers is_floor across prefix/name copy
    PUSH BC
    LD   A, C
    CP   ICAT_GOLD
    JR   NZ, .not_floor_gold
    ; 16-bit gold amount = (itemdesc_p1 << 8) | itemdesc_qty
    LD   A, (itemdesc_qty)
    LD   L, A
    LD   A, (itemdesc_p1)
    LD   H, A
    CALL fmt_u16_dec            ; advances DE to NUL
    LD   A, ' '
    LD   (DE), A
    INC  DE
    JR   .append_name

.not_floor_gold:
    LD   A, (itemdesc_qty)
    CP   2
    JR   C, .append_name
.qty_num:
    CALL fmt_u8_dec             ; DE -> NUL
    LD   A, ' '
    LD   (DE), A
    INC  DE

.append_name:
    ; Copy item_name_decode_buf into DE
    LD   HL, item_name_decode_buf
    CALL _id_append_str

    POP  BC                     ; B = has_tool_prefix | (is_floor << 7), C = category
    BIT  7, B
    JP   NZ, .finish            ; floor Look stops after base/flavour name (6502 parity)
    PUSH BC

    ; 3. Ego suffix (if not tool prefix already emitted, ego != 0; unconditional per 6502 item_desc_banked.s)
    LD   A, B
    OR   A
    JR   NZ, .chk_stats
    LD   A, (itemdesc_ego)
    AND  EGO_ID_MASK
    JR   Z, .chk_stats
    CP   EGO_TYPE_COUNT
    JR   NC, .chk_stats
    LD   B, A                   ; B = ego_id
.show_ego:
    LD   A, B
    PUSH DE
    LD   DE, item_name_decode_buf
    CALL icat_decode_ego_name
    POP  DE
    JR   C, .chk_stats
    LD   HL, item_name_decode_buf
    CALL _id_append_str

.chk_stats:
    POP  BC                     ; C = category
    LD   A, C
    CP   ICAT_LIGHT
    JP   Z, .put_turns
    CP   ICAT_GOLD
    JP   Z, .chk_sensed
    LD   A, (itemdesc_flags)
    AND  IF_IDENTIFIED
    JP   Z, .chk_sensed

    LD   A, C
    CP   ICAT_WEAPON
    JR   Z, .put_weapon
    CP   ICAT_CLOAK
    JR   Z, .put_armor
    CP   ICAT_ARMOR
    JR   C, .not_armor
    CP   ICAT_BOOTS + 1
    JR   C, .put_armor
.not_armor:
    CP   ICAT_RING
    JR   Z, .put_ring
    CP   ICAT_AMULET
    JP   Z, .put_p1
    CP   ICAT_WAND
    JP   Z, .put_charges
    CP   ICAT_STAFF
    JP   Z, .put_charges
    JP   .chk_sensed

.put_weapon:
    LD   HL, itemdesc_to_hit
    LD   A, (itemdesc_to_dam)
    OR   (HL)
    JR   Z, .put_p1
.put_hit_dam:
    LD   A, ' '
    LD   (DE), A
    INC  DE
    LD   A, '('
    LD   (DE), A
    INC  DE
    LD   A, (itemdesc_to_hit)
    CALL _id_append_signed
    LD   A, ','
    LD   (DE), A
    INC  DE
    LD   A, (itemdesc_to_dam)
    CALL _id_append_signed
    LD   A, ')'
    LD   (DE), A
    INC  DE
    JR   .put_p1

.put_ring:
    LD   A, (item_cur_page)
    AND  ITEM_PAGE_BIT
    JP   Z, .chk_sensed
    LD   A, (itemdesc_to_ac)
    OR   A
    JR   NZ, .put_ring_ac
    LD   HL, itemdesc_to_hit
    LD   A, (itemdesc_to_dam)
    OR   (HL)
    JR   NZ, .put_hit_dam
    JR   .put_p1
.put_ring_ac:
    LD   A, ' '
    LD   (DE), A
    INC  DE
    LD   A, '['
    LD   (DE), A
    INC  DE
    LD   A, (itemdesc_to_ac)
    CALL _id_append_signed
    LD   A, ']'
    LD   (DE), A
    INC  DE
    JR   .put_p1

.put_armor:
    LD   A, ' '
    LD   (DE), A
    INC  DE
    LD   A, '['
    LD   (DE), A
    INC  DE
    LD   A, (itemdesc_item_id)
    CALL item_get_base_ac_a
    CALL fmt_u8_dec
    LD   A, ','
    LD   (DE), A
    INC  DE
    LD   A, (itemdesc_to_ac)
    CALL _id_append_signed
    LD   A, ']'
    LD   (DE), A
    INC  DE
.put_p1:
    LD   A, (itemdesc_p1)
    OR   A
    JR   Z, .chk_sensed
    LD   A, ' '
    LD   (DE), A
    INC  DE
    LD   A, '('
    LD   (DE), A
    INC  DE
    LD   A, (itemdesc_p1)
    CALL _id_append_signed
    LD   A, ')'
    LD   (DE), A
    INC  DE
    JR   .chk_sensed

.put_charges:
    LD   HL, _id_str_charges
    JR   .put_count_paren
.put_turns:
    LD   HL, _id_str_turns
.put_count_paren:
    PUSH HL
    LD   A, ' '
    LD   (DE), A
    INC  DE
    LD   A, '('
    LD   (DE), A
    INC  DE
    LD   A, (itemdesc_p1)
    CALL fmt_u8_dec
    LD   A, ' '
    LD   (DE), A
    INC  DE
    POP  HL
    CALL _id_append_str
    LD   A, ')'
    LD   (DE), A
    INC  DE

.chk_sensed:
    LD   A, (itemdesc_flags)
    AND  (IF_IDENTIFIED | IF_SENSED)
    CP   IF_SENSED
    JR   NZ, .finish
    LD   HL, _id_str_magik
    CALL _id_append_str

.finish:
    XOR  A
    LD   (DE), A
    POP  HL                     ; HL = orig_de
    LD   A, E
    SUB  L
    LD   B, A                   ; B = byte len
    RET

; Decode prefix + base/flavour name into item_name_decode_buf.
; Input: C = category, (item_cur_page) set. Output: B = 1 if tool prefix used, else 0.
_id_decode_core_name:
    LD   B, 0
    LD   A, C
    CP   ICAT_DIGGING
    JR   NZ, .not_tool
    LD   A, (item_cur_page)
    AND  ITEM_PAGE_BIT
    JR   NZ, .not_tool
    LD   A, (itemdesc_item_id)
    CP   ITEM_SLOT_PICK
    JR   Z, .chk_tool_ego
    CP   ITEM_SLOT_SHOVEL
    JR   NZ, .not_tool
.chk_tool_ego:
    LD   A, (itemdesc_ego)
    AND  EGO_ID_MASK
    JR   Z, .not_tool
    CP   3
    JR   NC, .not_tool
    ; Tool prefix idx = (id - PICK)*2 + (ego - 1) -> 0..3
    DEC  A
    LD   L, A
    LD   A, (itemdesc_item_id)
    SUB  ITEM_SLOT_PICK
    ADD  A, A
    ADD  A, L
    ADD  A, A                   ; * 2 for DW table
    LD   E, A
    LD   D, 0
    LD   HL, _id_tool_prefix_tbl
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    EX   DE, HL
    LD   DE, item_name_decode_buf
    CALL _id_append_str
    LD   A, (itemdesc_item_id)
    CALL icat_decode_paged_item_name
    LD   B, 1
    RET

.not_tool:
    ; Check catalog-wide id_known_bits (6502 item_get_name_ptr)
    LD   A, (itemdesc_item_id)
    CALL id_is_known
    JR   C, .decode_real
    LD   A, (itemdesc_item_id)
    LD   B, C                   ; B = category
    CALL _id_lookup_global_flavour
    JR   NC, .decode_real
    LD   DE, item_name_decode_buf
    CALL icat_decode_flavour_name
    LD   B, 0
    RET

.decode_real:
    LD   A, (itemdesc_item_id)
    LD   DE, item_name_decode_buf
    CALL icat_decode_paged_item_name
    LD   B, 0
    RET

; item_get_floor_color_a — Flavour-aware display color for (item_cur_page, A).
; Output: A = COL_* (0..15). Preserves BC, DE, HL, IX, IY.
item_get_floor_color_a:
    CALL id_is_known
    JP   C, item_get_color_a
    PUSH BC
    PUSH DE
    PUSH HL
    LD   C, A                   ; C = slot_lo
    CALL item_get_category_a
    LD   B, A                   ; B = category
    LD   A, C
    CALL _id_lookup_global_flavour
    JR   NC, .real_col
    POP  HL
    POP  DE
    POP  BC
    JP   item_get_flavour_color_a
.real_col:
    LD   A, C
    POP  HL
    POP  DE
    POP  BC
    JP   item_get_color_a

; _id_lookup_global_flavour — Check if (item_cur_page, A) with category B has a
; shuffled flavour. Output: CF=1 & A=global_flavour (0..173), else CF=0.
; Clobbers A, B, DE, HL. Preserves C.
_id_lookup_global_flavour:
    LD   D, A                   ; D = item_id
    LD   A, B
    CP   ICAT_POTION
    JR   C, .no_flav
    CP   ICAT_STAFF + 1
    JR   NC, .no_flav
    CP   ICAT_BOOK
    JR   Z, .no_flav
    SUB  ICAT_POTION
    LD   E, A
    LD   A, D
    PUSH DE
    LD   D, 0
    LD   HL, _id_flav_base_tbl
    ADD  HL, DE
    LD   B, (HL)                ; B = class base
    CALL item_get_unknown_idx_a
    POP  DE
    CP   0xFF
    JR   Z, .no_flav
    ADD  A, B                   ; A = global shuffle index (0..173)
    LD   E, A
    LD   D, 0
    LD   HL, potion_shuffle
    ADD  HL, DE
    LD   A, (HL)
    ADD  A, B
    SCF
    RET
.no_flav:
    OR   A
    RET

_id_append_str:
    LD   A, (HL)
    OR   A
    RET  Z
    LD   (DE), A
    INC  HL
    INC  DE
    JR   _id_append_str

_id_append_signed:
    BIT  7, A
    JR   Z, .pos
    NEG
    LD   C, '-'
    JR   .emit
.pos:
    LD   C, '+'
.emit:
    PUSH AF
    LD   A, C
    LD   (DE), A
    INC  DE
    POP  AF
    JP   fmt_u8_dec

_id_flav_base_tbl:
    DB   FLAVOUR_POTION_BASE, FLAVOUR_SCROLL_BASE, FLAVOUR_RING_BASE
    DB   0xFF, FLAVOUR_WAND_BASE, FLAVOUR_STAFF_BASE

_id_tool_prefix_tbl:
    DW   _id_tp_orcish, _id_tp_dwarven, _id_tp_gnomish, _id_tp_dwarven
_id_tp_orcish:  DB "Orcish ", 0
_id_tp_dwarven: DB "Dwarven ", 0
_id_tp_gnomish: DB "Gnomish ", 0
_id_str_charges: DB "charges", 0
_id_str_turns:   DB "turns", 0
_id_str_magik:   DB " (magik)", 0

    ENDIF
