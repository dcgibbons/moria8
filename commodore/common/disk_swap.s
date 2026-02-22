// disk_swap.s — Dual-disk mode support
//
// Provides disk swap prompts for separate game/save disks.
// In single-disk mode (disk_mode=0), all prompts are no-ops.
//
// Requires: save.s constants (KERNAL_*, CMD_CHANNEL, SAVE_DEVICE)
//           main.s labels (press_key_str)

// ============================================================
// Data
// ============================================================
disk_mode:      .byte 0                 // 0=single, 1=swap, 2=dual-drive
save_device:    .byte 8                 // Device# for save/score I/O (8 or 9)

// Screen-code strings (under .encoding "screencode_mixed" from main.s)
ds_save_str:    .text "Insert save disk" ; .byte 0
ds_game_str:    .text "Insert game disk" ; .byte 0
ds_dual_str:    .text "[Save Disk]" ; .byte 0
ds_menu_str:    .text "S)ame W)swap #)Drive #" ; .byte 0
de_prompt_str:  .text "Save drive (8-30): " ; .byte 0  // 19 chars
de_ind_pfx:     .text "[Drive " ; .byte 0               // 7 chars
de_nodev_str:   .text "Drive not found!" ; .byte 0      // 16 chars
// Device-entry state (transient, no save needed)
de_digits:      .byte 0, 0    // buffered digit ASCII codes
de_count:       .byte 0       // number of digits entered
de_temp:        .byte 0       // scratch / device number

// PETSCII "I0" for drive init (raw bytes — NOT screen codes)
disk_init_cmd:  .byte $49, $30

// ============================================================
// disk_prompt_save — Prompt to insert save disk
// Clobbers: A, X, Y, zp_ptr0/hi, zp_cursor_row/col, zp_text_color
// ============================================================
disk_prompt_save:
    lda #<ds_save_str
    ldx #>ds_save_str
    jmp disk_prompt

// ============================================================
// disk_prompt_game — Prompt to insert game disk
// Clobbers: A, X, Y, zp_ptr0/hi, zp_cursor_row/col, zp_text_color
// ============================================================
disk_prompt_game:
    lda #<ds_game_str
    ldx #>ds_game_str
    jmp disk_prompt

// ============================================================
// disk_prompt — Display swap prompt and wait for keypress
// Input: A/X = lo/hi of prompt string (screen codes, null-terminated)
// No-op in mode 0 (single) and mode 2 (dual-drive, no swap needed).
// Clobbers: A, X, Y, zp_ptr0/hi, zp_cursor_row/col, zp_text_color
// ============================================================
disk_prompt:
    ldy disk_mode
    beq !dp_done+               // mode 0: no-op
    cpy #2
    beq !dp_done+               // mode 2: no-op (separate drive)
    sta zp_ptr0
    stx zp_ptr0_hi
    lda #COL_WHITE
    sta zp_text_color
    lda #10
    sta zp_cursor_row
    lda #12                     // (40-16)/2 = 12
    sta zp_cursor_col
    jsr screen_put_string

    // "PRESS ANY KEY" on row 11
    lda #11
    sta zp_cursor_row
    lda #13                     // (40-13)/2 = 13
    sta zp_cursor_col
    lda #<press_key_str
    sta zp_ptr0
    lda #>press_key_str
    sta zp_ptr0_hi
    jsr screen_put_string

    jsr input_get_key
    jsr disk_init_drive

    // Clear prompt rows
    lda #10
    jsr screen_clear_row
    lda #11
    jsr screen_clear_row
!dp_done:
    rts

// ============================================================
// disk_init_drive — Reinitialize drive 8 after disk swap
// Sends "I0" command via KERNAL command channel.
// Clobbers: A, X, Y
// ============================================================
disk_init_drive:
    lda #2
    ldx #<disk_init_cmd
    ldy #>disk_init_cmd
    jsr KERNAL_SETNAM
    lda #CMD_CHANNEL
    ldx save_device
    ldy #CMD_CHANNEL
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcs !did_skip+
    lda #CMD_CHANNEL
    jsr KERNAL_CLOSE
!did_skip:
    jsr KERNAL_CLRCHN
    rts

// ============================================================
// probe_device — Check if an IEC device is present on IEC bus
// Opens command channel 15 on the given device, sends "I0".
// Input:  X = device number (8–30)
// Output: carry clear = present, carry set = absent
// Clobbers: A, X, Y
// ============================================================
probe_device:
    stx de_temp                 // save device# (SETNAM clobbers X)
    lda #2
    ldx #<disk_init_cmd
    ldy #>disk_init_cmd
    jsr KERNAL_SETNAM
    lda #CMD_CHANNEL
    ldx de_temp                 // restore device number
    ldy #CMD_CHANNEL
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcs !pd_absent+             // OPEN failed → device not present
    jsr KERNAL_READST
    and #$83                    // Bits 7,1,0 = timeout/error
    bne !pd_close_absent+
    lda #CMD_CHANNEL
    jsr KERNAL_CLOSE
    jsr KERNAL_CLRCHN
    clc
    rts
