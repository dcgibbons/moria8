; dat_loader.asm — Random-access MORIA8.DAT ('M8CP') loader & overlay streamer.
;
; Requires main.asm to INCLUDE "memory.inc", "dat_toc.inc", "state.inc",
; and "bdos_io.asm" beforehand.
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax).
;
; dat_toc_cache (127 B) layout:
;   +0      : valid flag (1 = initialized, 0 = uninitialized)
;   +1      : DAT format version (DAT_VERSION = 1)
;   +2      : entry_count (1..41)
;   +3      : reserved (0)
;   +4+i*3  : [u16 LE start_rec, u8 rec_count] for slot i = 0..40

    EXPORT dat_init
    EXPORT dat_lookup_slot
    EXPORT dat_read_slot_record
    EXPORT dat_get_cold_byte_len
    EXPORT overlay_load
    EXPORT ovl_to_dat_slot

; ---------------------------------------------------------------------------
; dat_init — Open MORIA8.DAT pinned to abi_program_drive + 1, validate 'M8CP'
; TOC records 0 & 1, validate rec_count_hi == 0 across all slots, and populate
; the 127-byte in-RAM dat_toc_cache. Always leaves BDOS DMA at 0xD080.
; Output: CF = 0 on success, CF = 1 on failure
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
dat_init:
    ; Zero-initialize 127-byte dat_toc_cache (leaves valid=0 until fully verified)
    LD   HL, dat_toc_cache
    LD   DE, dat_toc_cache + 1
    LD   BC, DAT_CACHE_SIZE - 1
    LD   (HL), 0
    LDIR

    CALL bdos_reset_dma_default
    CALL bdos_open_dat
    RET  C

    ; Read TOC record 0 into cpm_dma_buf (0xD080)
    LD   DE, FCB_DAT_ADDR
    LD   HL, 0
    CALL bdos_read_rand
    RET  C

    ; Verify 'M','8','C','P' magic and DAT_VERSION == 1
    LD   HL, CPM_DMA_BUF_BASE
    LD   A, (HL)
    CP   DAT_MAGIC_0
    JR   NZ, .dat_bad
    INC  HL
    LD   A, (HL)
    CP   DAT_MAGIC_1
    JR   NZ, .dat_bad
    INC  HL
    LD   A, (HL)
    CP   DAT_MAGIC_2
    JR   NZ, .dat_bad
    INC  HL
    LD   A, (HL)
    CP   DAT_MAGIC_3
    JR   NZ, .dat_bad
    INC  HL
    LD   A, (HL)                ; byte 4 = version
    CP   DAT_VERSION
    JR   NZ, .dat_bad
    INC  HL
    LD   A, (HL)                ; byte 5 = entry_count
    OR   A
    JR   Z, .dat_bad
    CP   DAT_MAX_ENTRIES + 1
    JR   NC, .dat_bad

    ; Save entry_count in cache+2 and C; parse slots 0..min(entry_count, 20)-1
    LD   (dat_toc_cache + 2), A
    LD   C, A                   ; C = entry_count
    CP   20
    JR   C, .rec0_cnt_ok
    LD   A, 20
