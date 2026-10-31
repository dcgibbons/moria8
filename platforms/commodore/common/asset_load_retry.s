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

// asset_load_required — asset_load_retry for a file the game cannot go on
// without (an overlay, a tier, the recall strings, a payload): when every
// attempt fails, ask for the program disk by the file's name, wait for a
// key and try again, rather than hand the caller a failure it can only meet
// with a restart, a crash or a stale overlay window. The C128's cache
// preloads (a miss loads from disk later) and the Atari's ATARI.BNK (it
// brings the prompt) keep asset_load_retry.
// Input: as asset_load_retry. Output: C = 0.
// Clobbers: A, X, Y; after a prompt, as disk_prompt_game: the screen (no
// redraw), zp_ptr0, the cursor and zp_text_color
#if C64_UNIT_TEST && !ASSET_LOAD_PROMPT_EXTERNAL
// Unit tests have no disk and no screen UI: a required load fails back to
// the caller (test_subsystems brings its own prompt and tests the loop).
.label asset_load_required = asset_load_retry
#else
asset_load_required:
    jsr asset_load_retry
    bcc !alq_done+
    jsr asset_load_ask_for_disk
    lda alr_len
    ldx alr_name_lo
    ldy alr_name_hi
    jmp asset_load_required
!alq_done:
    rts
#endif

#if !ASSET_LOAD_PROMPT_EXTERNAL && !C64_UNIT_TEST
#import "asset_load_prompt.s"
#endif

alr_len:            .byte 0
alr_name_lo:        .byte 0
alr_name_hi:        .byte 0
alr_left:           .byte 0
// Repeated loads since boot (wraps); the playtest auditor reports changes.
asset_load_retries: .byte 0
