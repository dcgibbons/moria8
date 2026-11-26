; item_catalog.asm — Cold 'ITM2' ITEM.CAT 3-record LRU reader, canonical Huffman
; + non-recursive 0x80+ token decoder, and hot catalog lookup helpers.
;
; Resident core module included once by platforms/z80/cpm/main.asm.
; Uses pure 0xNN hex syntax for sjasmplus v1.24.0 (DEVICE NOSLOT64K).
; All public entry points preserve IX and IY.

    IFNDEF CORE_Z80_ITEM_CATALOG_ASM
    DEFINE CORE_Z80_ITEM_CATALOG_ASM 1

    INCLUDE "item_cat_layout_z80.inc"
    INCLUDE "item_cat_pinned_z80.inc"
    INCLUDE "item_ids_z80.inc"
    INCLUDE "item_hot_tables_z80.inc"

    EXPORT icat_init
    EXPORT icat_select_id
    EXPORT icat_select_logical
    EXPORT icat_get_cold_record
    EXPORT icat_get_cost
    EXPORT icat_get_weight
    EXPORT icat_get_dmg
    EXPORT icat_get_effects
    EXPORT icat_get_ego
    EXPORT icat_get_level_missile
    EXPORT icat_decode_item_name
    EXPORT icat_decode_paged_item_name
    EXPORT icat_decode_ego_name
    EXPORT icat_decode_flavour_name
    EXPORT item_paged_to_logical
    EXPORT item_logical_to_paged
    EXPORT item_get_category_a
    EXPORT item_get_color_a
    EXPORT item_get_unknown_idx_a
    EXPORT item_get_flavour_color_a
    EXPORT item_get_base_ac_a
    EXPORT item_get_display_char_a
    EXPORT item_stacks_a

; ============================================================
; icat_init — Reset 3-record ITEM.CAT LRU cache and selected record cache.
; Output: none
; Clobbers: AF, HL (preserves BC, DE, IX, IY)
; ============================================================
icat_init:
    LD   HL, 0xFFFF
    LD   (icat_lru_rec0), HL
    LD   (icat_lru_rec1), HL
    LD   (icat_lru_rec2), HL
    LD   (icat_cached_id), HL
    LD   A, 0
    LD   (icat_lru_age0), A
    INC  A
    LD   (icat_lru_age1), A
    INC  A
    LD   (icat_lru_age2), A
    RET

; ============================================================
; item_paged_to_logical — Convert paged (item_cur_page, A) to 0..360 in HL.
; Input:  A = slot_lo (0..254), (item_cur_page) & ITEM_PAGE_BIT
; Output: HL = logical_id (0..360)
; Preserves: BC, DE, IX, IY (clobbers AF)
; ============================================================
item_paged_to_logical:
    PUSH DE
    LD   L, A
    LD   H, 0
    LD   A, (item_cur_page)
    AND  ITEM_PAGE_BIT
    JR   Z, .p0
    LD   DE, ITEM_PAGE_SIZE
    ADD  HL, DE
.p0:
    POP  DE
    RET

; ============================================================
; item_logical_to_paged — Convert logical_id (HL = 0..360) to (item_cur_page, A).
; Input:  HL = logical_id (0..360)
; Output: A = slot_lo (0..254), (item_cur_page) = 0x00 or 0x40
; Preserves: BC, DE, HL, IX, IY
; ============================================================
item_logical_to_paged:
    PUSH HL
    PUSH DE
    LD   DE, ITEM_PAGE_SIZE
    OR   A
    SBC  HL, DE
    JR   NC, .page1
    POP  DE
    POP  HL
    XOR  A
    LD   (item_cur_page), A
    LD   A, L
    RET
.page1:
    LD   A, ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   A, L                   ; logical_id - 255 fits in 0..105
    POP  DE
    POP  HL
    RET

