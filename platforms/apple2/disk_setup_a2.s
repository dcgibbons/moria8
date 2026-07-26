#importonce
// disk_setup_a2.s — Apple II guided Disk Setup (Commodore parity).
//
// Lives in OVL.STORAGE next to save.s. Coordinator + display/input UI in one
// file; all disk transactions go through the resident storage_mli.s helpers
// (ON_LINE scans, marker probe/init, pathname volume routing). Flow mirrors
// platforms/commodore/common/disk_setup_banked.s with ProDOS volume names in
// place of device numbers:
//   menu (one drive (swap) / pick save drive / done) -> prepare (insert
//   prompts, program-media rejection, marker probe, init prompt, init-fail
//   detail) -> commit (disk_setup_done = hal_storage_disk_setup_done_value).
// One-drive swap mode (A2_DISK_MODE_SWAP) additionally restores the program
// disk before returning; runtime swap prompts live in main.s
// (disk_prompt_save / disk_prompt_game).

// ------------------------------------------------------------
// UI mailbox (Apple-local; values mirror the Commodore DISK_UI_* consts)
// ------------------------------------------------------------
.const A2DS_ACT_MENU           = 0
.const A2DS_ACT_INSERT_DISK    = 2
.const A2DS_ACT_INIT_PROMPT    = 3
.const A2DS_ACT_SHOW_NO_DEVICE = 5
.const A2DS_ACT_SHOW_PROGRAM   = 6
.const A2DS_ACT_SHOW_INIT_FAIL = 7
.const A2DS_ACT_PICK_VOLUME    = 8
.const A2DS_ACT_INSERT_PROGRAM = 9

.const A2DS_RES_OK     = 0
.const A2DS_RES_CANCEL = 1
.const A2DS_RES_ONE_DRIVE   = 2
.const A2DS_RES_PICK   = 3
.const A2DS_RES_RESCAN = 4
.const A2DS_RES_YES    = 5
.const A2DS_RES_NO     = 6

a2ds_ui_result:  .byte 0
a2ds_ui_value:   .byte 0
a2ds_row_idx:    .byte 0
a2ds_entry_off:  .byte 0
a2ds_pick_count: .byte 0
a2ds_want_unit:  .byte 0
a2ds_pick_buf:   .fill 1 + 9 * 17, 0
a2ds_unit_vol:   .fill 16, 0        // volume found by a2_volume_on_unit

.const A2DS_TITLE_COL  = (SCREEN_COLS - 10) / 2
.const A2DS_LINE_COL   = (SCREEN_COLS - 24) / 2
.const A2DS_PRESS_COL  = (SCREEN_COLS - 13) / 2

// ============================================================
// Volume management. ProDOS addresses disks by volume name: ON_LINE reports
// every mounted volume with its unit, and an absolute "/VOLUME/FILE"
// pathname resolves against whichever unit holds that volume. The game's own
// /RAM volume (unit $B0, aux RAM) is never a candidate.
// (Overlay-hosted: resident space is byte-tight and only the Disk Setup
// coordinator + media prompts enumerate volumes.)
// ============================================================

a2ds_online_params:
    .byte 2
a2ds_online_unit: .byte 0           // 0 = report all units
    .word a2_title_stage            // 256-byte volume report buffer

a2ds_prefix_params:
    .byte 1
    .word A2_MLI_PATHNAME

a2ds_list_count: .byte 0

a2i_on_line:
    jsr A2_MLI
    .byte A2_MLI_ON_LINE
    .word a2ds_online_params
    rts

a2i_get_prefix:
    jsr A2_MLI
    .byte A2_MLI_GET_PREFIX
    .word a2ds_prefix_params
    rts

// a2_scan_volume — is the named volume online?
// Input: X = name ptr lo, Y = name ptr hi (ProDOS len-prefixed: byte 0 =
// length, bytes 1-15 = uppercase name).
// Output: carry clear + A = unit byte (drive/slot); carry set = not mounted.
// Clobbers a2_nc_ptr/a2_nc_len/a2_nc_tmp and the ON_LINE report buffer.
a2_scan_volume:
    stx a2_nc_ptr
    sty a2_nc_ptr + 1
    ldy #0
    lda (a2_nc_ptr),y
    bne !go+
    sec                             // nameless selection is never "online"
    rts
