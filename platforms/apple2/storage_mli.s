#importonce
// Apple IIe storage HAL over the ProDOS 8 MLI.
//
// Implements the full hal_storage_* contract surface
// (platforms/commodore/hal/hal_storage.s) plus the hal_overlay.s asset-load
// contract on top of ProDOS 8 MLI calls at $BF00. The KERNAL-shaped byte
// stream primitives (SETNAM/SETLFS/OPEN/CLOSE/CHKIN/CHKOUT/CHRIN/CHROUT/
// CLRCHN/READST) live in save_stream.s; this file owns MLI command builders,
// the pathname converter, the ProDOS-error-to-HAL_STATUS map, media probes,
// marker I/O, whole-file asset loads, diagnostics, and every filename label.
//
// Conventions:
// - MLI call: jsr $BF00 / .byte command / .word param_list. Carry set = error,
//   A = ProDOS error code.
// - Higher-level entries follow the contract error convention: carry clear =
//   success; carry set with A = HAL_STATUS_*, X = raw ProDOS code,
//   Y = HAL_STORAGE_PHASE_*.
// - Every MLI sequence is wrapped: jsr save_zp ($02-$8F to zp_save_buf)
//   before, jsr restore_zp + jsr a2_install_zp_thunks after (a2_mli_begin /
//   a2_mli_end). The MLI zero-page footprint ($3A-$4E) sits inside the saved
//   core window; platform ZP $90+ is never touched by the MLI.
// - One open file at a time. The OPEN io_buffer is the reserved 1024-byte
//   page-aligned block at $BB00-$BEFF (memory.s).
// - Pathnames are built at A2_MLI_PATHNAME ($0290, platform scratch):
//   length byte, then ASCII, high bit clear, no trailing zero. All game
//   filenames are already ProDOS-legal (A-Z 0-9 '.', <= 15 chars); the
//   converter uppercases a-z defensively. Save-side names ("0:"/"S0:"/"@0:")
//   become absolute "/VOLUME/FILE" pathnames when Disk Setup has selected a
//   separate save volume (disk_mode >= A2_DISK_MODE_TWO_DRIVE).
// - Filename labels keep the Commodore PETSCII strings byte-identical
//   ("@0:THE.GAME,S,W" etc.) so the shared save-slot menu's runtime digit
//   mutation and its offset asserts hold unchanged; the converter strips the
//   "@"/"0:"/"S0:" prefixes and ",S,R"/",S,W" suffixes when building MLI
//   pathnames. Tier/overlay/title labels are plain zero-terminated names
//   (display code prints them; lengths exclude the trailing zero).

#import "hal/hal_contract.s"
#import "hal/storage_policy.s"

// ============================================================
// Constants
// ============================================================

.const A2_MLI             = $bf00
.const A2_MLI_CREATE      = $c0
.const A2_MLI_DESTROY     = $c1
.const A2_MLI_GET_INFO    = $c4
.const A2_MLI_ON_LINE     = $c5
.const A2_MLI_GET_PREFIX  = $c7
.const A2_MLI_OPEN        = $c8
.const A2_MLI_READ        = $ca
.const A2_MLI_WRITE       = $cb
.const A2_MLI_CLOSE       = $cc
.const A2_MLI_SET_MARK    = $ce
.const A2_MLI_SET_EOF     = $d0

// MLI OPEN io_buffer: reserved 1024-byte page-aligned block (memory.s).
.const A2_MLI_IO_BUFFER   = $bb00

// MLI pathname buffer in platform scratch ($0290-$02D0, memory.s).
.const A2_MLI_PATHNAME    = $0290
.const A2_MLI_PATHNAME_CAPACITY = 64

// Name converter & PAK workspace: platform-owned ZP ($90-$EF, memory.s). Survives
// MLI calls; never inside the saved $02-$8F core window.
.const a2_nc_ptr          = $a4       // 2 bytes: source name pointer
.const a2_nc_len          = $a6       // source name length
.const a2_nc_tmp          = $a7       // suffix mode-letter stash
.const a2_pak_id          = $ab       // resolved MORIA8.PAK entry index
.const a2_pak_len         = $ac       // 2 bytes: resolved PAK entry length

// ============================================================
// Diagnostic and classification state (ASCII digits stay initialized here;
// zero-init bytes live in claimed low scratch $0329-$0335, memory.s).
// ============================================================

hal_storage_diag_dos0:    .byte $30   // ASCII tens digit of diag_code
hal_storage_diag_dos1:    .byte $30   // ASCII ones digit of diag_code

// ============================================================
// Static MLI parameter blocks (resident main RAM; the MLI reads values and
// writes results in place)
// ============================================================

a2_create_params:
    .byte 7
    .word A2_MLI_PATHNAME
    .byte $c3                       // access: full (unlocked)
    .byte $06                       // file_type: BIN
    .word 0                         // aux_type
    .byte 1                         // storage_type: standard file
    .word 0                         // create_date
    .word 0                         // create_time

a2_destroy_params:
    .byte 1
    .word A2_MLI_PATHNAME

a2_gfi_params:
    .byte 10
    .word A2_MLI_PATHNAME
a2_gfi_access:  .byte 0
a2_gfi_type:    .byte 0
a2_gfi_aux:     .word 0             // load address for our BIN payloads
a2_gfi_storage: .byte 0
a2_gfi_blocks:  .word 0             // blocks used (size = blocks * 512)
    .word 0                         // mod_date
    .word 0                         // mod_time
    .word 0                         // create_date
    .word 0                         // create_time

a2_open_params:
    .byte 3
    .word A2_MLI_PATHNAME
    .word A2_MLI_IO_BUFFER
a2_open_ref:    .byte 0             // ref_num result

a2_rw_params:
    .byte 4
a2_rw_ref:      .byte 0
a2_rw_buf:      .word 0
a2_rw_req:      .word 0
a2_rw_trans:    .word 0

a2_close_params:
    .byte 1
a2_close_ref:   .byte 0             // 0 = close all files

a2_mark_params:
    .byte 2
a2_mark_ref:    .byte 0
    .byte 0, 0, 0                   // 24-bit file position (LE)
.label a2_mark_pos = a2_mark_ref + 1

a2_eof_params:
    .byte 2
a2_eof_ref:     .byte 0
    .byte 0, 0, 0                   // 24-bit EOF position (truncate to 0)

// ON_LINE/GET_PREFIX param blocks + primitives live in disk_setup_a2.s
// (OVL.STORAGE): only the Disk Setup coordinator and media prompts enumerate
// volumes, and resident space is byte-tight.

// ============================================================
// hal_storage_enter_os / hal_storage_exit_os
// No OS banking on the Apple II: main RAM is always visible and the MLI is
// always callable. Genuinely no-ops, matching hal_memory_enter_os/exit_os.
// ============================================================
hal_storage_enter_os:
    clc
    rts