; ============================================================
; 3-Record ITEM.CAT LRU Reader
; ============================================================
; _icat_read_byte — Read byte at ITM2 offset HL (0..ITMCAT_TOTAL_SIZE-1).
; Input:  HL = byte offset in ITEM.CAT
; Output: A = byte (CF = 0 on OK; CF = 1, A = 0 on bounds/I/O error)
; Preserves: BC, DE, HL, IX, IY
_icat_read_byte:
    PUSH HL
    PUSH DE
    LD   DE, ITMCAT_TOTAL_SIZE
    OR   A
    SBC  HL, DE
    POP  DE
    POP  HL
    JR   NC, .oob

    PUSH BC
    PUSH DE
    PUSH HL
    ; rec_idx = HL >> 7 (0..58); D = 0, E = rec_idx
    LD   A, L
    RLCA
    LD   A, H
    RLA
    AND  0x7F
    LD   E, A
    LD   D, 0

    ; Check slot 0, 1, 2
    LD   HL, (icat_lru_rec0)
    OR   A
    SBC  HL, DE
    LD   A, 0
    JR   Z, .hit
    LD   HL, (icat_lru_rec1)
    OR   A
    SBC  HL, DE
    LD   A, 1
    JR   Z, .hit
    LD   HL, (icat_lru_rec2)
    OR   A
    SBC  HL, DE
    LD   A, 2
    JR   Z, .hit

    ; Cache miss: pick LRU slot S = age2 (oldest in [age0, age1, age2])
    LD   A, (icat_lru_age2)
    CP   3
    JR   C, .lru_valid
    LD   A, 2
.lru_valid:
    LD   B, A                   ; B = victim slot 0..2
    PUSH BC
    PUSH DE
    CALL _icat_slot_buf_hl      ; HL = buf ptr for slot A
    POP  DE                     ; DE = rel_rec
    PUSH DE
    PUSH HL
    LD   A, DAT_ID_ITEM_CAT
    CALL dat_read_slot_record   ; preserves IX, IY
    POP  HL
    POP  DE
    POP  BC                     ; B = slot 0..2
    JR   C, .io_err

    ; Record rec[B] = DE and promote B to MRU
    LD   A, B
    CALL _icat_store_rec
    LD   A, B
.hit:
    PUSH AF
    CALL _icat_promote_slot     ; A = slot 0..2 -> age0 = A
    POP  AF
    CALL _icat_slot_buf_hl      ; HL = buf base
    POP  DE                     ; DE = caller's original offset HL
    PUSH DE
    LD   A, E
    AND  0x7F
    LD   E, A
    LD   D, 0
    ADD  HL, DE
    LD   A, (HL)
    POP  HL
    POP  DE
    POP  BC
    OR   A                      ; CF = 0
    RET

.io_err:
    ; Mark victim slot empty so partial buffer isn't treated as valid
    LD   A, B
    LD   DE, 0xFFFF
    CALL _icat_store_rec
    POP  HL
    POP  DE
    POP  BC
.oob:
    XOR  A
    SCF
    RET

; A = slot (0..2) -> HL = icat_lru_buf0 + A * 128. Clobbers AF.
_icat_slot_buf_hl:
    OR   A
    LD   HL, icat_lru_buf0
    RET  Z
    CP   1
    LD   HL, icat_lru_buf1
    RET  Z
    LD   HL, icat_lru_buf2
    RET

; Store DE into icat_lru_rec[A]. Preserves BC, DE.
_icat_store_rec:
    OR   A
    JR   NZ, .not0
    LD   (icat_lru_rec0), DE
    RET
.not0:
    CP   1
    JR   NZ, .not1
    LD   (icat_lru_rec1), DE
    RET
.not1:
    LD   (icat_lru_rec2), DE
    RET

; Promote slot A (0..2) to front of 3-entry queue [age0, age1, age2].
; Clobbers AF, C.
_icat_promote_slot:
    LD   C, A
    LD   A, (icat_lru_age0)
    CP   C
    RET  Z                      ; already MRU
    LD   A, (icat_lru_age1)
    CP   C
    JR   NZ, .from_age2
    ; swap age0 <-> age1
    LD   A, (icat_lru_age0)
    LD   (icat_lru_age1), A
    LD   A, C
    LD   (icat_lru_age0), A
    RET
.from_age2:
    ; shift age2 <- age1 <- age0 <- C
    LD   A, (icat_lru_age1)
    LD   (icat_lru_age2), A
    LD   A, (icat_lru_age0)
    LD   (icat_lru_age1), A
    LD   A, C
    LD   (icat_lru_age0), A
    RET

; Read byte at HL and increment HL. Sets CF=1 on I/O error.
_icat_read_next_hl:
    CALL _icat_read_byte
    INC  HL
    RET