!go:
    jsr a2_mli_begin
    lda #0
    sta a2ds_online_unit
    jsr a2i_on_line
    bcs !fail+
    lda #0
    sta a2_nc_tmp                   // entry offset (16 bytes per entry)
!entry:
    ldx a2_nc_tmp
    lda a2_title_stage,x            // unit nibble + name length / end / error
    beq !fail+                      // 0 = end of report
    tay
    and #$f0
    cmp #$b0                        // /RAM (slot 3 drive 2) is never save media
    beq !next+
    tya
    and #$0f
    cmp #$0f                        // low nibble $f = error entry, not a volume
    beq !next+
    sta a2_nc_len                   // entry name length
    ldy #0
    cmp (a2_nc_ptr),y               // name lengths must match
    bne !next+
    inx                             // X walks entry name bytes
    ldy #1
!cmp_name:
    lda a2_title_stage,x
    cmp (a2_nc_ptr),y
    bne !next+
    inx
    iny
    cpy a2_nc_len
    beq !cmp_name-                  // y == len: last name byte still to check
    bcs !found+                     // y > len: all bytes matched
    jmp !cmp_name-
!found:
    ldx a2_nc_tmp
    lda a2_title_stage,x
    and #$f0                        // unit byte (drive/slot nibbles)
    clc
    jsr a2_mli_end
    rts
!next:
    lda a2_nc_tmp
    clc
    adc #16
    sta a2_nc_tmp
    bcc !entry-
!fail:
    sec
    jsr a2_mli_end
    rts

// Poll the configured volumes. On success the matching device byte is
// refreshed with the unit the volume is currently mounted on (it can move
// between swaps). Output: carry clear = online, carry set = not mounted.
a2_save_volume_online:
    ldx #<a2_save_volume
    ldy #>a2_save_volume
    jsr a2_scan_volume
    bcs !out+
    sta save_device
    clc
!out:
    rts

// a2_volume_on_unit — what is mounted on the given unit?
// Input: A = unit byte (drive/slot nibbles).
// Output: A = 0 nothing mounted, 1 = ProDOS volume (len-prefixed name copied
//         to a2ds_unit_vol), 2 = unreadable media (ON_LINE error entry, e.g.
//         an unformatted or non-ProDOS disk).
a2_volume_on_unit:
    sta a2ds_want_unit
    jsr a2_mli_begin
    lda #0
    sta a2ds_online_unit
    jsr a2i_on_line
    bcs !none+
    lda #0
    sta a2_nc_tmp                   // entry offset
!entry:
    ldx a2_nc_tmp
    lda a2_title_stage,x
    beq !none+                      // 0 = end of report
    tay
    and #$f0
    cmp #$b0                        // skip /RAM
    beq !next+
    cmp a2ds_want_unit
    bne !next+
    tya
    and #$0f
    beq !bad+                       // zero-length name: not a usable volume
    cmp #$0f                        // error entry: media present but unreadable
    beq !bad+
    bne !good+
!bad:
    lda #2
    jmp !out+
!good:
    sta a2ds_unit_vol               // byte 0 = name length
    ldy #0
!copy:
    inx
    iny
    lda a2_title_stage,x
    sta a2ds_unit_vol,y
    cpy #15
    bcc !copy-
    lda #1
    jmp !out+
!bad:
    lda #2
    jmp !out+
!next:
    lda a2_nc_tmp
    clc
    adc #16
    sta a2_nc_tmp
    bcc !entry-
!none:
    lda #0
!out:
    jsr a2_mli_end
    rts

a2_program_volume_online:
    ldx #<a2_program_volume
    ldy #>a2_program_volume
    jsr a2_scan_volume
    bcs !out+
    sta program_device
    clc
!out:
    rts

// a2_init_program_volume — discover the boot volume once per session:
// GET_PREFIX supplies "/VOL[/subdir...]" (ProDOS sets the prefix to the boot
// volume); the first path element is the program volume name; ON_LINE
// resolves its unit. Idempotent. Output: carry clear = volume known.
a2_init_program_volume:
    lda a2_program_volume
    bne !done+                      // already discovered
    jsr a2_mli_begin
    jsr a2i_get_prefix
    bcs !fail_mli+
    jsr a2_mli_end
    lda A2_MLI_PATHNAME + 1
    cmp #$2f                        // '/'
    bne !fail+
    ldx #0
    ldy #2