hal_storage_exit_os:
    clc
    rts

// Best-effort drive-init equivalent. ProDOS tracks mounted volumes itself;
// there is no drive-init command channel. Carry is not meaningful.
hal_storage_init_selected_drive:
    clc
    rts

// ============================================================
// a2_mli_begin / a2_mli_end — ZP save/restore wrap for every MLI sequence.
// a2_mli_end preserves the MLI result: A and the flags (including carry) are
// exactly what the last MLI call returned.
// ============================================================
a2_mli_begin:
    jmp save_zp

a2_mli_end:
    php
    pha
    jsr restore_zp
    jsr a2_install_zp_thunks        // belt and braces (TRM: MLI never touches high ZP)
    jsr a2_platform_runtime_resync  // MLI/driver may change IIe soft switches
    pla
    plp
    rts

// ============================================================
// a2i_* — raw MLI primitives. Caller must be inside a2_mli_begin/end.
// Each returns the MLI result verbatim: carry clear = ok; carry set,
// A = ProDOS error code.
// ============================================================
a2i_create:
    jsr A2_MLI
    .byte A2_MLI_CREATE
    .word a2_create_params
    rts

a2i_destroy:
    jsr A2_MLI
    .byte A2_MLI_DESTROY
    .word a2_destroy_params
    rts

a2i_get_file_info:
    jsr A2_MLI
    .byte A2_MLI_GET_INFO
    .word a2_gfi_params
    rts

a2i_open:
    jsr A2_MLI
    .byte A2_MLI_OPEN
    .word a2_open_params
    rts

a2i_read:
    jsr A2_MLI
    .byte A2_MLI_READ
    .word a2_rw_params
    rts

a2i_write:
    jsr A2_MLI
    .byte A2_MLI_WRITE
    .word a2_rw_params
    rts

a2i_close:
    jsr A2_MLI
    .byte A2_MLI_CLOSE
    .word a2_close_params
    rts

a2i_close_open_ref:
    lda a2_open_ref
    sta a2_close_ref
    jmp a2i_close

a2i_set_mark:
    jsr A2_MLI
    .byte A2_MLI_SET_MARK
    .word a2_mark_params
    rts

a2i_set_eof0:
    jsr A2_MLI
    .byte A2_MLI_SET_EOF
    .word a2_eof_params
    rts

// ============================================================
// a2_code_to_digits — ASCII decimal digits of a ProDOS error code.
// Input: A = code. Output: hal_storage_diag_dos0/dos1. Clobbers: A, X.
// ============================================================
a2_code_to_digits:
    ldx #$30                        // tens accumulator, ASCII
!tens:
    cmp #10
    bcc !ones+
    sbc #10                         // carry set by the cmp above
    inx
    jmp !tens-
!ones:
    ora #$30
    sta hal_storage_diag_dos1
    stx hal_storage_diag_dos0
    rts

// ============================================================
// a2_map_error / a2_map_media_error — classify a raw ProDOS error via shared
// lookup table. Both update hal_storage_diag_code/dos0/dos1 and a2_last_status,
// and return with carry set.
// a2_map_error:       A = HAL_STATUS_*, X = raw code, Y = phase.
// a2_map_media_error: a2_media_status = a2_last_status = A = HAL_STORAGE_STATUS_*.
// ============================================================
a2_err_raw:
    .byte A2ERR_NOT_FOUND, A2ERR_PATH_NOT_FOUND
    .byte A2ERR_WRITE_PROT, A2ERR_ACCESS
    .byte A2ERR_DISK_FULL
    .byte A2ERR_NO_DEVICE, A2ERR_VOL_NOT_FOUND, A2ERR_DISK_SWITCHED
.const A2_ERR_MAP_COUNT = * - a2_err_raw
a2_err_status:
    .byte HAL_STATUS_ERR_NOT_FOUND, HAL_STATUS_ERR_NOT_FOUND
    .byte HAL_STATUS_ERR_WRITE_PROTECTED, HAL_STATUS_ERR_WRITE_PROTECTED
    .byte HAL_STATUS_ERR_DISK_FULL
    .byte HAL_STATUS_ERR_NO_DEVICE, HAL_STATUS_ERR_NO_DEVICE, HAL_STATUS_ERR_UNKNOWN
    .byte HAL_STATUS_ERR_UNKNOWN
a2_err_media:
    .byte HAL_STORAGE_STATUS_WRONG_MEDIA, HAL_STORAGE_STATUS_WRONG_MEDIA
    .byte HAL_STORAGE_STATUS_WRITE_PROTECTED, HAL_STORAGE_STATUS_WRITE_PROTECTED
    .byte HAL_STORAGE_STATUS_DISK_FULL
    .byte HAL_STORAGE_STATUS_NO_DEVICE, HAL_STORAGE_STATUS_WRONG_MEDIA, HAL_STORAGE_STATUS_WRONG_MEDIA
    .byte HAL_STORAGE_STATUS_UNKNOWN

a2_map_error:
    jsr a2_map_err_find
    lda a2_err_status,x
    sta a2_last_status
    ldx hal_storage_diag_code
    ldy hal_storage_diag_phase
    sec
    rts

a2_map_media_error:
    jsr a2_map_err_find
    lda a2_err_media,x
    sta a2_media_status
    sta a2_last_status
    sec
    rts

a2_map_err_find:
    sta hal_storage_diag_code
    jsr a2_code_to_digits
    lda hal_storage_diag_code
    ldx #0
!loop:
    cmp a2_err_raw,x
    beq !done+
    inx
    cpx #A2_ERR_MAP_COUNT
    bne !loop-
!done:
    rts

// a2_clear_diag — reset diagnostics before a successful-path sequence.
a2_clear_diag:
    lda #0
    sta hal_storage_diag_code
    sta a2_last_status
    lda #$30
    sta hal_storage_diag_dos0
    sta hal_storage_diag_dos1
    rts

// ============================================================
// a2_mli_set_pathname — KERNAL name → length-prefixed MLI pathname.
// Input: A = name length, X = name pointer lo, Y = name pointer hi.
// Strips "@"/"0:"/"S0:" prefixes and truncates at the first ","
// (KERNAL mode suffix); uppercases a-z. Sets a2_name_write / a2_name_replace
// / a2_name_scratch.
// Output: A = pathname length; pathname at A2_MLI_PATHNAME.
// Runs before a2_mli_begin; touches no MLI state and no core ZP.
// ============================================================
a2_mli_set_pathname:
    sta a2_nc_len
    stx a2_nc_ptr
    sty a2_nc_ptr + 1
    lda #0
    sta a2_name_write
    sta a2_name_replace
    sta a2_name_scratch
    sta a2_name_drive
    ldx #0                          // pathname out index
    ldy #0                          // source in index
    // Prefix passes: '@' (replace), "0:" (drive), "S0:" (scratch)