.rec0_cnt_ok:
    LD   B, A                   ; B = slots in record 0 (1..20)
    LD   HL, CPM_DMA_BUF_BASE + DAT_TOC_OFFSET
    LD   DE, dat_toc_cache + DAT_CACHE_HEADER_SIZE
    CALL _dat_parse_toc_entries
    JR   C, .dat_bad

    ; Save slot 20 start_rec (bytes 126..127 of record 0) across record 1 read
    LD   HL, (CPM_DMA_BUF_BASE + 126)
    PUSH HL
    PUSH BC                     ; preserve C = entry_count

    ; Read TOC record 1 into cpm_dma_buf (0xD080)
    LD   DE, FCB_DAT_ADDR
    LD   HL, 1
    CALL bdos_read_rand
    POP  BC                     ; C = entry_count
    POP  HL                     ; HL = slot 20 start_rec from record 0
    RET  C

    LD   A, C
    CP   21
    JR   C, .toc_done           ; entry_count <= 20: all slots parsed

    ; Slot 20 straddles rec 0 (start_rec in HL) and rec 1 (+0..+1 rec_count)
    LD   A, (CPM_DMA_BUF_BASE + 1)  ; rec_count_hi must be 0
    OR   A
    JR   NZ, .dat_bad
    LD   DE, dat_toc_cache + DAT_CACHE_HEADER_SIZE + (20 * DAT_CACHE_ENTRY_SIZE)
    EX   DE, HL                 ; HL = cache[20], DE = start_rec
    LD   (HL), E
    INC  HL
    LD   (HL), D
    INC  HL
    LD   A, (CPM_DMA_BUF_BASE + 0)  ; rec_count_lo
    LD   (HL), A
    INC  HL
    EX   DE, HL                 ; DE = cache[21]

    ; Parse slots 21..entry_count-1 from record 1 offset +4
    LD   A, C
    SUB  21
    JR   Z, .toc_done
    LD   B, A
    LD   HL, CPM_DMA_BUF_BASE + 4
    CALL _dat_parse_toc_entries
    JR   C, .dat_bad

.toc_done:
    LD   A, 1
    LD   (dat_toc_cache + 0), A ; valid = 1
    LD   A, DAT_VERSION
    LD   (dat_toc_cache + 1), A
    CALL bdos_reset_dma_default
    OR   A                      ; CF = 0
    RET

.dat_bad:
    LD   A, 0xFE                ; synthetic invalid-DAT error code
    LD   (abi_last_bdos_err), A
    CALL bdos_reset_dma_default
    SCF
    RET

; Internal: copy B x 6-byte TOC entries at HL into 3-byte cache entries at DE.
; Validates rec_count_hi == 0 (<= 255).
; Preserves C; returns CF = 1 on invalid descriptor.
_dat_parse_toc_entries:
    PUSH BC
.pte_loop:
    LD   A, (HL)                ; start_rec lo
    LD   (DE), A
    INC  HL
    INC  DE
    LD   A, (HL)                ; start_rec hi
    LD   (DE), A
    INC  HL
    INC  DE
    LD   A, (HL)                ; rec_count lo
    LD   (DE), A
    INC  HL
    INC  DE
    LD   A, (HL)                ; rec_count hi MUST be 0 (<= 255)
    OR   A
    JR   NZ, .pte_fail
    INC  HL
    INC  HL                     ; skip byte_len lo
    INC  HL                     ; skip byte_len hi -> next 6-byte entry
    DJNZ .pte_loop
    POP  BC
    OR   A                      ; CF = 0
    RET
.pte_fail:
    POP  BC
    SCF
    RET

; ---------------------------------------------------------------------------
; dat_lookup_slot — Look up cached MORIA8.DAT TOC entry by slot ID.
; Input:  A  = slot_id (0..40)
; Output: HL = start_rec (u16), B = rec_count (u8, 1..255), CF = 0 if present
;         CF = 1 if uninitialized, out of range, or empty (rec_count == 0)
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
dat_lookup_slot:
    LD   B, A
    LD   A, (dat_toc_cache + 0)
    OR   A
    JR   Z, .lkp_fail
    LD   A, (dat_toc_cache + 2) ; entry_count
    CP   B
    JR   C, .lkp_fail
    JR   Z, .lkp_fail           ; require slot_id < entry_count
    ; offset = DAT_CACHE_HEADER_SIZE + slot_id * 3
    LD   L, B
    LD   H, 0
    LD   E, L
    LD   D, H
    ADD  HL, HL                 ; *2
    ADD  HL, DE                 ; *3
    LD   DE, dat_toc_cache + DAT_CACHE_HEADER_SIZE
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)                ; DE = start_rec
    INC  HL
    LD   B, (HL)                ; B = rec_count
    LD   A, B
    OR   A
    JR   Z, .lkp_fail
    EX   DE, HL                 ; HL = start_rec
    OR   A                      ; CF = 0
    RET
.lkp_fail:
    LD   HL, 0
    LD   B, 0
    SCF
    RET