!copy:
    cpy A2_MLI_PATHNAME
    beq !element+                   // y == length: last character
    bcs !term+
!element:
    lda A2_MLI_PATHNAME,y
    cmp #$2f                        // '/': subdirectory boundary
    beq !term+
    sta a2_program_volume + 1,x
    inx
    iny
    cpx #15
    bcc !copy-
!term:
    stx a2_program_volume
    cpx #0
    beq !fail+
    jsr a2_program_volume_online    // also records the unit when mounted
    clc
    rts
!done:
    clc
    rts
!fail_mli:
    jsr a2_mli_end
!fail:
    sec
    rts

// a2_list_volumes — copy the ON_LINE report into a caller buffer for the
// pick list. Buffer layout: byte 0 = count, then per entry 17 bytes: unit,
// name length, 15 name bytes (space padded). Max 9 entries. Unreadable
// media (error entries, zero-length names) is listed with length $ff so the
// player can select the drive anyway (Commodore parity).
// Input: X = buffer lo, Y = buffer hi. Output: buffer + A = count.
a2_list_volumes:
    stx a2_nc_ptr
    sty a2_nc_ptr + 1
    jsr a2_mli_begin
    lda #0
    sta a2ds_online_unit
    jsr a2i_on_line
    bcc !report+
    jmp !fail+
!report:
    lda #0
    sta a2_nc_tmp                   // entry offset
    sta a2ds_list_count
    ldy #1                          // buffer write index
!entry:
    ldx a2_nc_tmp
    lda a2_title_stage,x
    bne !more+
    jmp !done+                      // 0 = end of report
!more:
    sta a2_nc_len                   // byte 0: unit nibble + name length
    and #$f0
    cmp #$b0                        // skip /RAM
    beq !next+
    lda a2_nc_len
    and #$0f
    beq !unreadable+                // zero-length name: unreadable media
    cmp #$0f                        // low nibble $f = error entry
    beq !unreadable+
    lda a2_nc_len
    and #$f0
    sta (a2_nc_ptr),y               // unit
    iny
    lda a2_nc_len
    and #$0f
    sta (a2_nc_ptr),y               // name length
    iny
    lda a2_nc_len
    and #$0f
    sta a2_nc_len                   // name length (1-15)
    inx                             // X walks entry name bytes
    lda #1
    sta a2ds_online_unit            // i
!name:
    lda a2ds_online_unit
    cmp a2_nc_len
    bcc !copy+
    beq !copy+
    lda #$20                        // pad to 15 bytes
    bne !put+
!copy:
    lda a2_title_stage,x
!put:
    sta (a2_nc_ptr),y
    inx
    iny
    inc a2ds_online_unit
    lda a2ds_online_unit
    cmp #16
    bcc !name-
    jmp !count+
!unreadable:
    // List unreadable media as a selectable entry (len byte $ff): Commodore
    // lets the player pick a drive regardless of what is in it, and the
    // prepare flow turns this into an honest init-offer/failure.
    lda a2_nc_len
    and #$f0
    sta (a2_nc_ptr),y               // unit
    iny
    lda #$ff
    sta (a2_nc_ptr),y               // $ff = unreadable marker
    iny
    lda #1
    sta a2ds_online_unit
    lda #$20
!pad:
    sta (a2_nc_ptr),y
    iny
    inc a2ds_online_unit
    lda a2ds_online_unit
    cmp #16
    bcc !pad-
!count:
    inc a2ds_list_count
    lda a2ds_list_count
    cmp #9
    bcs !done+
!next:
    lda a2_nc_tmp
    clc
    adc #16
    sta a2_nc_tmp
    bcs !done+
    jmp !entry-
!done:
    ldy #0
    lda a2ds_list_count
    sta (a2_nc_ptr),y
    clc
    jsr a2_mli_end
    lda a2ds_list_count
    rts
!fail:
    ldy #0
    lda #0
    sta (a2_nc_ptr),y
    clc
    jsr a2_mli_end
    lda #0
    rts