; Read 16-bit LE at HL into DE and advance HL by 2. Sets CF=1 on I/O error.
_icat_read_u16_hl:
    CALL _icat_read_next_hl
    RET  C
    LD   E, A
    CALL _icat_read_next_hl
    RET  C
    LD   D, A
    RET

; Read B bytes from offset HL into buffer DE. Sets CF=1 on I/O error.
_icat_read_block:
    CALL _icat_read_next_hl
    RET  C
    LD   (DE), A
    INC  DE
    DJNZ _icat_read_block
    RET

; ============================================================
; icat_select_id / icat_select_logical
; ============================================================
; icat_select_id: A = slot_lo (0..254), uses (item_cur_page).
; Output: icat_rec_0..3 loaded, HL = logical_id, CF = 0 OK / 1 err.
; Preserves: BC, DE, IX, IY
icat_select_id:
    CALL item_paged_to_logical
    ; fall through to icat_select_logical

; icat_select_logical: HL = logical_id (0..360).
; Output: icat_rec_0..3 loaded, HL preserved, CF = 0 OK / 1 err.
; Preserves: BC, DE, IX, IY
icat_select_logical:
    PUSH DE
    LD   DE, ITEM_TYPE_COUNT
    PUSH HL
    OR   A
    SBC  HL, DE
    POP  HL
    JR   NC, .bad_id

    LD   (icat_sel_id), HL
    LD   DE, (icat_cached_id)
    PUSH HL
    OR   A
    SBC  HL, DE
    POP  HL
    JR   NZ, .load_rec
    POP  DE
    OR   A                      ; CF = 0
    RET
.load_rec:
    PUSH BC
    PUSH HL
    ; offset = ITMCAT_OFF_RECORDS + HL * 4
    ADD  HL, HL
    ADD  HL, HL
    LD   DE, ITMCAT_OFF_RECORDS
    ADD  HL, DE
    LD   DE, icat_rec_0
    LD   B, ITMCAT_REC_SIZE
    CALL _icat_read_block
    POP  HL
    JR   C, .rec_fail
    LD   (icat_cached_id), HL
    POP  BC
    POP  DE
    OR   A
    RET
.rec_fail:
    LD   DE, 0xFFFF
    LD   (icat_cached_id), DE
    POP  BC
.bad_id:
    POP  DE
    SCF
    RET

; ============================================================
; Cold Record Field Accessors (all preserve IX, IY)
; ============================================================

; icat_get_cost — Load uint16 cost of currently selected item.
; Output: HL = cost (also stored in icat_cost_lo/hi), CF = 0 OK / 1 err
; Clobbers: AF, DE, HL (preserves BC, IX, IY)
icat_get_cost:
    LD   A, (icat_rec_0)
    AND  ITMCAT_REC_COST_MASK
    LD   L, A
    LD   H, 0
    ADD  HL, HL
    LD   DE, ITMCAT_OFF_COSTS
    ADD  HL, DE
    CALL _icat_read_u16_hl
    RET  C
    LD   (icat_cost_lo), DE
    EX   DE, HL
    OR   A
    RET

; Compute ITMCAT_OFF_WDS + (icat_rec_1 & ITMCAT_REC_WD_MASK) * 2 -> HL
_icat_wd_off_hl:
    LD   A, (icat_rec_1)
    AND  ITMCAT_REC_WD_MASK
    LD   L, A
    LD   H, 0
    ADD  HL, HL
    LD   DE, ITMCAT_OFF_WDS
    ADD  HL, DE
    RET

; icat_get_weight — Load uint16 weight (0.1 lb) of selected item.
; Output: HL = weight (also stored in icat_weight_lo/hi), CF = 0 OK / 1 err
; Clobbers: AF, DE, HL (preserves BC, IX, IY)
icat_get_weight:
    CALL _icat_wd_off_hl
    CALL _icat_read_byte        ; A = weight_idx
    RET  C
    LD   L, A
    LD   H, 0
    ADD  HL, HL
    LD   DE, ITMCAT_OFF_WEIGHTS
    ADD  HL, DE
    CALL _icat_read_u16_hl
    RET  C
    LD   (icat_weight_lo), DE
    EX   DE, HL
    OR   A
    RET