!prefix_loop:
    cpy a2_nc_len
    bcs !body+
    lda (a2_nc_ptr),y
    cmp #$40                        // '@'
    bne !not_at+
    lda #1
    sta a2_name_replace
    iny
    jmp !prefix_loop-
!not_at:
    cmp #$53                        // 'S'
    bne !not_s+
    lda a2_nc_len
    sec
    sbc #3
    bcc !body+                      // too short for "S0:"
    iny
    lda (a2_nc_ptr),y
    cmp #$30                        // '0'
    bne !not_s2+
    iny
    lda (a2_nc_ptr),y
    cmp #$3a                        // ':'
    bne !not_s2+
    lda #1
    sta a2_name_scratch
    sta a2_name_drive
    iny
    jmp !prefix_loop-
!not_s2:
    dey
    jmp !body+
!not_s:
    cmp #$30                        // '0'
    bne !body+
    lda a2_nc_len
    sec
    sbc #2
    bcc !body+                      // too short for "0:"
    iny
    lda (a2_nc_ptr),y
    cmp #$3a                        // ':'
    bne !not_s2-
    iny
    lda #1
    sta a2_name_drive
    jmp !prefix_loop-
!body:
    // Save-side names ("0:"/"S0:"/"@0:") resolve on the selected save volume
    // once Disk Setup has chosen a separate one; program assets (no drive
    // prefix) always stay relative to the boot prefix.
    lda a2_name_drive
    beq !body_copy+
    lda disk_mode
    cmp #A2_DISK_MODE_TWO_DRIVE
    bcc !body_copy+
    lda a2_save_volume              // 0 = no volume selected: stay relative
    beq !body_copy+
    sty a2_nc_tmp                   // stash source index
    lda #$2f                        // '/'
    sta A2_MLI_PATHNAME + 1,x
    inx
    ldy #0
!vol_copy:
    cpy a2_save_volume
    bcs !vol_done+
    lda a2_save_volume + 1,y
    sta A2_MLI_PATHNAME + 1,x
    inx
    iny
    jmp !vol_copy-
!vol_done:
    lda #$2f                        // '/'
    sta A2_MLI_PATHNAME + 1,x
    inx
    ldy a2_nc_tmp                   // restore source index
!body_copy:
    cpy a2_nc_len
    bcs !done+
    lda (a2_nc_ptr),y
    cmp #$2c                        // ',' -> KERNAL mode suffix begins
    beq !suffix+
    cmp #$61
    bcc !store+
    cmp #$7b
    bcs !store+
    and #$df                        // uppercase a-z defensively
!store:
    sta A2_MLI_PATHNAME + 1,x
    inx
    iny
    jmp !body_copy-
!suffix:
    // Mode letter at y+3 in ",S,R" / ",S,W" decides write-vs-read intent.
    tya
    clc
    adc #3
    cmp a2_nc_len
    bcs !done+
    tay
    lda (a2_nc_ptr),y
    cmp #$57                        // 'W'
    bne !done+
    lda #1
    sta a2_name_write
!done:
    stx A2_MLI_PATHNAME
    txa
    rts

// ============================================================
// hal_storage_probe_media — check whether program media responds. The probe
// is GET_FILE_INFO on MORIA8.PAK (always present on the game volume, addressed
// relative to the boot prefix); in one-drive swap mode it fails while the
// save disk is mounted, which is exactly what disk_prompt_game[_required]
// needs. The device number in X is advisory on Commodore and ignored here.
// Output: carry clear = present, carry set = absent/unusable.
// ============================================================
hal_storage_probe_media:
hal_storage_require_program_media:
    lda #hal_storage_program_probe_name_len
    ldx #<hal_storage_program_probe_name
    ldy #>hal_storage_program_probe_name
    jsr a2_mli_set_pathname
    jsr a2_clear_diag
    jsr a2_mli_begin
    lda #HAL_STORAGE_PHASE_PROBE
    sta hal_storage_diag_phase
    jsr a2i_get_file_info
    jsr a2_mli_end
    bcc !ok+
    jmp a2_map_media_error  // carry set

!ok:
    lda #HAL_STORAGE_STATUS_OK
    sta a2_media_status
    clc
    rts

// ============================================================
// hal_storage_marker_present — validate the save-media marker MORIA8.ID.
// GET_FILE_INFO probe plus a magic-byte content check (Commodore semantics:
// the file must exist AND start with the marker magic).
// Output: carry clear = valid save media, carry set = wrong/absent media.
//         a2_media_status carries the HAL_STORAGE_STATUS_* verdict.
// ============================================================
hal_storage_marker_present:
    lda #hal_storage_marker_read_name_len
    ldx #<hal_storage_marker_read_name
    ldy #>hal_storage_marker_read_name
    jsr a2_mli_set_pathname
    jsr a2_clear_diag
    jsr a2_mli_begin
    lda #HAL_STORAGE_PHASE_MARKER
    sta hal_storage_diag_phase
    jsr a2i_get_file_info
    bcs !fail_end+
    jsr a2i_open
    bcs !fail_end+
    lda a2_open_ref
    sta a2_rw_ref
    lda #<a2_probe_buf
    sta a2_rw_buf
    lda #>a2_probe_buf
    sta a2_rw_buf + 1
    lda #hal_storage_marker_magic_len
    sta a2_rw_req
    lda #0
    sta a2_rw_req + 1
    jsr a2i_read
    php
    jsr a2i_close_open_ref
    plp
    bcs !fail_end+
    jsr a2_mli_end
    ldx #0
!compare:
    lda a2_probe_buf,x
    cmp hal_storage_marker_magic,x
    bne !wrong+
    inx
    cpx #hal_storage_marker_magic_len
    bcc !compare-
    lda #HAL_STORAGE_STATUS_OK
    sta a2_media_status
    clc
    rts
!wrong:
    // Marker file exists but contents mismatch = wrong media (no MLI error).
    lda #$30
    sta hal_storage_diag_dos0
    sta hal_storage_diag_dos1
    lda #HAL_STORAGE_STATUS_WRONG_MEDIA
    sta a2_media_status
    sta a2_last_status
    sec
    rts
!fail_end:
    jsr a2_mli_end
    jmp a2_map_media_error  // carry set


// Requiring save media is the marker probe on the selected save volume
// (a2_mli_set_pathname routes "0:" names by disk_mode); callers (save.s,
// score_io.s via the disk_require_save_media alias) get carry clear = usable,
// carry set + a2_media_status = failure verdict.
.label hal_storage_require_save_media = hal_storage_marker_present
// save.s and score_io.s call the historical common symbol directly.
.label disk_require_save_media = hal_storage_marker_present

.label hal_storage_diag_code   = a2_diag_code
.label hal_storage_diag_phase  = a2_diag_phase
.label hal_storage_diag_readst = a2_diag_readst
.label hal_storage_diag_device = a2_diag_device