// a2_print_volume — print "/NAME" at the current cursor.
// Input: X = name ptr lo, Y = name ptr hi (len-prefixed).
a2_print_volume:
    stx a2_nc_ptr
    sty a2_nc_ptr + 1
    ldy #0
    lda (a2_nc_ptr),y
    sta a2_nc_len
    lda #$2f                        // '/'
    jsr hal_screen_put_char
    ldy #1
!loop:
    cpy a2_nc_len
    beq !char+
    bcs !done+
!char:
    lda (a2_nc_ptr),y
    sty a2_nc_tmp                   // hal_screen_put_char may clobber Y
    jsr hal_screen_put_char
    ldy a2_nc_tmp
    iny
    jmp !loop-
!done:
    rts

// ============================================================
// a2ds_ui and the coordinator below handle every Disk Setup screen. The
// runtime swap prompts (disk_prompt_save / disk_prompt_game) are resident in
// main.s like the Commodore originals, since callers run with arbitrary
// overlays live.
// ============================================================

.macro A2DSPrint(row, col, label) {
    ldx #row
    ldy #col
    lda #<label
    sta zp_ptr0
    lda #>label
    jsr a2ds_print_loaded
}

// ============================================================
// a2_disk_setup_run — guided setup entry (title 'D', implicit before load /
// save / game-over when disk_setup_done == 0). Strict cross-port parity:
// saves never live on the game disk; the player either shares one drive
// (swap) or picks a save volume on another unit.
// Output: carry clear = setup committed, carry set = cancelled/failed.
// ============================================================
a2_disk_setup_run:
    jsr a2_init_program_volume
    bcs !fail+
    lda a2_save_volume
    bne !menu+                      // keep an earlier selection
    lda save_device
    bne !menu+
    jsr a2ds_select_one_drive       // default: share the program drive
!menu:
    lda #A2DS_ACT_MENU
    jsr a2ds_ui
    lda a2ds_ui_result
    cmp #A2DS_RES_ONE_DRIVE
    beq !one_drive+
    cmp #A2DS_RES_PICK
    beq !pick+
    cmp #A2DS_RES_OK
    beq !done+
    jmp !fail+                      // Q) Back
!one_drive:
    jsr a2ds_select_one_drive
    jmp !menu-
!pick:
    jsr a2ds_pick_volume
    jmp !menu-
!done:
    jsr a2ds_compute_mode
    jsr a2_disk_prepare_selected
    bcs !menu-
    clc
    rts
!fail:
    sec
    rts

// One-drive selection: saves will go to a separate disk swapped into the
// program drive. The volume name is unknown until the disk is inserted
// (prepare adopts it), so the selection is nameless.
a2ds_select_one_drive:
    lda program_device
    sta save_device
    lda #0
    sta a2_save_volume
    rts

// disk_mode: 3 = save volume shares the program unit (one-drive swap),
// 2 = save volume on another unit (two-drive).
a2ds_compute_mode:
    lda save_device
    cmp program_device
    bne !two+
    lda #A2_DISK_MODE_SWAP
    bne !store+
!two:
    lda #A2_DISK_MODE_TWO_DRIVE
!store:
    sta disk_mode
    rts

// ============================================================
// a2ds_pick_volume — enumerate mounted volumes and let the player choose.
// Output: carry clear = save_volume/save_device updated, carry set = backed
// out (menu re-entry).
// ============================================================
a2ds_pick_volume:
!rescan:
    ldx #<a2ds_pick_buf
    ldy #>a2ds_pick_buf
    jsr a2_list_volumes
    sta a2ds_pick_count
    bne !show+
    lda #A2DS_ACT_SHOW_NO_DEVICE
    jsr a2ds_ui
    sec
    rts
!show:
    lda #A2DS_ACT_PICK_VOLUME
    jsr a2ds_ui
    lda a2ds_ui_result
    cmp #A2DS_RES_RESCAN
    beq !rescan-
    cmp #A2DS_RES_OK
    bne !cancel+
    // copy the picked entry: unit -> save_device, name -> save_volume
    lda a2ds_ui_value
    asl                             // x 17
    asl
    asl
    asl
    clc
    adc a2ds_ui_value
    tax                             // entry offset within a2ds_pick_buf + 1
    lda a2ds_pick_buf + 1,x
    sta save_device
    lda a2ds_pick_buf + 2,x         // name length ($ff = unreadable media)
    cmp #$ff
    bne !named+
    lda #0
    sta a2_save_volume              // no name: prepare offers init, which
    clc                             // fails honestly on unreadable media
    rts