; icat_get_dmg — Load dice & sides of selected item.
; Output: D = dice, E = sides (also stored in icat_dmg_dice/sides), CF = 0/1
; Clobbers: AF, DE, HL (preserves BC, IX, IY)
icat_get_dmg:
    CALL _icat_wd_off_hl
    INC  HL
    CALL _icat_read_byte        ; A = dmg_idx
    RET  C
    LD   L, A
    LD   H, 0
    ADD  HL, HL
    LD   DE, ITMCAT_OFF_DMGS
    ADD  HL, DE
    CALL _icat_read_u16_hl
    RET  C
    LD   A, E                   ; byte 0 = dice
    LD   (icat_dmg_dice), A
    LD   A, D                   ; byte 1 = sides
    LD   (icat_dmg_sides), A
    LD   D, A
    LD   E, A
    LD   A, (icat_dmg_dice)
    LD   D, A                   ; D = dice, E = sides
    OR   A
    RET

; _icat_load_effect_a — Load 4 flag bytes & 5 bonus bytes for effect_idx A.
; Preserves: BC, IX, IY (clobbers AF, DE, HL)
_icat_load_effect_a:
    PUSH BC
    LD   L, A
    LD   H, 0
    ADD  HL, HL
    LD   DE, ITMCAT_OFF_EFFECTS
    ADD  HL, DE
    CALL _icat_read_u16_hl      ; E = flags_idx, D = bonus_idx
    JR   C, .err
    PUSH DE
    ; flags at ITMCAT_OFF_FLAGS + flags_idx * 4
    LD   L, E
    LD   H, 0
    ADD  HL, HL
    ADD  HL, HL
    LD   DE, ITMCAT_OFF_FLAGS
    ADD  HL, DE
    LD   DE, icat_flags_0
    LD   B, ITMCAT_FLAG_SIZE
    CALL _icat_read_block
    POP  DE
    JR   C, .err
    ; bonuses at ITMCAT_OFF_BONUSES + bonus_idx * 5
    LD   L, D
    LD   H, 0
    LD   E, L
    LD   D, H
    ADD  HL, HL
    ADD  HL, HL
    ADD  HL, DE                 ; * 5
    LD   DE, ITMCAT_OFF_BONUSES
    ADD  HL, DE
    LD   DE, icat_p1_lo
    LD   B, ITMCAT_BONUS_SIZE
    CALL _icat_read_block
    POP  BC
    RET
.err:
    POP  BC
    RET

; icat_get_effects — Load icat_flags_0..3 & icat_p1_lo/hi, tohit, todam, toac.
; Output: CF = 0 OK / 1 err
; Clobbers: AF, DE, HL (preserves BC, IX, IY)
icat_get_effects:
    LD   A, (icat_rec_2)
    JR   _icat_load_effect_a

; icat_get_ego — Load ego record for ego_id (0..EGO_COUNT).
; Input:  A = ego_id (0 or >= EGO_TYPE_COUNT -> zeros output fields)
; Output: icat_ego_cost_lo/hi, icat_flags_0..3, icat_p1..toac, CF = 0/1
; Clobbers: AF, DE, HL (preserves BC, IX, IY)
icat_get_ego:
    OR   A
    JR   Z, .zero_ego
    CP   EGO_TYPE_COUNT
    JR   NC, .zero_ego
    DEC  A                      ; 0..54
    LD   E, A
    ADD  A, A
    ADD  A, E                   ; * 3 (<= 162)
    LD   L, A
    LD   H, 0
    LD   DE, ITMCAT_OFF_EGOS
    ADD  HL, DE
    CALL _icat_read_next_hl     ; byte 0 = effect_idx
    RET  C
    PUSH AF
    CALL _icat_read_u16_hl      ; DE = cost_delta
    JR   C, .pop_err
    LD   (icat_ego_cost_lo), DE
    POP  AF
    JR   _icat_load_effect_a
.pop_err:
    POP  AF
    RET
.zero_ego:
    PUSH BC
    LD   HL, icat_flags_0
    LD   B, 11                  ; flags_0..3, p1_lo/hi, tohit, todam, toac, ego_cost_lo/hi
    XOR  A
.zloop:
    LD   (HL), A
    INC  HL
    DJNZ .zloop
    POP  BC
    OR   A
    RET