// ============================================================
// hal_storage_marker_init — create MORIA8.ID and write the marker magic.
// DESTROY (missing file is fine) + CREATE + OPEN + WRITE magic + CLOSE.
// Lives in StorageOverlay (sole caller is disk_setup_a2.s).
// Output: carry clear = marker written, carry set = failure
//         (a2_media_status = HAL_STORAGE_STATUS_* verdict).
// ============================================================
.segment StorageOverlay
hal_storage_marker_init:
    lda #hal_storage_marker_write_name_len
    ldx #<hal_storage_marker_write_name
    ldy #>hal_storage_marker_write_name
    jsr a2_mli_set_pathname
    jsr a2_clear_diag
    jsr a2_mli_begin
    lda #HAL_STORAGE_PHASE_MARKER
    sta hal_storage_diag_phase
    jsr a2i_destroy
    bcc !create+
    cmp #A2ERR_NOT_FOUND
    bne !fail_end+                  // real destroy failure (e.g. write-protect)
!create:
    jsr a2i_create
    bcs !fail_end+
    jsr a2i_open
    bcs !fail_end+
    lda a2_open_ref
    sta a2_rw_ref
    lda #<hal_storage_marker_magic
    sta a2_rw_buf
    lda #>hal_storage_marker_magic
    sta a2_rw_buf + 1
    lda #hal_storage_marker_magic_len
    sta a2_rw_req
    lda #0
    sta a2_rw_req + 1
    jsr a2i_write
    bcs !close_fail+
    jsr a2i_close_open_ref
    bcs !fail_end+
    jsr a2_mli_end
    lda #HAL_STORAGE_STATUS_OK
    sta a2_media_status
    clc
    rts
!close_fail:
    pha
    jsr a2i_close_open_ref
    pla
!fail_end:
    jsr a2_mli_end
    jmp a2_map_media_error  // carry set
.segment Default


// ============================================================
// Status classifiers (contract: return A = HAL_STORAGE_STATUS_*)
// ============================================================

// Most recent save-media / Disk Setup failure verdict.
hal_storage_save_media_status:
hal_storage_setup_status:
    lda a2_media_status
    rts

// Most recent save/load record stream verdict. With
// HAL_STORAGE_STREAM_STATUS_HELPERS the shared save.s helpers own this.
.label hal_storage_save_stream_status = save_stream_status
.label hal_storage_load_stream_status = load_stream_status

// ============================================================
// hal_storage_read_command_status — there is no command channel on ProDOS;
// synthesize the diag digits from the last recorded MLI error code. Callable
// in any visibility state (performs no MLI call).
// ============================================================
hal_storage_read_command_status:
    lda hal_storage_diag_code
    jsr a2_code_to_digits
    clc
    rts

// hal_storage_command_status — classify the most recently captured status.
hal_storage_command_status:
    lda a2_last_status
    rts

// ============================================================
// MORIA8.PAK random-access resolver & loader (MLI_SET_MARK = $CE)
// Entries 0..7 are sequential boot payloads; entries 8..19 are cold assets
// packed into MORIA8.PAK (A2.PLAY, OVL.START..TITLE, LEGALUI, TITLE).
// ============================================================

.const A2_PAK_ENTRY_PLAY    = 8
.const A2_PAK_ENTRY_LEGALUI = 18
.const A2_PAK_ENTRY_TITLE   = 19
.const A2_OVL_LOAD_ADDR     = $a400

// Parallel to hal_storage_overlay_name_lo/hi/len (0..12 -> MORIA8.PAK indices).
a2_overlay_pak_id:
    .byte 9, 10, 11, 12, 13, 3, 4, 5, 6, 14, 15, 16, 17
.assert "PAK id table matches hal_platform_overlay_count", * - a2_overlay_pak_id, hal_platform_overlay_count

// Compare A2_MLI_PATHNAME against string at (a2_nc_ptr) of length a2_nc_len.
// Output: Z=1 (BEQ) on match, Z=0 (BNE) on mismatch. Preserves X.
a2_cmp_pathname:
    lda A2_MLI_PATHNAME
    cmp a2_nc_len
    bne !no+
    tay
    beq !yes+
!loop:
    lda A2_MLI_PATHNAME,y
    dey
    cmp (a2_nc_ptr),y
    bne !no+
    tya
    bne !loop-
!yes:
    lda #0
!no:
    rts

// Match normalized A2_MLI_PATHNAME against packed MORIA8.PAK cold payloads.
// Output: C=0 -> A = PAK entry index, X/Y = BIN load address (lo/hi);
//         C=1 -> filename is not a packed entry.
a2_pak_resolve:
    ldx #hal_platform_overlay_count - 1
!ovl_chk:
    lda hal_storage_overlay_name_lo,x
    sta a2_nc_ptr
    lda hal_storage_overlay_name_hi,x
    sta a2_nc_ptr + 1
    lda hal_storage_overlay_name_len,x
    sta a2_nc_len
    jsr a2_cmp_pathname
    beq !ovl_hit+
    dex
    bpl !ovl_chk-

    lda #<a2_play_file_name
    sta a2_nc_ptr
    lda #>a2_play_file_name
    sta a2_nc_ptr + 1
    lda #a2_play_file_name_len
    sta a2_nc_len
    jsr a2_cmp_pathname
    bne !chk_legal+
    lda #A2_PAK_ENTRY_PLAY
    ldx #<A2_PLAY_SLOT_BASE
    ldy #>A2_PLAY_SLOT_BASE
    clc
    rts

!chk_legal:
    lda #<legal_ui_filename
    sta a2_nc_ptr
    lda #>legal_ui_filename
    sta a2_nc_ptr + 1
    lda #7
    sta a2_nc_len
    jsr a2_cmp_pathname
    bne !miss+
    lda #A2_PAK_ENTRY_LEGALUI
!ret_ovl_addr:
    ldx #<A2_OVL_LOAD_ADDR
    ldy #>A2_OVL_LOAD_ADDR
    clc
    rts
!ovl_hit:
    lda a2_overlay_pak_id,x
    jmp !ret_ovl_addr-
!miss:
    sec
    rts