!named:
    ldy #0
!copy:
    lda a2ds_pick_buf + 2,x
    sta a2_save_volume,y
    inx
    iny
    cpy #16
    bcc !copy-
    clc
    rts
!cancel:
    sec
    rts

// ============================================================
// a2_disk_prepare_selected — validate/prepare the configured save media.
// Also the wrong-media recovery entry (tramp_disk_prepare_selected).
// When the configured save volume is not mounted, the save unit is examined
// (Commodore semantics): the program disk is rejected, any other ProDOS
// volume is adopted as the new save volume, and unreadable media (blank /
// non-ProDOS) goes straight to the init offer, whose init fails honestly
// with the classified detail line. Output: carry clear = media ready +
// disk_setup_done set; carry set = player declined (or init failed and
// dismissed).
// ============================================================
a2_disk_prepare_selected:
!wait_save:
    jsr a2_save_volume_online
    bcs !not_online+
    // The save volume is online; it must never be the program disk.
    ldx #0
!cmp_sel:
    lda a2_save_volume,x
    cmp a2_program_volume,x
    bne !marker_probe+
    inx
    cpx #16
    bcc !cmp_sel-
    lda #A2DS_ACT_SHOW_PROGRAM
    jsr a2ds_ui
    jmp !fail+
!not_online:
    // The configured save volume is not mounted. Like the Commodore flow,
    // look at whatever is actually on the save unit instead of looping on
    // an exact name match: the program disk is rejected, any other ProDOS
    // volume is adopted (Commodore probes whatever is inserted), and
    // unreadable media goes straight to the init offer, where init fails
    // honestly with the classified detail line. Rejection alternates with
    // the insert prompt, which cancels to the menu on Q.
    lda save_device
    jsr a2_volume_on_unit
    cmp #1
    beq !have_volume+
    cmp #2
    beq !init_offer+
    lda disk_mode                   // nothing on the unit: in swap mode the
    cmp #A2_DISK_MODE_SWAP          // player may have re-inserted the game disk
    bne !insert+
    jsr a2_program_volume_online
    bcs !insert+
    lda #A2DS_ACT_SHOW_PROGRAM
    jsr a2ds_ui
!insert:
    lda #A2DS_ACT_INSERT_DISK
    jsr a2ds_ui
    lda a2ds_ui_result
    cmp #A2DS_RES_CANCEL
    beq !fail+
    jmp !wait_save-
!have_volume:
    // A ProDOS volume sits on the save unit; the game disk may not hold
    // saves.
    ldx #0
!cmp_prog:
    lda a2ds_unit_vol,x
    cmp a2_program_volume,x
    bne !adopt+
    inx
    cpx #16
    bcc !cmp_prog-
    lda #A2DS_ACT_SHOW_PROGRAM
    jsr a2ds_ui
    jmp !insert-
!adopt:
    ldx #0
!copy:
    lda a2ds_unit_vol,x
    sta a2_save_volume,x
    inx
    cpx #16
    bcc !copy-
!marker_probe:
    jsr hal_storage_marker_present
    bcc !commit+
!init_offer:
    lda #A2DS_ACT_INIT_PROMPT
    jsr a2ds_ui
    lda a2ds_ui_result
    cmp #A2DS_RES_YES
    bne !fail+
    lda a2_save_volume
    beq !init_fail+                 // unreadable media: init cannot succeed;
                                    // never let it fall back to a relative
                                    // pathname on the program volume
    jsr hal_storage_marker_init
    bcc !commit+
!init_fail:
    lda #A2DS_ACT_SHOW_INIT_FAIL
    jsr a2ds_ui
!fail:
    sec
    rts
!commit:
    lda #hal_storage_disk_setup_done_value
    sta disk_setup_done
    lda disk_mode
    cmp #A2_DISK_MODE_SWAP
    bne !ok+
!restore:                           // leave the program disk mounted
    jsr a2_program_volume_online
    bcc !ok+
    lda #A2DS_ACT_INSERT_PROGRAM
    jsr a2ds_ui
    jmp !restore-
!ok:
    clc
    rts