; icat_get_level_missile — Decode vms_level, missile_type, and depth_variant flag.
; Output: A = vms_level (0..63), B = missile_type (0, 1..3, 0x81..0x83),
;         CF = 1 if depth_variant
; Preserves: DE, HL, IX, IY
icat_get_level_missile:
    LD   A, (icat_rec_3)
    RLCA
    RLCA
    AND  0x03
    LD   B, A
    LD   A, (icat_rec_1)
    AND  ITMCAT_REC_AMMO_BIT
    OR   B
    LD   B, A                   ; B = missile_type
    LD   A, (icat_rec_0)
    RLA                         ; CF = ITMCAT_REC_DEPTH_BIT
    LD   A, (icat_rec_3)
    AND  ITMCAT_REC_LVL_MASK
    RET

; icat_get_cold_record — Select HL and populate all cold item fields.
; Input:  HL = logical_id (0..360)
; Output: DE = cost, BC = weight, H = dmg_dice, L = dmg_sides, A = vms_level,
;         CF = 0 OK / 1 err (also populates icat_cost/weight/dmg/flags/bonuses)
; Preserves: IX, IY
icat_get_cold_record:
    CALL icat_select_logical
    RET  C
    CALL icat_get_effects
    RET  C
    CALL icat_get_weight
    RET  C
    CALL icat_get_dmg
    RET  C
    CALL icat_get_cost
    RET  C
    CALL icat_get_level_missile
    LD   DE, (icat_cost_lo)
    LD   BC, (icat_weight_lo)
    LD   HL, (icat_dmg_dice)    ; L = icat_dmg_dice, H = icat_dmg_sides
    LD   A, H
    LD   H, L
    LD   L, A                   ; H = dice, L = sides
    LD   A, (icat_rec_3)
    AND  ITMCAT_REC_LVL_MASK
    OR   A                      ; CF = 0
    RET

; ============================================================
; Canonical Huffman + Non-Recursive 0x80+ Token String Decoder
; ============================================================
; Pinned metadata resides in ROM via item_cat_pinned_z80.inc:
;   icat_blk_index (89 x uint16 bitpos, stride 8)
;   icat_canon_counts (13 B, indices 1..12)
;   icat_canon_syms (176 B)

; _icat_seek_entry — Position stream cursor at string ID (icat_str_id).
; Clobbers: AF, BC, DE, HL
_icat_seek_entry:
    LD   HL, (icat_str_id)
    LD   A, L
    AND  0x07
    LD   (icat_skip_cnt), A
    ; blk = str_id >> 3 (0..88)
    SRL  H
    RR   L
    SRL  H
    RR   L
    SRL  H
    RR   L
    ADD  HL, HL                 ; * 2
    LD   DE, icat_blk_index
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)                ; DE = bp (bit offset from ITMCAT_OFF_STREAM)
    LD   A, E
    AND  0x07
    LD   B, A                   ; B = bit shift within byte (0..7)
    ; stream_byte_off = ITMCAT_OFF_STREAM + (bp >> 3)
    SRL  D
    RR   E
    SRL  D
    RR   E
    SRL  D
    RR   E
    LD   HL, ITMCAT_OFF_STREAM
    ADD  HL, DE
    CALL _icat_read_next_hl
    RET  C
    LD   (icat_stream_byte_off), HL
    ; Align initial byte by shift B; bits_left = 8 - B
    LD   C, A
    LD   A, 8
    SUB  B
    LD   (icat_bits_left), A
    LD   A, B
    OR   A
    JR   Z, .aligned
.align_loop:
    SLA  C
    DJNZ .align_loop
.aligned:
    LD   A, C
    LD   (icat_cur_byte), A
    ; Skip (str_id & 7) NUL-terminated entries
    LD   A, (icat_skip_cnt)
    OR   A
    RET  Z                      ; CF = 0
.skip_entry:
    PUSH AF
.skip_char:
    CALL _icat_read_sym
    JR   C, .skip_err
    OR   A
    JR   NZ, .skip_char
    POP  AF
    DEC  A
    JR   NZ, .skip_entry
    OR   A
    RET
.skip_err:
    POP  AF
    RET

; _icat_read_sym — Decode one canonical Huffman symbol from stream cursor.
; Output: A = symbol (0 = end, 1..0x7F = ASCII, 0x80+ = token), CF = 0/1 err
; Clobbers: AF, BC, DE, HL
_icat_read_sym:
    LD   DE, 0                  ; DE = code accumulator
    LD   C, 0                   ; C = sym_idx
    LD   B, 1                   ; B = bit length (1..12)