// Open MORIA8.PAK, read its 256-byte header prefix into a2_ss_buf, fetch
// 16-bit length (bytes 2..) and 24-bit offset (bytes 128..), and SET_MARK ($CE).
// Precondition: caller inside a2_clear_diag + a2_mli_begin.
// Input: A = PAK entry index. Output: C=0 open & positioned; C=1 closed + A=err.
a2_pak_open_seek:
    sta a2_pak_id
    lda #hal_storage_program_probe_name_len
    ldx #<hal_storage_program_probe_name
    ldy #>hal_storage_program_probe_name
    jsr a2_mli_set_pathname
    lda #HAL_STORAGE_PHASE_OPEN
    sta hal_storage_diag_phase
    jsr a2i_open
    bcs !open_err+
    lda a2_open_ref
    sta a2_rw_ref
    sta a2_mark_ref
    lda #HAL_STORAGE_PHASE_READ
    sta hal_storage_diag_phase
    lda #<a2_ss_buf
    sta a2_rw_buf
    lda #>a2_ss_buf
    sta a2_rw_buf + 1
    lda #0
    sta a2_rw_req
    lda #1
    sta a2_rw_req + 1               // 256-byte PAK header prefix (<= 42 entries)
    jsr a2i_read
    bcs !err_close+
    lda a2_rw_trans + 1
    beq !err_bad_close+             // truncated header
    lda a2_pak_id
    cmp #42
    bcs !err_bad_close+
    cmp a2_ss_buf                   // entry index < entry count
    bcs !err_bad_close+
    asl
    tay
    lda a2_ss_buf + 2,y
    sta a2_pak_len
    lda a2_ss_buf + 3,y
    sta a2_pak_len + 1
    ora a2_pak_len
    beq !err_bad_close+
    tya
    clc
    adc a2_pak_id
    tay
    lda a2_ss_buf + 128,y
    sta a2_mark_pos
    lda a2_ss_buf + 129,y
    sta a2_mark_pos + 1
    lda a2_ss_buf + 130,y
    sta a2_mark_pos + 2
    jsr a2i_set_mark
    bcs !err_close+
    clc
!open_err:
    rts
!err_bad_close:
    lda #$53
!err_close:
    pha
    jsr a2i_close_open_ref
    pla
    sec
    rts

// ============================================================
// hal_asset_load_prg_header — load a packed payload (A2.PLAY, OVL.*, LEGALUI)
// from MORIA8.PAK to its recorded load address ($7C00 or $A400).
// Input: A = filename length, X = filename lo, Y = filename hi.
// Output: carry clear = success, carry set = failure.
// ============================================================
hal_asset_load_prg_header:
    // Aux-cache front end: hot overlay classes populate the window from
    // aux (~ms) and skip the disk entirely. try_cache clobbers A/X/Y, so
    // the filename registers ride the stack for the disk fallback.
    pha
    txa
    pha
    tya
    pha
    jsr a2_overlay_try_cache
    bcs !no_cache+
    pla
    pla
    pla
    clc
    rts
!no_cache:
    pla
    tay
    pla
    tax
    pla
    jsr a2_mli_set_pathname
    jsr a2_pak_resolve
    bcs a2_asset_not_packed
    stx a2_asset_dest
    sty a2_asset_dest + 1
a2_pak_load_to_dest:
    sta a2_pak_id
    jsr a2_clear_diag
    jsr a2_mli_begin
    lda a2_pak_id
    jsr a2_pak_open_seek
    bcs a2_asset_fail_end
    lda a2_pak_len
    sta a2_rw_req
    lda a2_pak_len + 1
    sta a2_rw_req + 1
    lda a2_asset_dest
    sta a2_rw_buf
    lda a2_asset_dest + 1
    sta a2_rw_buf + 1
a2_asset_read_close:
    lda #HAL_STORAGE_PHASE_READ
    sta hal_storage_diag_phase
    jsr a2i_read
    bcs a2_asset_close_fail
    jsr a2i_close_open_ref
    bcs a2_asset_fail_end
a2_asset_done_ok:
    jsr a2_mli_end
    clc
    rts
a2_asset_close_fail:
    pha
    jsr a2i_close_open_ref
    pla
a2_asset_fail_end:
    jsr a2_mli_end
    jmp a2_map_error                // carry set
a2_asset_not_packed:
    jsr a2_clear_diag
    lda #HAL_STORAGE_PHASE_PROBE
    sta hal_storage_diag_phase
    lda #$53                        // synthetic invalid-parameter error
    jmp a2_map_error

// ============================================================
// hal_asset_load — KERNAL LOAD equivalent over the name stashed by
// hal_storage_setnam. A = 0 for LOAD, nonzero for VERIFY (existence probe).
// X/Y = caller-selected load address. Only packed MORIA8.PAK assets resolve.
// ============================================================
hal_asset_load:
    sta a2_asset_verify
    stx a2_asset_dest
    sty a2_asset_dest + 1
    lda a2_ss_name_len
    ldx a2_ss_name_lo
    ldy a2_ss_name_hi
    jsr a2_mli_set_pathname
    jsr a2_pak_resolve
    bcs a2_asset_not_packed
    ldx a2_asset_verify
    beq a2_pak_load_to_dest
    sta a2_pak_id
    jsr a2_clear_diag
    jsr a2_mli_begin
    lda a2_pak_id
    jsr a2_pak_open_seek
    bcs a2_asset_fail_end
    jsr a2i_close_open_ref
    bcs a2_asset_fail_end
    jmp a2_asset_done_ok

.label hal_storage_load = hal_asset_load

// ============================================================
// hal_asset_load_title — stream TITLE from MORIA8.PAK into aux MAP_BASE.
// MAP_BASE lives in AUXILIARY RAM on this platform and the MLI writes only
// main RAM, so the payload streams through a 256-byte main-RAM staging buffer
// and each chunk crosses via mmu_safe_map_write_ptr1 (RAMWRT writes-only
// switch, safe from resident code). zp_ptr1 is the aux destination; core ZP
// is already saved by the surrounding a2_mli_begin/end.
// Output: carry clear = success, carry set = failure (title falls back to
// the text title in title_screen.s).
// Cold and title-only (sole caller is in the TitleOverlay), so it rides that
// overlay to free resident Default bytes for chest look suffixes (step 14).
// ============================================================
.segment TitleOverlay
hal_asset_load_title:
    jsr a2_clear_diag
    jsr a2_mli_begin
    lda #A2_PAK_ENTRY_TITLE
    jsr a2_pak_open_seek
    bcc !seek_ok+
    jmp !fail_end+
!seek_ok:
    lda #<MAP_BASE
    sta zp_ptr1
    lda #>MAP_BASE
    sta zp_ptr1 + 1
    lda #HAL_STORAGE_PHASE_READ
    sta hal_storage_diag_phase
!chunk:
    lda a2_pak_len + 1
    bne !req_256+
    lda a2_pak_len
    bne !req_partial+
    jmp !close_done+
!req_partial:
    sta a2_rw_req
    lda #0
    sta a2_rw_req + 1
    beq !do_read+                   // A is 0
!req_256:
    lda #0
    sta a2_rw_req
    lda #1
    sta a2_rw_req + 1               // request 256
!do_read:
    lda #<a2_title_stage
    sta a2_rw_buf
    lda #>a2_title_stage
    sta a2_rw_buf + 1
    jsr a2i_read
    bcc !read_sub+
    jmp !close_fail+