; ---------------------------------------------------------------------------
; dat_read_slot_record — Read one 128-byte record from a MORIA8.DAT slot.
; Input:  A  = slot_id
;         DE = 0-based relative record index within slot
;         HL = destination 128-byte buffer
; Output: CF = 0, A = 0 on success; CF = 1, A != 0 on error (abi_last_bdos_err set)
; Always restores BDOS DMA to cpm_dma_buf (0xD080) on both success & error.
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
dat_read_slot_record:
    PUSH HL                     ; [dest]
    PUSH DE                     ; [dest, rel_rec]
    CALL dat_lookup_slot        ; HL = start_rec, B = rec_count
    POP  DE                     ; [dest]; DE = rel_rec
    JR   C, .rsr_bad_rec
    LD   A, D
    OR   A
    JR   NZ, .rsr_bad_rec       ; rec_count <= 255 -> D must be 0
    LD   A, E
    CP   B
    JR   NC, .rsr_bad_rec       ; require rel_rec < rec_count
    ADD  HL, DE                 ; HL = abs_rec = start_rec + rel_rec
    POP  DE                     ; DE = dest
    PUSH HL                     ; [abs_rec]
    LD   HL, CPM_DMA_BUF_BASE
    OR   A
    SBC  HL, DE
    JR   Z, .rsr_direct_default ; dest == 0xD080: read straight into default DMA
    CALL bdos_set_dma           ; DE = dest
    POP  HL                     ; HL = abs_rec
    LD   DE, FCB_DAT_ADDR
    CALL bdos_read_rand
    PUSH AF                     ; preserve A and CF across DMA reset
    CALL bdos_reset_dma_default
    POP  AF
    RET
.rsr_direct_default:
    POP  HL                     ; HL = abs_rec
    LD   DE, FCB_DAT_ADDR
    JP   bdos_read_rand
.rsr_bad_rec:
    POP  HL                     ; discard dest
    LD   A, 0xFF
    LD   (abi_last_bdos_err), A
    SCF
    RET

; ---------------------------------------------------------------------------
; dat_get_cold_byte_len — Read exact u16 byte_len for a slot from MORIA8.DAT TOC.
; Input:  A  = slot_id (e.g. 17..19 inside TOC record 0, or 0..entry_count-1)
; Output: HL = u16 byte_len, CF = 0 on success; HL = 0, CF = 1 on failure
; Leaves BDOS DMA at cpm_dma_buf (0xD080).
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
dat_get_cold_byte_len:
    LD   B, A
    LD   A, (dat_toc_cache + 0)
    OR   A
    JR   Z, .gbl_fail
    LD   A, (dat_toc_cache + 2) ; entry_count
    CP   B
    JR   C, .gbl_fail
    JR   Z, .gbl_fail
    LD   A, B
    CP   20
    JR   NC, .gbl_rec1
    ; Slots 0..19 live inside TOC record 0 at offset 6 + slot_id*6 + 4 = 10 + slot_id*6
    LD   L, A
    LD   H, 0
    ADD  HL, HL                 ; *2
    LD   E, L
    LD   D, H
    ADD  HL, HL                 ; *4
    ADD  HL, DE                 ; *6
    LD   DE, 10                 ; DAT_TOC_OFFSET (6) + DAT_OFF_BYTE_LEN (4)
    ADD  HL, DE
    PUSH HL                     ; save offset within record 0
    LD   HL, 0
    JR   .gbl_read_toc
.gbl_rec1:
    ; Slot 20 byte_len is at record 1 + 2; slots 21..40 at 4 + (slot-21)*6 + 4
    CP   20
    JR   NZ, .gbl_rec1_21p
    LD   HL, 2
    PUSH HL
    LD   HL, 1
    JR   .gbl_read_toc
.gbl_rec1_21p:
    SUB  21
    LD   L, A
    LD   H, 0
    ADD  HL, HL
    LD   E, L
    LD   D, H
    ADD  HL, HL
    ADD  HL, DE                 ; (slot - 21) * 6
    LD   DE, 8                  ; 4 (rec1 tail start) + 4 (DAT_OFF_BYTE_LEN)
    ADD  HL, DE
    PUSH HL
    LD   HL, 1
