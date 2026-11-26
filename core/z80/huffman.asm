; huffman.asm — Page-tail packed RO tables and 2-record LRU Huffman string decoder.
;
; Requires huff_ascii.inc to support HUFF_NO_INDEX / HUFF_NO_TREE split guards
; so monster_idx_z80 and sgr_lut pack cleanly into the 256-byte huff_tree_page
; tail (+0x78..+0xFC) between huff_tree_right (+0x40..+0x77) and huff_str_index.
;
; Included once by resident main.asm.

    IFNDEF CORE_Z80_HUFFMAN_ASM
    DEFINE CORE_Z80_HUFFMAN_ASM 1

; ============================================================
; Page-Tail Packed RO Data Block (256-byte aligned, <= 256 B)
;
;   +0x00..0x3F ( 64 B): huff_tree_left (56 nodes + 8 B pad)
;   +0x40..0x77 ( 56 B): huff_tree_right
;   +0x78..0xEC (117 B): monster_idx_z80 (cat_level_raw, cat_level_playable, cat_undead)
;   +0xED..0xFC ( 16 B): sgr_lut (logical color 0..15 -> ANSI SGR fg 30..37 / 90..97)
;   +0xFD..0xFF (  3 B): page slack
; ============================================================
    ALIGN 256
huff_tree_page:
    DEFINE HUFF_NO_INDEX 1
    INCLUDE "huff_ascii.inc"
    UNDEFINE HUFF_NO_INDEX
    EXPORT huff_tree_left
    EXPORT huff_tree_right

    INCLUDE "monster_idx_z80.inc"
    EXPORT cat_level_raw
    EXPORT cat_level_playable
    EXPORT cat_undead

    ; Logical Moria8/C64 palette 0..15 -> ANSI SGR foreground parameter (1 byte each)
    EXPORT sgr_lut
sgr_lut:
    DB 30, 97, 31, 96, 35, 32, 34, 93
    DB 33, 33, 91, 90, 37, 92, 94, 37

    ASSERT (huff_tree_page & 0xFF) == 0
    ASSERT huff_tree_left == huff_tree_page + 0x00
    ASSERT huff_tree_right == huff_tree_page + 0x40
    ASSERT cat_level_raw == huff_tree_page + 0x78
    ASSERT sgr_lut == huff_tree_page + 0xED
    ASSERT ($ - huff_tree_page) <= 256

    ; 496-byte string byte-offset index into huff_stream.bin (DAT_ID_HUFF_STREAM)
    DEFINE HUFF_NO_TREE 1
    INCLUDE "huff_ascii.inc"
    UNDEFINE HUFF_NO_TREE
    EXPORT huff_str_index

; ============================================================
; huff_lru_init — Invalidate 2-record Huffman bitstream LRU cache
;
; Clobbers: AF, HL (preserves BC, DE, IX, IY)
; ============================================================
    EXPORT huff_lru_init
huff_lru_init:
    LD   HL, 0xFFFF
    LD   (huff_lru_rec0), HL
    LD   (huff_lru_rec1), HL
    XOR  A
    LD   (huff_lru_mru), A
    INC  A              ; 1 = cache tags initialized
    LD   (huff_lru_flags), A
    RET

; ============================================================
; huff_decode_string — Decode Huffman-compressed ASCII string via 2-record LRU
;
; Input:  A  = string ID (0..HUFF_STR_COUNT-1)
;         DE = destination ASCII buffer (at least 82 bytes recommended)
; Output: NUL-terminated ASCII string written at caller's DE
;         DE = preserved (points to start of decoded string)
;         HL = DE (points to start of decoded string)
;         B  = decoded byte length (excluding NUL; 0 on error)
;         CF = 0 on success; CF = 1 on invalid ID or dat_read_slot_record error
; Clobbers: AF, BC (preserves DE, IX, IY)
; ============================================================
    EXPORT huff_decode_string
huff_decode_string:
    CP   HUFF_STR_COUNT
    JR   C, .id_ok
    XOR  A
    LD   (DE), A
    LD   H, D
    LD   L, E
    LD   B, 0
    SCF
    RET

.id_ok:
    PUSH IX
    PUSH DE             ; stack: (SP)=orig_de, (SP+2)=orig_ix

    LD   C, A           ; C = string ID
    LD   A, (huff_lru_flags)
    OR   A
    JR   NZ, .lru_ready
    CALL huff_lru_init