!read_sub:
    sec
    lda a2_pak_len
    sbc a2_rw_trans
    sta a2_pak_len
    lda a2_pak_len + 1
    sbc a2_rw_trans + 1
    sta a2_pak_len + 1
!read_ok:
    lda a2_rw_trans + 1
    bne !full_chunk+                // 256 bytes transferred
    lda a2_rw_trans
    beq !close_done+                // defensive: no data with clear carry
    sta a2_tc
    ldy #0
!copy_partial:
    cpy a2_tc
    bcs !last_chunk+
    lda a2_title_stage,y
    jsr mmu_safe_map_write_ptr1
    iny
    jmp !copy_partial-
!full_chunk:
    ldy #0
!copy_full:
    lda a2_title_stage,y
    jsr mmu_safe_map_write_ptr1
    iny
    bne !copy_full-
    inc zp_ptr1 + 1                 // next aux page
    jmp !chunk-
!last_chunk:
!close_done:
    jsr a2i_close_open_ref
    bcs !fail_end+
    jsr a2_mli_end
    clc
    rts
!close_fail:
    pha
    jsr a2i_close_open_ref
    pla
!fail_end:
    jsr a2_mli_end
    jmp a2_map_error

// ============================================================
// a2_boot_preload_aux_lc — Cold boot preload (runs in TitleOverlay):
//   1. Zeroes persistent recall[RECALL_DATA_SIZE] in Aux LC Bank 1 ($D000-$D45B).
//   2. Reads standalone ITEM.CAT into A2_PLAY_SLOT_BASE ($7C00-$9D94), verifies
//      byte count and 'ITM2' magic, and copies to Aux LC High ($E000-$FD94).
// Uses A2_PLAY_SLOT_BASE before a2_require_play has ever loaded A2.PLAY.
// ============================================================
a2_boot_preload_aux_lc:
    // 1. Zero Aux LC Bank 1 recall[279] ($D000-$D45B).
    ldx #A2_LC_BOUNCE_SIZE - 1
    lda #0
!zero_bounce:
    sta A2_LC_BOUNCE,x
    dex
    bpl !zero_bounce-
    lda #A2_LC_BANK1
    sta A2_LC_ARG_BANK
    lda #A2_LC_DIR_WRITE
    sta A2_LC_ARG_DIR
    lda #<A2_LC_RECALL_BASE
    sta zp_ptr1
    lda #>A2_LC_RECALL_BASE
    sta zp_ptr1_hi
    lda #<RECALL_DATA_SIZE
    sta zp_temp0
    lda #>RECALL_DATA_SIZE
    sta zp_temp1
!zero_loop:
    jsr !calc_chunk+
    beq !load_item_cat+
    ldx zp_ptr1
    ldy zp_ptr1_hi
    jsr a2_aux_lc_bounce_xfer
    jsr !advance_dst+
    jmp !zero_loop-

!preload_mli_fail:
    jsr a2_mli_end
!preload_bad:
    lda #$ee
    jmp hal_platform_panic

!load_item_cat:
    lda #a2_item_cat_name_len
    ldx #<a2_item_cat_name
    ldy #>a2_item_cat_name
    jsr a2_mli_set_pathname
    jsr a2_clear_diag
    jsr a2_mli_begin
    lda #HAL_STORAGE_PHASE_OPEN
    sta hal_storage_diag_phase
    jsr a2i_open
    bcs !preload_mli_fail-
    lda a2_open_ref
    sta a2_rw_ref
    lda #<A2_PLAY_SLOT_BASE
    sta a2_rw_buf
    lda #>A2_PLAY_SLOT_BASE
    sta a2_rw_buf + 1
    lda #<ITMCAT_TOTAL_SIZE
    sta a2_rw_req
    lda #>ITMCAT_TOTAL_SIZE
    sta a2_rw_req + 1
    lda #HAL_STORAGE_PHASE_READ
    sta hal_storage_diag_phase
    jsr a2i_read
    php
    jsr a2i_close_open_ref
    plp
    bcs !preload_mli_fail-
    jsr a2_mli_end
    lda a2_rw_trans
    cmp #<ITMCAT_TOTAL_SIZE
    bne !preload_bad-
    lda a2_rw_trans + 1
    cmp #>ITMCAT_TOTAL_SIZE
    bne !preload_bad-
    lda A2_PLAY_SLOT_BASE
    cmp #$49                        // 'I'
    bne !preload_bad-
    lda A2_PLAY_SLOT_BASE + 1
    cmp #$54                        // 'T'
    bne !preload_bad-
    lda A2_PLAY_SLOT_BASE + 2
    cmp #$4d                        // 'M'
    bne !preload_bad-
    lda A2_PLAY_SLOT_BASE + 3
    cmp #$32                        // '2'
    bne !preload_bad-

    // 3. Copy ITEM.CAT ($7C00..) -> Aux LC High ($E000..$FD94).
    lda #A2_LC_BANK2
    sta A2_LC_ARG_BANK
    lda #A2_LC_DIR_WRITE
    sta A2_LC_ARG_DIR
    lda #<A2_PLAY_SLOT_BASE
    sta zp_ptr0
    lda #>A2_PLAY_SLOT_BASE
    sta zp_ptr0_hi
    lda #<A2_LC_ITEM_CAT_BASE
    sta zp_ptr1
    lda #>A2_LC_ITEM_CAT_BASE
    sta zp_ptr1_hi
    lda #<ITMCAT_TOTAL_SIZE
    sta zp_temp0
    lda #>ITMCAT_TOTAL_SIZE
    sta zp_temp1
!copy_loop:
    jsr !calc_chunk+
    beq !copy_done+
    tay
    dey
!fill_bounce:
    lda (zp_ptr0),y
    sta A2_LC_BOUNCE,y
    dey
    bpl !fill_bounce-
    lda a2_tc
    ldx zp_ptr1
    ldy zp_ptr1_hi
    jsr a2_aux_lc_bounce_xfer
    clc
    lda zp_ptr0
    adc a2_tc
    sta zp_ptr0
    bcc !src_nc+
    inc zp_ptr0_hi
!src_nc:
    jsr !advance_dst+
    jmp !copy_loop-
!copy_done:
    lda #0                          // keep A2.PLAY signature clear until loaded
    sta A2_PLAY_SLOT_BASE
    clc
    rts

// Output: A = a2_tc = min(16, zp_temp1:zp_temp0), Z=1 iff remaining == 0.
!calc_chunk:
    lda zp_temp1
    bne !use16+
    lda zp_temp0
    beq !done_chunk+
    cmp #A2_LC_BOUNCE_SIZE
    bcc !store_chunk+
!use16:
    lda #A2_LC_BOUNCE_SIZE
!store_chunk:
    sta a2_tc
!done_chunk:
    rts