// ============================================================
// UI layer (display/input only)
// ============================================================
a2ds_print_loaded:
    sta zp_ptr0_hi
    stx zp_cursor_row
    sty zp_cursor_col
    jmp hal_screen_put_string

a2ds_ui:
    cmp #A2DS_ACT_MENU
    bne !n0+
    jmp a2ds_menu
!n0:
    cmp #A2DS_ACT_PICK_VOLUME
    bne !n1+
    jmp a2ds_pick
!n1:
    cmp #A2DS_ACT_INSERT_DISK
    bne !n2+
    jmp a2ds_insert_disk
!n2:
    cmp #A2DS_ACT_INSERT_PROGRAM
    bne !n3+
    jmp a2ds_insert_program
!n3:
    cmp #A2DS_ACT_INIT_PROMPT
    bne !n4+
    jmp a2ds_init_prompt
!n4:
    cmp #A2DS_ACT_SHOW_NO_DEVICE
    bne !n5+
    jmp a2ds_no_device
!n5:
    cmp #A2DS_ACT_SHOW_PROGRAM
    bne !n6+
    jmp a2ds_program_disk
!n6:
    cmp #A2DS_ACT_SHOW_INIT_FAIL
    bne !n7+
    jmp a2ds_init_fail
!n7:
    lda #A2DS_RES_CANCEL
    sta a2ds_ui_result
    rts

a2ds_menu:
    jsr ui_clear_full_screen_safe
    lda #COL_WHITE
    sta zp_text_color
    :A2DSPrint(0, A2DS_TITLE_COL, a2ds_title_str)
    :A2DSPrint(2, A2DS_LINE_COL, a2ds_program_str)
    ldx #<a2_program_volume
    ldy #>a2_program_volume
    jsr a2_print_volume
    :A2DSPrint(3, A2DS_LINE_COL, a2ds_save_str)
    lda a2_save_volume
    beq !save_unit+
    ldx #<a2_save_volume
    ldy #>a2_save_volume
    jsr a2_print_volume
    jmp !save_done+
!save_unit:                             // nameless one-drive selection:
    lda save_device                     // show where the save disk will go
    jsr a2ds_print_unit
!save_done:
    :A2DSPrint(5, A2DS_LINE_COL, a2ds_one_drive_str)
    :A2DSPrint(6, A2DS_LINE_COL, a2ds_pick_drive_str)
    :A2DSPrint(7, A2DS_LINE_COL, a2ds_done_str)
    :A2DSPrint(8, A2DS_LINE_COL, a2ds_back_str)
!key:
    jsr hal_input_get_key
    cmp #$31                        // '1'
    bne !not1+
    lda #A2DS_RES_ONE_DRIVE
    bne !out+
!not1:
    cmp #$32                        // '2'
    bne !not2+
    lda #A2DS_RES_PICK
    bne !out+
!not2:
    cmp #$33                        // '3'
    bne !not3+
    lda #A2DS_RES_OK
    jmp !out+
!not3:
    cmp #$51                        // 'Q'
    bne !key-
    lda #A2DS_RES_CANCEL
!out:
    sta a2ds_ui_result
    rts

a2ds_pick:
    jsr ui_clear_full_screen_safe
    lda #COL_WHITE
    sta zp_text_color
    :A2DSPrint(0, A2DS_TITLE_COL, a2ds_title_str)
    lda #0
    sta a2ds_row_idx
!row:
    lda a2ds_row_idx
    cmp a2ds_pick_count
    bcs !hint+
    clc
    adc #2
    sta zp_cursor_row
    lda #A2DS_LINE_COL
    sta zp_cursor_col
    lda a2ds_row_idx
    asl                             // x 17
    asl
    asl
    asl
    clc
    adc a2ds_row_idx
    sta a2ds_entry_off
    lda a2ds_row_idx
    clc
    adc #$31                        // '1' + i
    jsr hal_screen_put_char
    lda #$29                        // ')'
    jsr hal_screen_put_char
    lda #$20                        // ' '
    jsr hal_screen_put_char
    lda a2ds_entry_off
    tax
    lda a2ds_pick_buf + 2,x         // name length ($ff = unreadable)
    cmp #$ff
    bne !named+
    lda #<a2ds_not_prodos_str
    sta zp_ptr0
    lda #>a2ds_not_prodos_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    jmp !unit+