!pd_close_absent:
    lda #CMD_CHANNEL
    jsr KERNAL_CLOSE
!pd_absent:
    jsr KERNAL_CLRCHN
    sec
    rts

// ============================================================
// disk_enter_device — Prompt for IEC device number and probe it
// Displays "Save drive (8-30): " on row 19; reads 1–2 digit keys.
// Validates range 8–30, probes the device, configures save_device.
// Returns: carry clear = success (disk_mode=2, save_device set)
//          carry set   = device not found (error shown, key waited)
// Clobbers: A, X, Y, zp_ptr0/hi, zp_cursor_row/col, zp_text_color
// ============================================================
disk_enter_device:
    lda #19
    jsr screen_clear_row
    lda #20
    jsr screen_clear_row
    // Print prompt on row 19
    lda #COL_WHITE
    sta zp_text_color
    lda #19
    sta zp_cursor_row
    lda #10                     // (40-19)/2 ≈ 10
    sta zp_cursor_col
    lda #<de_prompt_str
    sta zp_ptr0
    lda #>de_prompt_str
    sta zp_ptr0_hi
    jsr screen_put_string       // cursor lands at col 29 after 19-char prompt
    // Reset digit count
    lda #0
    sta de_count
!de_key_loop:
    jsr input_get_key
    // DEL ($14) — erase last digit
    cmp #$14
    bne !de_not_del+
    lda de_count
    beq !de_key_loop-           // nothing to erase
    dec de_count
    lda de_count                // new count = digit column offset
    clc
    adc #29                     // erase col 29+new_count
    sta zp_cursor_col
    lda #19
    sta zp_cursor_row
    lda #$20                    // space screen code
    jsr screen_put_char
    jmp !de_key_loop-
!de_not_del:
    // RETURN ($0d) — commit entered digits
    cmp #$0d
    bne !de_not_ret+
    lda de_count
    bne !de_commit+
    jmp !de_key_loop-           // no digits yet — ignore
!de_not_ret:
    // Accept digit $30–$39 if < 2 digits entered
    cmp #$30
    bcc !de_key_loop-
    cmp #$3a
    bcs !de_key_loop-
    ldx de_count
    cpx #2
    bcs !de_key_loop-           // already 2 digits — wait for RETURN or DEL
    sta de_digits,x             // store ASCII digit
    pha                         // save digit for screen_put_char
    txa
    clc
    adc #29                     // col = 29 + digit index
    sta zp_cursor_col
    lda #19
    sta zp_cursor_row
    pla                         // restore digit ($30–$39 = same screen code)
    jsr screen_put_char
    inc de_count
    jmp !de_key_loop-

!de_commit:
    // Convert de_digits[] to binary
    lda de_count
    cmp #1
    beq !de_one_digit+
    // Two digits: N = (tens*10) + units
    lda de_digits               // tens ASCII
    sec
    sbc #$30                    // 0–9
    asl                         // ×2
    sta de_temp
    asl                         // ×4
    asl                         // ×8
    clc
    adc de_temp                 // ×10
    sta de_temp
    lda de_digits+1             // units ASCII
    sec
    sbc #$30
    clc
    adc de_temp
    jmp !de_validate+
!de_one_digit:
    lda de_digits
    sec
    sbc #$30                    // 0–9

!de_validate:
    // Range check: 8 <= A <= 30
    cmp #8
    bcc !de_restart+
    cmp #31
    bcs !de_restart+
    // Valid range — probe the device
    tax                         // X = device number
    jsr probe_device            // stashes X in de_temp; C=0 if present
    bcc !de_found+
    // Device not found — show error on row 20, wait for key, return C=1
    lda #COL_LRED
    sta zp_text_color
    lda #20
    sta zp_cursor_row
    lda #12                     // (40-16)/2 = 12
    sta zp_cursor_col
    lda #<de_nodev_str
    sta zp_ptr0
    lda #>de_nodev_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #COL_WHITE
    sta zp_text_color
    jsr input_get_key
    // Clean up rows before returning to disk menu
    lda #19
    jsr screen_clear_row
    lda #20
    jsr screen_clear_row
    sec
    rts

!de_restart:
    jmp disk_enter_device       // out of range — re-prompt

!de_found:
    // de_temp holds device# (saved by probe_device's stx de_temp)
    lda #2
    sta disk_mode
    lda de_temp
    sta save_device
    // Show "[Drive N]" indicator on row 18
    lda #18
    jsr screen_clear_row
    lda #COL_CYAN
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #15                     // center: (40-10)/2 = 15 for "[Drive NN]"
    sta zp_cursor_col
    lda #<de_ind_pfx
    sta zp_ptr0
    lda #>de_ind_pfx
    sta zp_ptr0_hi
    jsr screen_put_string       // prints "[Drive " (7 chars)
    lda de_temp
    jsr screen_put_decimal_rj2  // 2-char right-justified device number
    lda #$1d                    // screen code for ']'
    jsr screen_put_char
    lda #COL_WHITE
    sta zp_text_color
    // Clear input rows
    lda #19
    jsr screen_clear_row
    clc
    rts