.bit_loop:
    LD   A, (icat_bits_left)
    OR   A
    JR   NZ, .have_bit
    LD   HL, (icat_stream_byte_off)
    CALL _icat_read_next_hl
    RET  C
    LD   (icat_stream_byte_off), HL
    LD   (icat_cur_byte), A
    LD   A, 8
.have_bit:
    DEC  A
    LD   (icat_bits_left), A
    LD   HL, icat_cur_byte
    SLA  (HL)
    RL   E
    RL   D                      ; code = (code << 1) | bit
    ; Lookup count = icat_canon_counts[B]
    LD   L, B
    LD   H, 0
    PUSH DE
    LD   DE, icat_canon_counts
    ADD  HL, DE
    POP  DE
    LD   A, (HL)                ; A = count
    LD   H, A                   ; H = count
    LD   A, D
    OR   A
    JR   NZ, .miss
    LD   A, E
    CP   H
    JR   NC, .miss
    ; Match: symbol = icat_canon_syms[sym_idx + E]
    ADD  A, C
    LD   L, A
    LD   H, 0
    LD   DE, icat_canon_syms
    ADD  HL, DE
    LD   A, (HL)
    OR   A                      ; CF = 0
    RET
.miss:
    ; code -= count; sym_idx += count
    LD   A, E
    SUB  H
    LD   E, A
    LD   A, D
    SBC  A, 0
    LD   D, A
    LD   A, C
    ADD  A, H
    LD   C, A
    INC  B
    LD   A, B
    CP   ITMCAT_CANON_MAX_LEN + 1
    JR   C, .bit_loop
    XOR  A
    SCF
    RET

; _icat_decode_entry — Decode (icat_str_id) into DE (max 47 chars + NUL).
; Input:  DE = dest buffer
; Output: HL = dest_buf, DE = NUL ptr, A = length, CF = 0 OK / 1 err
; Preserves: IX, IY
_icat_decode_entry:
    PUSH DE                     ; [orig_de]
    LD   (icat_dst_ptr), DE
    LD   A, ITEM_NAME_DECODE_BUF_SIZE - 1
    LD   (icat_dst_rem), A
    CALL _icat_seek_entry
    JR   C, .fail
.outer_loop:
    CALL _icat_read_sym
    JR   C, .fail
    OR   A
    JR   Z, .done
    BIT  7, A
    JR   NZ, .expand_tok
    CALL _icat_emit_char
    JR   .outer_loop
.expand_tok:
    ; Save 4-byte outer cursor (stream_byte_off, cur_byte, bits_left)
    LD   HL, (icat_stream_byte_off)
    LD   (icat_outer_byte_off), HL
    LD   HL, (icat_cur_byte)    ; L = cur_byte, H = bits_left
    LD   (icat_outer_byte), HL
    SUB  ITMCAT_TOK_MIN
    LD   L, A
    LD   H, 0
    LD   DE, ITMCAT_STR_BASE_TOK
    ADD  HL, DE
    LD   (icat_str_id), HL
    CALL _icat_seek_entry
    JR   C, .fail
.tok_loop:
    CALL _icat_read_sym
    JR   C, .fail
    OR   A
    JR   Z, .tok_done
    CALL _icat_emit_char
    JR   .tok_loop
.tok_done:
    LD   HL, (icat_outer_byte_off)
    LD   (icat_stream_byte_off), HL
    LD   HL, (icat_outer_byte)
    LD   (icat_cur_byte), HL
    JR   .outer_loop
.done:
    LD   HL, (icat_dst_ptr)
    XOR  A
    LD   (HL), A                ; NUL terminate
    EX   DE, HL                 ; DE = NUL ptr
    POP  HL                     ; HL = orig_de
    LD   A, E
    SUB  L                      ; A = written byte len (0..47)
    OR   A                      ; CF = 0
    RET
.fail:
    POP  DE
    XOR  A
    LD   (DE), A
    LD   H, D
    LD   L, E
    SCF
    RET

; Emit ASCII byte A if dst_rem > 0. Clobbers HL.
_icat_emit_char:
    LD   HL, icat_dst_rem
    LD   C, A
    LD   A, (HL)
    OR   A
    RET  Z
    DEC  (HL)
    LD   HL, (icat_dst_ptr)
    LD   (HL), C
    INC  HL
    LD   (icat_dst_ptr), HL
    RET