!named:
    txa
    clc
    adc #<(a2ds_pick_buf + 2)       // len-prefixed name at entry + 1
    tax
    lda #>(a2ds_pick_buf + 2)
    adc #0
    tay
    jsr a2_print_volume
!unit:
    ldx a2ds_entry_off
    lda a2ds_pick_buf + 1,x         // unit
    jsr a2ds_print_unit
    inc a2ds_row_idx
    jmp !row-
!hint:
    :A2DSPrint(12, A2DS_LINE_COL, a2ds_rescan_str)
!key:
    jsr hal_input_get_key
    cmp #$51                        // 'Q'
    bne !nq+
    lda #A2DS_RES_CANCEL
    bne !out+
!nq:
    cmp #$52                        // 'R'
    bne !nr+
    lda #A2DS_RES_RESCAN
    bne !out+
!nr:
    sec
    sbc #$31                        // '1' -> 0-based index
    bcc !key-
    cmp a2ds_pick_count
    bcs !key-
    sta a2ds_ui_value
    lda #A2DS_RES_OK
!out:
    sta a2ds_ui_result
    rts

// A = ProDOS unit byte; prints " (S<slot>,D<drive>)" at the cursor.
a2ds_print_unit:
    pha
    lda #$20                        // ' '
    jsr hal_screen_put_char
    lda #$28                        // '('
    jsr hal_screen_put_char
    lda #$53                        // 'S'
    jsr hal_screen_put_char
    pla
    pha
    lsr
    lsr
    lsr
    lsr
    and #$07
    ora #$30
    jsr hal_screen_put_char
    lda #$2c                        // ','
    jsr hal_screen_put_char
    lda #$44                        // 'D'
    jsr hal_screen_put_char
    pla
    asl                             // carry = drive bit
    lda #$31                        // '1' + carry
    adc #0
    jsr hal_screen_put_char
    lda #$29                        // ')'
    jsr hal_screen_put_char
    rts

a2ds_insert_disk:
    jsr ui_clear_full_screen_safe
    lda #COL_WHITE
    sta zp_text_color
    :A2DSPrint(0, A2DS_TITLE_COL, a2ds_title_str)
    :A2DSPrint(3, A2DS_LINE_COL, ds_save_str)
    ldx #<a2_save_volume
    ldy #>a2_save_volume
    jsr a2_print_volume
    lda save_device
    beq !wait+
    jsr a2ds_print_unit
!wait:
    :A2DSPrint(6, A2DS_LINE_COL, a2ds_insert_hint_str)
!key:
    jsr input_get_modal_dismiss_key
    cmp #$51                        // 'Q'
    beq !cancel+
    cmp #$1b                        // ESC
    bne !not_q+
!cancel:
    lda #A2DS_RES_CANCEL
    sta a2ds_ui_result
    rts
!not_q:
    lda #A2DS_RES_OK
    sta a2ds_ui_result
    rts

a2ds_insert_program:
    jsr ui_clear_full_screen_safe
    lda #COL_WHITE
    sta zp_text_color
    :A2DSPrint(0, A2DS_TITLE_COL, a2ds_title_str)
    :A2DSPrint(3, A2DS_LINE_COL, ds_game_str)
    ldx #<a2_program_volume
    ldy #>a2_program_volume
    jsr a2_print_volume
    :A2DSPrint(6, A2DS_PRESS_COL, a2ds_press_key_str)
    jsr input_get_modal_dismiss_key
    lda #A2DS_RES_OK
    sta a2ds_ui_result
    rts

a2ds_init_prompt:
    jsr ui_clear_full_screen_safe
    lda #COL_WHITE
    sta zp_text_color
    :A2DSPrint(0, A2DS_TITLE_COL, a2ds_title_str)
    :A2DSPrint(3, A2DS_LINE_COL, a2ds_no_marker_str)
    :A2DSPrint(5, A2DS_LINE_COL, a2ds_init_prompt_str)
!key:
    jsr input_get_modal_dismiss_key
    cmp #$59                        // 'Y'
    beq !yes+
    cmp #$4e                        // 'N'
    bne !key-
    lda #A2DS_RES_NO
    bne !out+