.lru_ready:
    ; Look up 16-bit byte offset in huff_str_index[id]
    LD   L, C
    LD   H, 0
    ADD  HL, HL
    LD   BC, huff_str_index
    ADD  HL, BC
    LD   C, (HL)
    INC  HL
    LD   B, (HL)        ; BC = byte offset into huff_stream.bin

    ; Compute byte_in_rec = C & 0x7F, rec_rem = 128 - byte_in_rec, rel_rec = BC >> 7
    LD   A, C
    AND  0x7F
    LD   E, A           ; E = byte_in_rec (0..127)
    LD   A, 128
    SUB  E              ; A = rec_rem (1..128)
    PUSH AF
    LD   L, C
    LD   H, B
    ADD  HL, HL
    LD   L, H
    LD   H, 0
    RL   H              ; HL = rel_rec (BC >> 7)
    POP  AF             ; A = rec_rem
    LD   C, E           ; C = byte_in_rec
    LD   B, A           ; B = rec_rem

    PUSH HL             ; save rel_rec
    PUSH BC             ; B = rec_rem, C = byte_in_rec
    EX   DE, HL         ; DE = rel_rec
    CALL .fetch_rec_lru
    POP  BC             ; B = rec_rem, C = byte_in_rec
    POP  DE             ; DE = rel_rec
    JR   C, .init_fail

    ; Advance IX to exact starting byte inside cached 128 B record
    LD   A, B           ; A = rec_rem
    LD   B, 0           ; BC = byte_in_rec
    ADD  IX, BC

    ; Build decode frame:
    ;   (SP+0): L = rec_rem, H = 82 (max 81 output chars + NUL guard)
    ;   (SP+2): rel_rec
    ;   (SP+4): orig_de
    ;   (SP+6): orig_ix
    PUSH DE
    LD   L, A
    LD   H, 82
    PUSH HL

    LD   HL, 4
    ADD  HL, SP
    LD   E, (HL)
    INC  HL
    LD   D, (HL)        ; DE = dest_ptr

    LD   HL, huff_tree_page ; H = page base, L = 0 (root node)
    LD   B, 0           ; bit_cnt = 0 -> load first byte

.walk_tree:
    LD   A, B
    OR   A
    JR   Z, .need_byte
.have_byte:
    DEC  B
    SLA  C              ; MSB-first bitstream: bit 7 -> CF
    JR   NC, .left
    SET  6, L           ; step into huff_tree_right[node]
.left:
    LD   A, (HL)
    BIT  7, A
    JR   NZ, .leaf
    LD   L, A           ; internal node 0..55 (H stays page base)
    JR   .walk_tree

.leaf:
    AND  0x7F
    JR   Z, .done
    POP  HL             ; L = rec_rem, H = chars_left
    DEC  H
    JR   Z, .cap_hit
    PUSH HL
    LD   (DE), A
    INC  DE
    LD   HL, huff_tree_page
    JR   .walk_tree

.need_byte:
    PUSH HL             ; save tree ptr (H=page, L=node)
    LD   HL, 2
    ADD  HL, SP
    LD   A, (HL)        ; A = rec_rem
    OR   A
    JR   NZ, .read_cur
    ; Exhausted current 128 B record: advance rel_rec and fetch via LRU
    PUSH DE
    LD   HL, 6
    ADD  HL, SP
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    INC  DE
    LD   (HL), D
    DEC  HL
    LD   (HL), E
    CALL .fetch_rec_lru
    POP  DE
    JR   C, .io_fail
    LD   A, 128
.read_cur:
    DEC  A
    LD   HL, 2
    ADD  HL, SP
    LD   (HL), A
    LD   C, (IX + 0)
    INC  IX
    LD   B, 8
    POP  HL
    JR   .have_byte

.done:
    POP  BC             ; discard chars_left:rec_rem
.cap_hit:
    XOR  A
    LD   (DE), A        ; NUL-terminate
    POP  HL             ; discard rel_rec
    POP  HL             ; HL = orig_de
    LD   A, E
    SUB  L
    LD   B, A           ; B = decoded byte length
    LD   D, H
    LD   E, L           ; DE = preserved caller buffer start
    POP  IX
    OR   A              ; CF = 0
    RET

.io_fail:
    POP  HL             ; discard tree_hl
    POP  HL             ; discard chars_left:rec_rem
    POP  HL             ; discard rel_rec
.init_fail:
    POP  DE             ; orig_de
    POP  IX             ; orig_ix
    XOR  A
    LD   (DE), A
    LD   H, D
    LD   L, E
    LD   B, 0
    SCF
    RET

; Fetch 128 B record DE of DAT_ID_HUFF_STREAM via 2-slot LRU -> IX = buf, CF on error
.fetch_rec_lru:
    LD   HL, (huff_lru_rec0)
    OR   A
    SBC  HL, DE
    JR   NZ, .chk_slot1
    XOR  A
    LD   (huff_lru_mru), A
    LD   IX, huff_lru_buf0
    RET
.chk_slot1:
    LD   HL, (huff_lru_rec1)
    OR   A
    SBC  HL, DE
    JR   NZ, .miss
    LD   A, 1
    LD   (huff_lru_mru), A
    LD   IX, huff_lru_buf1
    OR   A
    RET
.miss:
    LD   A, (huff_lru_mru)
    XOR  1
    LD   (huff_lru_mru), A
    LD   HL, huff_lru_buf0
    LD   BC, huff_lru_rec0
    JR   Z, .do_fill
    LD   HL, huff_lru_buf1
    LD   BC, huff_lru_rec1
.do_fill:
    LD   A, E
    LD   (BC), A
    INC  BC
    LD   A, D
    LD   (BC), A
    DEC  BC
    PUSH BC             ; save tag ptr for error invalidation
    PUSH HL             ; save buffer ptr for IX
    LD   A, DAT_ID_HUFF_STREAM
    CALL dat_read_slot_record
    POP  IX
    POP  HL
    RET  NC
    LD   (HL), 0xFF
    INC  HL
    LD   (HL), 0xFF
    RET

    ENDIF