.gbl_read_toc:
    PUSH HL                     ; preserve TOC record number (0 or 1) across DMA reset
    CALL bdos_reset_dma_default
    POP  HL
    LD   DE, FCB_DAT_ADDR
    CALL bdos_read_rand
    POP  HL                     ; HL = byte offset inside cpm_dma_buf
    JR   C, .gbl_fail
    LD   DE, CPM_DMA_BUF_BASE
    ADD  HL, DE
    LD   E, (HL)
    INC  HL
    LD   D, (HL)
    EX   DE, HL                 ; HL = u16 byte_len
    OR   A                      ; CF = 0
    RET
.gbl_fail:
    LD   HL, 0
    SCF
    RET

; ---------------------------------------------------------------------------
; overlay_load — Stream overlay ovl_id (1..OVL_COUNT) directly into 0x5600+.
; Input:  A = ovl_id (1..19)
; Output: CF = 0 on success (abi_current_overlay = ovl_id)
;         CF = 1 on error (abi_current_overlay = OVL_NONE if window dirtied)
; ALWAYS calls bdos_reset_dma_default (0xD080) on BOTH success and error paths!
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
overlay_load:
    OR   A
    JR   Z, .ovl_bad_id
    CP   OVL_COUNT + 1
    JR   NC, .ovl_bad_id

    PUSH AF                     ; save ovl_id
    DEC  A
    LD   E, A
    LD   D, 0
    LD   HL, ovl_to_dat_slot
    ADD  HL, DE
    LD   A, (HL)                ; A = DAT slot ID
    CALL dat_lookup_slot        ; HL = start_rec, B = rec_count
    JR   C, .ovl_lookup_fail
    LD   A, B
    OR   A
    JR   Z, .ovl_range_fail
    CP   OVL_MAX_RECORDS + 1
    JR   NC, .ovl_range_fail

    ; Stream B records starting at HL into DE = OVL_WINDOW_BASE
    LD   DE, OVL_WINDOW_BASE
.ovl_loop:
    PUSH BC                     ; [ovl_id, rec_rem]
    PUSH HL                     ; [ovl_id, rec_rem, cur_rec]
    PUSH DE                     ; [ovl_id, rec_rem, cur_rec, cur_dma]
    CALL bdos_set_dma           ; DE = cur_dma
    POP  DE
    POP  HL
    PUSH DE
    PUSH HL
    LD   DE, FCB_DAT_ADDR
    CALL bdos_read_rand
    POP  HL
    POP  DE
    POP  BC
    JR   C, .ovl_stream_err
    INC  HL                     ; cur_rec++
    PUSH HL
    LD   HL, CPM_RECORD_SIZE
    ADD  HL, DE
    EX   DE, HL                 ; cur_dma += 128
    POP  HL
    DJNZ .ovl_loop

    CALL bdos_reset_dma_default ; invariant: always restore 0xD080
    POP  AF                     ; A = ovl_id
    LD   (abi_current_overlay), A
    OR   A                      ; CF = 0
    RET

.ovl_stream_err:
    XOR  A
    LD   (abi_current_overlay), A   ; OVL_NONE: 0x5600+ may be partially overwritten
    POP  AF
    CALL bdos_reset_dma_default     ; invariant: always restore 0xD080 on error
    SCF
    RET

.ovl_range_fail:
    LD   A, 0xFE
    LD   (abi_last_bdos_err), A
.ovl_lookup_fail:
    POP  AF
.ovl_bad_id:
    CALL bdos_reset_dma_default     ; invariant: always restore 0xD080 on error
    SCF
    RET

; Map overlay ID (1..19) -> MORIA8.DAT TOC slot ID (0..13, 20..24)
ovl_to_dat_slot:
    DB   0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
    DB   20, 21, 22, 23, 24
ovl_to_dat_slot_end:
    ASSERT (ovl_to_dat_slot_end - ovl_to_dat_slot) == OVL_COUNT