!advance_dst:
    clc
    lda zp_ptr1
    adc a2_tc
    sta zp_ptr1
    bcc !dst_nc+
    inc zp_ptr1_hi
!dst_nc:
    sec
    lda zp_temp0
    sbc a2_tc
    sta zp_temp0
    bcs !rem_nc+
    dec zp_temp1
!rem_nc:
    rts

a2_item_cat_name:
    .byte $49,$54,$45,$4d,$2e,$43,$41,$54   // "ITEM.CAT"
.label a2_item_cat_name_len = * - a2_item_cat_name

a2_tc:            .byte 0
.segment Default
// Title-art staging shares the save-stream buffer: title loads, ON_LINE
// reports (disk_setup_a2.s), and save streams are never open concurrently.
// a2_probe_buf, a2_program_volume, and a2_save_volume live in $0301-$0328 (memory.s).
.label a2_title_stage = a2_ss_buf

// ============================================================
// hal_asset_close_channel — close any open file and restore default state.
// Asset loads above self-close; this is the defensive table-cleanup
// equivalent (CLOSE ref 0 = close all at the current level).
// ============================================================
hal_asset_close_channel:
    jsr a2_mli_begin
    lda #0
    sta a2_close_ref
    jsr a2i_close
    jsr a2_mli_end
    clc
    rts

// ============================================================
// Contract aliases into the shared save engine
// ============================================================
.label hal_storage_save_record = save_game
.label hal_storage_load_record = load_game

// ============================================================
// Platform-owned filename labels.
// Save/check/score/marker strings are byte-identical to the Commodore ports
// (PETSCII == ASCII for every byte used) so the shared save-slot menu's
// runtime mutation and offset asserts hold. ProDOS-illegal bytes never reach
// the MLI: a2_mli_set_pathname strips prefixes/suffixes.
// ============================================================

// Save-record filenames. "@0:" = replace, "0:" = read, ",S,W"/",S,R" = mode.
hal_storage_save_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $54, $48, $45, $2e, $47, $41, $4d, $45 // "THE.GAME"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_save_write_name_len = * - hal_storage_save_write_name
    .byte $57                                   // spare suffix byte for "THE.GAME2"
.label hal_storage_save_probe_name = hal_storage_save_write_name + 1
.label hal_storage_save_probe_name_len = hal_storage_save_write_name_len - 1

hal_storage_save_read_name:
    .byte $30, $3a                              // "0:"
    .byte $54, $48, $45, $2e, $47, $41, $4d, $45 // "THE.GAME"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_save_read_name_len = * - hal_storage_save_read_name
    .byte $52                                   // spare suffix byte for "THE.GAME2"

// High-score filenames (sole consumer core/score_io.s lives in DeathOverlay).
.segment DeathOverlay
hal_storage_score_read_name:
    .byte $30, $3a                              // "0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45 // "HALL.OF.FAME"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_score_read_name_len = * - hal_storage_score_read_name

hal_storage_score_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45 // "HALL.OF.FAME"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_score_write_name_len = * - hal_storage_score_write_name

hal_storage_score_scratch_name:
    .byte $53, $30, $3a                         // "S0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45 // "HALL.OF.FAME"
.label hal_storage_score_scratch_name_len = * - hal_storage_score_scratch_name
.segment Default

// Commodore drive-init command. Unused on ProDOS; exported for the contract.
hal_storage_init_command:
    .byte $49, $30                              // "I0"

// Save-disk marker bytes and filenames.
hal_storage_marker_magic:
    .byte $4d, $38, $53, $41, $56, $45          // "M8SAVE"
.label hal_storage_marker_magic_len = * - hal_storage_marker_magic

hal_storage_marker_read_name:
    .byte $30, $3a                              // "0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44 // "MORIA8.ID"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_marker_read_name_len = * - hal_storage_marker_read_name

hal_storage_marker_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44 // "MORIA8.ID"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_marker_write_name_len = * - hal_storage_marker_write_name

hal_storage_marker_scratch_name:
    .byte $53, $30, $3a                         // "S0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44 // "MORIA8.ID"
.label hal_storage_marker_scratch_name_len = * - hal_storage_marker_scratch_name

// Program-media probe file: the packed container on the game volume.
hal_storage_program_probe_name:
    .byte $4d,$4f,$52,$49,$41,$38,$2e,$50,$41,$4b // "MORIA8.PAK"
.label hal_storage_program_probe_name_len = * - hal_storage_program_probe_name
    .byte 0

// Title-art asset name (zero-terminated for display code).
hal_storage_title_name:
    .byte $54, $49, $54, $4c, $45               // "TITLE"
.label hal_storage_title_name_len = * - hal_storage_title_name
    .byte 0

#if !HAL_PLATFORM_MONSTER_CATALOG    // The catalog has no tier files
// Tier data filenames (zero-terminated for display code; lengths exclude the
// trailing zero per the storage-HAL data contract).
hal_storage_tier_1_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$2e,$31 // "MONSTER.DB.1"
.label hal_storage_tier_1_name_len = * - hal_storage_tier_1_name
    .byte 0
hal_storage_tier_2_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$2e,$32 // "MONSTER.DB.2"
.label hal_storage_tier_2_name_len = * - hal_storage_tier_2_name
    .byte 0
hal_storage_tier_3_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$2e,$33 // "MONSTER.DB.3"
.label hal_storage_tier_3_name_len = * - hal_storage_tier_3_name
    .byte 0
hal_storage_tier_4_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$2e,$34 // "MONSTER.DB.4"
.label hal_storage_tier_4_name_len = * - hal_storage_tier_4_name
    .byte 0

hal_storage_tier_name_lo:
    .byte <hal_storage_tier_1_name, <hal_storage_tier_2_name, <hal_storage_tier_3_name, <hal_storage_tier_4_name
hal_storage_tier_name_hi:
    .byte >hal_storage_tier_1_name, >hal_storage_tier_2_name, >hal_storage_tier_3_name, >hal_storage_tier_4_name
hal_storage_tier_name_len:
    .byte hal_storage_tier_1_name_len, hal_storage_tier_2_name_len, hal_storage_tier_3_name_len, hal_storage_tier_4_name_len
#endif

// Overlay asset filenames, indexed by overlay ID - 1 (common/overlay.s).
// IDs 1-11 are the shared classes (incl. OVL_CHEST, OVL_HOME); OVL.STORAGE (12)
// and OVL.TITLE (13) are the Apple II window-hosted classes appended at the end.
hal_storage_overlay_start_name:
    .byte $4f,$56,$4c,$2e,$53,$54,$41,$52,$54   // "OVL.START"
.label hal_storage_overlay_start_name_len = * - hal_storage_overlay_start_name
    .byte 0
hal_storage_overlay_town_name:
    .byte $4f,$56,$4c,$2e,$54,$4f,$57,$4e       // "OVL.TOWN"
