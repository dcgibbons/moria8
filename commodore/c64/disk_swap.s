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
ds_drv9_str:    .text "[Drive 9]" ; .byte 0
ds_menu_str:    .text "S)ame W)swap 9)Drive 9" ; .byte 0
ds_nod9_str:    .text "Drive 9 not found!" ; .byte 0

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
// probe_device_9 — Check if device 9 is present on IEC bus
// Opens command channel 15 on device 9, sends "I0".
// Output: carry clear = device 9 present, carry set = absent
// Clobbers: A, X, Y
// ============================================================
probe_device_9:
    lda #2
    ldx #<disk_init_cmd
    ldy #>disk_init_cmd
    jsr KERNAL_SETNAM
    lda #CMD_CHANNEL
    ldx #9
    ldy #CMD_CHANNEL
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcs !pd9_absent+            // OPEN failed → device not present
    // Check KERNAL status ($90) for device-not-present error
    jsr KERNAL_READST
    and #$83                    // Bits 7,1,0 = timeout/error
    bne !pd9_close_absent+
    // Device present — close and return C=0
    lda #CMD_CHANNEL
    jsr KERNAL_CLOSE
    jsr KERNAL_CLRCHN
    clc
    rts
!pd9_close_absent:
    lda #CMD_CHANNEL
    jsr KERNAL_CLOSE
!pd9_absent:
    jsr KERNAL_CLRCHN
    sec
    rts
