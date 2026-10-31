#importonce
// ============================================================
// asset_load_retry — hal_asset_load_prg_header, repeated on failure
// ============================================================
// A drive can miss a serial handshake and fail a load that succeeds when
// repeated (Plus/4 playtest: ST=$43, drive status 00). Each attempt rewrites
// the whole destination, and a cache hit never fails. Overlays, tiers and the
// recall strings all load through here.
// Input/output: as hal_asset_load_prg_header (A = name length, X/Y = name).
// Clobbers: A, X, Y
#if HAL_STORAGE_ASSET_LOAD_TWO_ATTEMPTS
.const ASSET_LOAD_ATTEMPTS = 2   // the OS already retries each sector
#else
.const ASSET_LOAD_ATTEMPTS = 3
#endif
asset_load_retry:
    sta alr_len
    stx alr_name_lo
    sty alr_name_hi
    lda #ASSET_LOAD_ATTEMPTS
    sta alr_left
!alr_try:
    lda alr_len
    ldx alr_name_lo
    ldy alr_name_hi
    jsr hal_asset_load_prg_header
    bcc !alr_done+
    dec alr_left                // carry stays set
    beq !alr_done+
    inc asset_load_retries
    jmp !alr_try-
!alr_done:
    rts

alr_len:            .byte 0
alr_name_lo:        .byte 0
alr_name_hi:        .byte 0
alr_left:           .byte 0
// Repeated loads since boot (wraps); the playtest auditor reports changes.
asset_load_retries: .byte 0