!yes:
    lda #A2DS_RES_YES
!out:
    sta a2ds_ui_result
    rts

a2ds_no_device:
    jsr ui_clear_full_screen_safe
    lda #COL_WHITE
    sta zp_text_color
    :A2DSPrint(0, A2DS_TITLE_COL, a2ds_title_str)
    :A2DSPrint(3, A2DS_LINE_COL, a2ds_no_device_str)
    :A2DSPrint(5, A2DS_PRESS_COL, a2ds_press_key_str)
    jsr input_get_modal_dismiss_key
    lda #A2DS_RES_CANCEL
    sta a2ds_ui_result
    rts

a2ds_program_disk:
    jsr ui_clear_full_screen_safe
    lda #COL_WHITE
    sta zp_text_color
    :A2DSPrint(0, A2DS_TITLE_COL, a2ds_title_str)
    :A2DSPrint(3, A2DS_LINE_COL, a2ds_program_disk_str)
    :A2DSPrint(5, A2DS_PRESS_COL, a2ds_press_key_str)
    jsr input_get_modal_dismiss_key
    lda #A2DS_RES_CANCEL
    sta a2ds_ui_result
    rts

a2ds_init_fail:
    jsr ui_clear_full_screen_safe
    lda #COL_WHITE
    sta zp_text_color
    :A2DSPrint(0, A2DS_TITLE_COL, a2ds_title_str)
    :A2DSPrint(3, A2DS_LINE_COL, a2ds_init_fail_str)
    jsr hal_storage_setup_status
    cmp #HAL_STORAGE_STATUS_WRITE_PROTECTED
    bne !check_full+
    :A2DSPrint(4, A2DS_LINE_COL, a2ds_wp_str)
    jmp !wait+
!check_full:
    cmp #HAL_STORAGE_STATUS_DISK_FULL
    bne !check_ready+
    :A2DSPrint(4, A2DS_LINE_COL, a2ds_full_str)
    jmp !wait+
!check_ready:
    cmp #HAL_STORAGE_STATUS_NO_DEVICE
    beq !not_ready+
    cmp #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    bne !generic+
!not_ready:
    :A2DSPrint(4, A2DS_LINE_COL, a2ds_not_ready_str)
    jmp !wait+
!generic:
    :A2DSPrint(4, A2DS_LINE_COL, a2ds_generic_str)
!wait:
    :A2DSPrint(6, A2DS_PRESS_COL, a2ds_press_key_str)
    jsr input_get_modal_dismiss_key
    lda #A2DS_RES_CANCEL
    sta a2ds_ui_result
    rts

a2ds_title_str:       .text "Disk Setup" ; .byte 0
a2ds_program_str:     .text "Program: " ; .byte 0
a2ds_save_str:        .text "Save:    " ; .byte 0
a2ds_one_drive_str:   .text "1) One drive (swap)" ; .byte 0
a2ds_pick_drive_str:  .text "2) Pick save drive" ; .byte 0
a2ds_done_str:        .text "3) Done" ; .byte 0
a2ds_back_str:        .text "Q) Back" ; .byte 0
a2ds_rescan_str:      .text "R) Rescan  Q) Back" ; .byte 0
a2ds_not_prodos_str:  .text "<not ProDOS>" ; .byte 0
a2ds_insert_hint_str: .text "Press any key  Q) Back" ; .byte 0
// Local copy of the game_loop.s text; the shared press_key_str lives in the
// play slot, which is not loaded when Disk Setup runs at title.
a2ds_press_key_str:   .text "Press any key" ; .byte 0
a2ds_no_marker_str:   .text "No Save Disk marker found." ; .byte 0
a2ds_init_prompt_str: .text "Initialize this disk? (Y/N)" ; .byte 0
a2ds_no_device_str:   .text "Drive not found." ; .byte 0
a2ds_program_disk_str: .text "Program disk cannot hold saves." ; .byte 0
a2ds_init_fail_str:   .text "Could not initialize disk." ; .byte 0
a2ds_wp_str:          .text "Disk is write-protected." ; .byte 0
a2ds_full_str:        .text "Disk is full." ; .byte 0
a2ds_not_ready_str:   .text "Drive is not ready." ; .byte 0
a2ds_generic_str:     .text "Check the disk and try again." ; .byte 0