; icat_decode_item_name — Decode item name for logical_id HL (0..360) into DE.
; Preserves: IX, IY
icat_decode_item_name:
    PUSH DE
    LD   DE, ITEM_TYPE_COUNT
    PUSH HL
    OR   A
    SBC  HL, DE
    POP  HL
    POP  DE
    JR   NC, _icat_empty_fail
    LD   (icat_str_id), HL
    JP   _icat_decode_entry

; icat_decode_paged_item_name — Decode paged item slot_lo A (item_cur_page) into DE.
; Preserves: IX, IY
icat_decode_paged_item_name:
    CALL item_paged_to_logical
    JR   icat_decode_item_name

; icat_decode_ego_name — Decode ego A (1..EGO_COUNT) into DE.
; Out-of-range ego ID writes NUL and returns len=0 cleanly (CF=0 if 0, CF=1 if > EGO_COUNT).
; Preserves: IX, IY
icat_decode_ego_name:
    OR   A
    JR   Z, _icat_empty_ok
    CP   EGO_TYPE_COUNT
    JR   NC, _icat_empty_fail
    DEC  A
    LD   L, A
    LD   H, 0
    PUSH DE
    LD   DE, ITMCAT_STR_BASE_EGO
    ADD  HL, DE
    POP  DE
    LD   (icat_str_id), HL
    JP   _icat_decode_entry

; icat_decode_flavour_name — Decode flavour index A (0..FLAVOUR_COUNT-1) into DE.
; Preserves: IX, IY
icat_decode_flavour_name:
    CP   FLAVOUR_COUNT
    JR   NC, _icat_empty_fail
    LD   L, A
    LD   H, 0
    PUSH DE
    LD   DE, ITMCAT_STR_BASE_FLAV
    ADD  HL, DE
    POP  DE
    LD   (icat_str_id), HL
    JP   _icat_decode_entry

_icat_empty_ok:
    XOR  A
    LD   (DE), A
    LD   H, D
    LD   L, E
    OR   A
    RET

_icat_empty_fail:
    XOR  A
    LD   (DE), A
    LD   H, D
    LD   L, E
    SCF
    RET

; ============================================================
; Hot Resident Lookup Table Accessors (zero disk I/O)
; All preserve BC, DE, HL, IX, IY!
; ============================================================

; Read (item_cur_page, A) from 361-byte table HL -> A. Preserves BC, DE, HL.
_it_read_table_hl_a:
    PUSH BC
    PUSH HL
    CALL item_paged_to_logical  ; HL = logical_id
    POP  BC                     ; BC = table base
    ADD  HL, BC
    LD   A, (HL)
    LD   H, B
    LD   L, C
    POP  BC
    RET

; item_get_category_a — Input: A = slot_lo, (item_cur_page).
; Output: A = ICAT_*, Z reflects A == 0. Preserves BC, DE, HL, IX, IY.
item_get_category_a:
    PUSH HL
    LD   HL, it_category
    CALL _it_read_table_hl_a
    POP  HL
    OR   A
    RET

; item_get_color_a — Input: A = slot_lo, (item_cur_page).
; Output: A = COL_* (0..15). Preserves BC, DE, HL, IX, IY.
item_get_color_a:
    PUSH HL
    LD   HL, it_color_ac
    CALL _it_read_table_hl_a
    RRCA
    RRCA
    RRCA
    RRCA
    AND  0x0F
    POP  HL
    RET

; item_get_unknown_idx_a — Input: A = slot_lo, (item_cur_page).
; Output: A = class-local flavour index or 0xFF. Preserves BC, DE, HL, IX, IY.
item_get_unknown_idx_a:
    PUSH HL
    LD   HL, it_unknown_idx
    CALL _it_read_table_hl_a
    POP  HL
    RET

; item_get_flavour_color_a — Input: A = global flavour (0..FLAVOUR_COUNT-1).
; Output: A = COL_*. Preserves BC, DE, HL, IX, IY.
item_get_flavour_color_a:
    PUSH HL
    PUSH DE
    LD   E, A
    LD   D, 0
    LD   HL, flavour_colors
    ADD  HL, DE
    LD   A, (HL)
    POP  DE
    POP  HL
    RET