.label hal_storage_overlay_town_name_len = * - hal_storage_overlay_town_name
    .byte 0
hal_storage_overlay_death_name:
    .byte $4f,$56,$4c,$2e,$44,$45,$41,$54,$48   // "OVL.DEATH"
.label hal_storage_overlay_death_name_len = * - hal_storage_overlay_death_name
    .byte 0
hal_storage_overlay_gen_name:
    .byte $4f,$56,$4c,$2e,$47,$45,$4e           // "OVL.GEN"
.label hal_storage_overlay_gen_name_len = * - hal_storage_overlay_gen_name
    .byte 0
hal_storage_overlay_help_name:
    .byte $4f,$56,$4c,$2e,$48,$45,$4c,$50       // "OVL.HELP"
.label hal_storage_overlay_help_name_len = * - hal_storage_overlay_help_name
    .byte 0
hal_storage_overlay_ui_name:
    .byte $4f,$56,$4c,$2e,$55,$49               // "OVL.UI"
.label hal_storage_overlay_ui_name_len = * - hal_storage_overlay_ui_name
    .byte 0
hal_storage_overlay_items_name:
    .byte $4f,$56,$4c,$2e,$49,$54,$45,$4d,$53   // "OVL.ITEMS"
.label hal_storage_overlay_items_name_len = * - hal_storage_overlay_items_name
    .byte 0
hal_storage_overlay_spell_name:
    .byte $4f,$56,$4c,$2e,$53,$50,$45,$4c,$4c // "OVL.SPELL"
.label hal_storage_overlay_spell_name_len = * - hal_storage_overlay_spell_name
    .byte 0
hal_storage_modal_misc_name:
    .byte $4f,$56,$4c,$2e,$4d,$4f,$44,$41,$4c   // "OVL.MODAL"
.label hal_storage_modal_misc_name_len = * - hal_storage_modal_misc_name
    .byte 0
hal_storage_overlay_chest_name:
    .byte $4f,$56,$4c,$2e,$43,$48,$45,$53,$54   // "OVL.CHEST"
.label hal_storage_overlay_chest_name_len = * - hal_storage_overlay_chest_name
    .byte 0
hal_storage_overlay_home_name:
    .byte $4f,$56,$4c,$2e,$48,$4f,$4d,$45       // "OVL.HOME"
.label hal_storage_overlay_home_name_len = * - hal_storage_overlay_home_name
    .byte 0
hal_storage_overlay_storage_name:
    .byte $4f,$56,$4c,$2e,$53,$54,$4f,$52,$41,$47,$45 // "OVL.STORAGE"
.label hal_storage_overlay_storage_name_len = * - hal_storage_overlay_storage_name
    .byte 0
hal_storage_overlay_title_name:
    .byte $4f,$56,$4c,$2e,$54,$49,$54,$4c,$45   // "OVL.TITLE"
.label hal_storage_overlay_title_name_len = * - hal_storage_overlay_title_name
    .byte 0

hal_storage_overlay_name_lo:
    .byte <hal_storage_overlay_start_name, <hal_storage_overlay_town_name, <hal_storage_overlay_death_name, <hal_storage_overlay_gen_name, <hal_storage_overlay_help_name, <hal_storage_overlay_ui_name, <hal_storage_overlay_items_name, <hal_storage_overlay_spell_name, <hal_storage_modal_misc_name, <hal_storage_overlay_chest_name, <hal_storage_overlay_home_name, <hal_storage_overlay_storage_name, <hal_storage_overlay_title_name
hal_storage_overlay_name_hi:
    .byte >hal_storage_overlay_start_name, >hal_storage_overlay_town_name, >hal_storage_overlay_death_name, >hal_storage_overlay_gen_name, >hal_storage_overlay_help_name, >hal_storage_overlay_ui_name, >hal_storage_overlay_items_name, >hal_storage_overlay_spell_name, >hal_storage_modal_misc_name, >hal_storage_overlay_chest_name, >hal_storage_overlay_home_name, >hal_storage_overlay_storage_name, >hal_storage_overlay_title_name
hal_storage_overlay_name_len:
    .byte hal_storage_overlay_start_name_len, hal_storage_overlay_town_name_len, hal_storage_overlay_death_name_len, hal_storage_overlay_gen_name_len, hal_storage_overlay_help_name_len, hal_storage_overlay_ui_name_len, hal_storage_overlay_items_name_len, hal_storage_overlay_spell_name_len, hal_storage_modal_misc_name_len, hal_storage_overlay_chest_name_len, hal_storage_overlay_home_name_len, hal_storage_overlay_storage_name_len, hal_storage_overlay_title_name_len

// ============================================================
// Compile-time validation
// ============================================================
.const A2_OVERLAY_TABLE_COUNT = * - hal_storage_overlay_name_len
.assert "Overlay table matches hal_platform_overlay_count", A2_OVERLAY_TABLE_COUNT, hal_platform_overlay_count
.assert "Save read name keeps slot-menu digit offset 10", hal_storage_save_read_name_len - 4, 10
.assert "Save write name keeps slot-menu digit offset 11", hal_storage_save_write_name_len - 4, 11
.assert "Probe filename tracks write filename without overwrite marker", hal_storage_save_probe_name_len, hal_storage_save_write_name_len - 1
.assert "Marker magic is 6 bytes", hal_storage_marker_magic_len, 6
.assert "Save basename fits a ProDOS name element", 8 <= 15, true
.assert "Score basename fits a ProDOS name element", 12 <= 15, true
.assert "Marker basename fits a ProDOS name element", 9 <= 15, true
#if !HAL_PLATFORM_MONSTER_CATALOG    // The catalog has no tier files
.assert "Tier basename fits a ProDOS name element", hal_storage_tier_1_name_len <= 15, true
#endif
.assert "Longest overlay basename fits a ProDOS name element", hal_storage_overlay_storage_name_len <= 15, true
.assert "MLI io_buffer is page aligned", <A2_MLI_IO_BUFFER, 0
.assert "MLI pathname buffer fits before Aux LC bounce", A2_MLI_PATHNAME + 1 + A2_MLI_PATHNAME_CAPACITY <= A2_LC_BOUNCE, true
.assert "MLI pathname buffer holds a max pathname", A2_MLI_PATHNAME + 1 + A2_MLI_PATHNAME_CAPACITY <= $0300, true
.assert "PAK workspace fits platform ZP before thunks", a2_pak_len + 1 < A2_ZP_THUNK_READ_P0 && a2_pak_id > save_slot_index, true
.assert "Save volume pathname (slash + 15 + slash + 15) fits", 17 + 15 <= A2_MLI_PATHNAME_CAPACITY, true

// ============================================================
// a2_disk_setup_run moved to disk_setup_a2.s (OVL.STORAGE): the guided
// Commodore-parity Disk Setup coordinator + UI.
// ============================================================