; item_get_base_ac_a — Input: A = slot_lo, (item_cur_page).
; Output: A = base AC (0..28). Preserves BC, DE, HL, IX, IY.
item_get_base_ac_a:
    PUSH BC
    PUSH DE
    PUSH HL
    LD   E, A                   ; E = slot_lo
    LD   HL, it_color_ac
    CALL _it_read_table_hl_a
    AND  0x0F
    CP   15
    JR   C, .ac_done
    LD   A, E
    CALL item_paged_to_logical  ; H = logical hi, L = logical lo
    EX   DE, HL                 ; D = logical hi, E = logical lo
    LD   HL, it_ac_extra_id_lo
    LD   B, IT_AC_EXTRA_COUNT
.ac_scan:
    LD   A, (HL)
    CP   E
    JR   NZ, .ac_next
    PUSH HL
    PUSH DE
    LD   DE, IT_AC_EXTRA_COUNT
    ADD  HL, DE                 ; -> it_ac_extra_id_hi[i]
    POP  DE
    LD   A, (HL)
    CP   D
    JR   NZ, .ac_pop_next
    PUSH DE
    LD   DE, IT_AC_EXTRA_COUNT
    ADD  HL, DE                 ; -> it_ac_extra_val[i]
    POP  DE
    LD   A, (HL)
    POP  HL
    JR   .ac_done
.ac_pop_next:
    POP  HL
.ac_next:
    INC  HL
    DJNZ .ac_scan
    LD   A, 15
.ac_done:
    POP  HL
    POP  DE
    POP  BC
    RET

; item_get_display_char_a — Pure ASCII map glyph for (item_cur_page, A).
; Output: A = ASCII char. Preserves BC, DE, HL, IX, IY.
item_get_display_char_a:
    PUSH HL
    PUSH DE
    LD   D, A
    LD   A, (item_cur_page)
    AND  ITEM_PAGE_BIT
    JR   NZ, .by_cat
    LD   A, D
    CP   ITEM_SLOT_SHORT_BOW
    JR   C, .not_ranged
    CP   ITEM_SLOT_IRON_SHOT + 1
    JR   NC, .not_ranged
    CP   ITEM_SLOT_ARROW
    LD   A, '}'
    JR   C, .done
    LD   A, '{'
    JR   .done
.not_ranged:
    CP   ITEM_SLOT_FLASK_OF_OIL
    JR   NZ, .by_cat
    LD   A, '!'
    JR   .done
.by_cat:
    LD   A, D
    CALL item_get_category_a
    LD   E, A
    LD   D, 0
    LD   HL, .cat_chars
    ADD  HL, DE
    LD   A, (HL)
.done:
    POP  DE
    POP  HL
    RET

.cat_chars:
    DB   0x5C, '$', '/', '[', ')', ']', ']', ']', '*', ',', '!', '?', '=', '?', '-', '/', '"', '&', 0x5C, '(', 0x5C

; item_stacks_a — Report whether paged item (item_cur_page, A) is stackable.
; Input:  A = slot_lo, (item_cur_page)
; Output: CF = 1 if stackable, CF = 0 otherwise. Preserves BC, DE, HL, IX, IY.
item_stacks_a:
    PUSH DE
    LD   D, A                   ; D = slot_lo
    CALL item_get_category_a
    CP   ICAT_FOOD
    JR   C, .chk_page0
    CP   ICAT_SCROLL + 1
    JR   C, .yes                ; food, potion, scroll
    CP   ICAT_SPIKE
    JR   Z, .yes
.chk_page0:
    LD   A, (item_cur_page)
    AND  ITEM_PAGE_BIT
    JR   NZ, .no
    LD   A, D
    CP   ITEM_SLOT_FLASK_OF_OIL
    JR   Z, .yes
    CP   ITEM_SLOT_WOODEN_TORCH
    JR   Z, .yes
    CP   ITEM_SLOT_ARROW
    JR   C, .no
    CP   ITEM_SLOT_IRON_SHOT + 1
    JR   C, .yes                ; arrow, bolt, rock, iron shot
.no:
    POP  DE
    OR   A                      ; CF = 0
    RET
.yes:
    POP  DE
    SCF                         ; CF = 1
    RET

    ENDIF
