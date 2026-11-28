// test_storage_errorsplus4.s — Plus/4 storage error classification unit tests
//
// Exercises platforms/shared/save.s and platforms/commodore/common/disk_swap.s
// under the real Plus/4 storage_policy.s defines:
//  1. Load early READST + DOS 74 -> LOAD_RESULT_IOERR + HSTR_SAVE_NOT_READY (no detail)
//  2. Load early READST + DOS 62 -> LOAD_RESULT_NOTFOUND + HSTR_SAVE_NOTFOUND (no detail)
//  3. Load early READST + DOS 00 -> LOAD_RESULT_NOTFOUND + HSTR_SAVE_NOTFOUND (no detail)
//  4. Load early READST + DOS 31 (unmapped) -> LOAD_RESULT_IOERR + HSTR_SAVE_IOERR + detail ('3','1')
//  5. Load OPEN fail ($05) + detached ($ff) -> LOAD_RESULT_IOERR + HSTR_SAVE_IOERR + detail ($05/$b1)
//  6. Load READST after OPEN ($80) + DOS 74 -> LOAD_RESULT_IOERR + HSTR_SAVE_NOT_READY
//  7. Load READST after OPEN ($80) + detached ($ff) -> LOAD_RESULT_IOERR + HSTR_SAVE_IOERR + detail ($80/$b1)
//  8. Load CHKIN fail ($05) + DOS 74 -> LOAD_RESULT_IOERR + HSTR_SAVE_NOT_READY
//  9. Load CHKIN fail ($05) + detached ($ff) -> LOAD_RESULT_IOERR + HSTR_SAVE_IOERR + detail ($05/$b2)
// 10. Save OPEN fail ($05) + detached ($ff) -> HSTR_SAVE_IOERR + detail ($05/$a1)
// 11. Plus/4 disk_save_media_status preserves 26/72/74, maps 62 -> WRONG_MEDIA, 31 -> UNKNOWN

.pc = $1000 "Plus/4 storage error test"

.encoding "screencode_mixed"

#define STORAGE_STATUS_HELPER
#define BYPASS_SLOT_PROMPT

#import "../../../../core/6502/zeropage.s"
#import "../hal/storage_policy.s"
#import "../../../shared/item_catalog/item_ids.s"

.const SCREEN_COLS = 40
.const STATUS_ROW = 21
.const COL_WHITE = $01
.const PL_STRUCT_SIZE = 114
.const TOTAL_INV_SLOTS = 34
.const FLAVOUR_COUNT = 174
.const STORE_TOTAL_SLOTS = 128
.const MAX_ROOMS = 8
.const MAX_TRAPS = 16
.const MAX_MONSTERS = 32
.const MONSTER_ENTRY_SIZE = 12
.const MAX_DOOR_STATES = 16
.const RECALL_DATA_SIZE = 1116
.const MAP_BASE = $c800
.const MAP_SIZE = 3840
.const MAX_FLOOR_ITEMS = 42
.const ITEM_TYPE_COUNT = 361
.const ITEM_PAGE_SIZE = 255
.const ITEM_PAGE_BIT = $40
.const FI_EMPTY = $ff
.const ID_KNOWN_BYTES = 47
.const MX_TYPE = 0
.const EMPTY_SLOT = $ff

.const hal_memory_bank_all_ram   = $30
.const hal_memory_bank_all_rom   = $37
.const hal_memory_bank_no_basic  = $36
.const hal_memory_bank_no_kernal = $35
.const hal_memory_bank_no_roms   = $34

// Huffman string IDs from core/6502/huffman_data.s (verified by exact values)
.const HSTR_SAVE_SAVING          = 184
.const HSTR_SAVE_DONE            = 185
.const HSTR_SAVE_LOADING         = 186
.const HSTR_SAVE_NOTFOUND        = 187
.const HSTR_SAVE_CORRUPT         = 188
.const HSTR_SAVE_UNSUPPORTED     = 189
.const HSTR_SAVE_IOERR           = 190
.const HSTR_SAVE_WELCOME         = 191
.const HSTR_SAVE_NEED_SAVE       = 192
.const HSTR_SAVE_BAD_SAVE        = 193
.const HSTR_SAVE_OVERWRITE       = 194
.const HSTR_SAVE_WRITE_PROTECTED = 195
.const HSTR_SAVE_DISK_FULL       = 196
.const HSTR_SAVE_NOT_READY       = 197

// Minimal dummy storage addresses for save.s descriptor tables & assertions
.const DUMMY_BUF = $7000
.label player_data         = DUMMY_BUF
.label player_background   = DUMMY_BUF
.label eff_fear_timer      = DUMMY_BUF
.label inv_item_id         = DUMMY_BUF
.label inv_qty             = inv_item_id + TOTAL_INV_SLOTS
.label inv_p1              = inv_item_id + 2 * TOTAL_INV_SLOTS
.label inv_to_hit          = inv_item_id + 3 * TOTAL_INV_SLOTS
.label inv_to_dam          = inv_item_id + 4 * TOTAL_INV_SLOTS
.label inv_to_ac           = inv_item_id + 5 * TOTAL_INV_SLOTS
.label inv_flags           = inv_item_id + 6 * TOTAL_INV_SLOTS
.label inv_ego             = inv_item_id + 7 * TOTAL_INV_SLOTS
.label potion_shuffle      = DUMMY_BUF
.label si_item_id          = DUMMY_BUF
.label store_inventory_data_end = si_item_id + 8 * STORE_TOTAL_SLOTS
.label si_meta_hi          = si_item_id + 7 * STORE_TOTAL_SLOTS
.label stairs_up_x         = DUMMY_BUF
.label level_entry_dir     = stairs_up_x + 6
.label room_count          = DUMMY_BUF
.label room_x              = DUMMY_BUF
.label room_type           = room_x + 5 * MAX_ROOMS
.label trap_count          = DUMMY_BUF
.label trap_type           = trap_count + 1 + 2 * MAX_TRAPS
.label monster_table       = DUMMY_BUF
.label door_state_count    = DUMMY_BUF
.label door_state_val      = door_state_count + 1 + 2 * MAX_DOOR_STATES
.label recall_data_start   = DUMMY_BUF
.label fi_item_id          = DUMMY_BUF
.label fi_x                = DUMMY_BUF
.label fi_y                = DUMMY_BUF
.label fi_qty              = DUMMY_BUF
.label fi_meta_hi          = DUMMY_BUF
.label fi_meta             = DUMMY_BUF
.label fi_p1               = DUMMY_BUF
.label fi_to_hit           = DUMMY_BUF
.label fi_to_dam           = DUMMY_BUF
.label fi_to_ac            = DUMMY_BUF
.label id_known_bits       = DUMMY_BUF

// Test harness state
t_open_fail:       .byte 0
t_open_err:        .byte 0
t_open_readst:     .byte 0
t_chkin_fail:      .byte 0
t_chkin_err:       .byte 0
t_magic_readst:    .byte 0
t_in_magic:        .byte 0
t_cmd_dos0:        .byte 0
t_cmd_dos1:        .byte 0
t_cmd_readst:      .byte 0
t_cmd_calls:       .byte 0
t_last_msg:        .byte 0
t_detail_calls:    .byte 0
t_detail_dos0:     .byte 0
t_detail_dos1:     .byte 0
t_detail_readst:   .byte 0
t_detail_phase:    .byte 0
t_dismiss_calls:   .byte 0
t_marker_present:  .byte 0
t_probe_exists:    .byte 0

// HAL storage bindings
.label hal_storage_setnam = t_setnam
.label hal_storage_setlfs = t_setlfs
.label hal_storage_open   = t_open
.label hal_storage_close  = t_close
.label hal_storage_chkin  = t_chkin
.label hal_storage_chkout = t_chkout
.label hal_storage_chrin  = t_chrin
.label hal_storage_chrout = t_chrout
.label hal_storage_clrchn = t_clrchn
.label hal_storage_readst = t_readst
.label hal_storage_read_command_status = t_read_cmd_status
.label hal_storage_open_cmd_channel = t_noop
.label hal_storage_read_open_cmd_status = t_read_cmd_status
.label hal_storage_close_cmd_channel = t_noop
.label hal_storage_status_lost = t_status_lost
.label hal_storage_command_status = disk_command_status
.label hal_storage_save_media_status = disk_save_media_status
.label hal_storage_setup_status = disk_setup_status
.label hal_storage_save_stream_status = save_stream_status
.label hal_storage_load_stream_status = load_stream_status
.label hal_storage_marker_present = t_marker_check
.label hal_storage_init_selected_drive = t_noop

t_status_lost: .byte 0
t_last_lfn:    .byte 0

hal_storage_save_write_name:
    .byte $40, $30, $3a, $54, $45, $53, $54, $2c, $53, $2c, $57
.label hal_storage_save_write_name_len = * - hal_storage_save_write_name
    .byte $57
.label hal_storage_save_probe_name = hal_storage_save_write_name + 1
.label hal_storage_save_probe_name_len = hal_storage_save_write_name_len - 1

hal_storage_save_read_name:
    .byte $30, $3a, $54, $45, $53, $54, $2c, $53, $2c, $52
.label hal_storage_save_read_name_len = * - hal_storage_save_read_name
    .byte $52

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Minimal stubs
t_noop:
ui_clear_full_screen_safe:
msg_init:
hal_screen_put_string:
hal_input_get_key:
player_sync_from_zp:
player_sync_to_zp:
player_search_clear_transient_state:
item_refresh_fixed_known:
item_init_floor:
floor_item_get_qty_hi_x:
floor_item_get_p1_x:
monster_get_ptr:
    clc
    rts

disk_program_media_present:
tramp_disk_prepare_selected:
    sec
    rts

huff_print_msg:
    stx t_last_msg
    rts

save_append_disk_detail_plus4:
    inc t_detail_calls
    lda disk_error_dos0
    sta t_detail_dos0
    lda disk_error_dos1
    sta t_detail_dos1
    lda disk_error_readst
    sta t_detail_readst
    lda disk_error_phase
    sta t_detail_phase
    rts

input_get_modal_dismiss_key:
    inc t_dismiss_calls
    lda #$20
    rts

t_marker_check:
    lda t_marker_present
    beq !fail+
    jsr disk_error_clear
    clc
    rts
!fail:
    sec
    rts

t_setnam:
    clc
    rts

t_setlfs:
    sta t_last_lfn
    clc
    rts

t_open:
    lda t_last_lfn
    cmp #hal_storage_check_file_num
    beq !probe_open+
    lda t_open_fail
    beq !ok+
    lda t_open_err
    sec
    rts
!probe_open:
    lda t_probe_exists
    bne !ok+
    sec
    rts
!ok:
    lda #0
    sta t_in_magic
    clc
    rts

t_close:
t_clrchn:
t_chkout:
t_chrout:
    clc
    rts

t_chkin:
    lda t_chkin_fail
    beq !ok+
    lda t_chkin_err
    sec
    rts
!ok:
    lda #1
    sta t_in_magic
    clc
    rts

t_chrin:
    lda #$00
    clc
    rts

t_readst:
    lda t_in_magic
    bne !magic+
    lda t_open_readst
    clc
    rts
!magic:
    lda t_magic_readst
    clc
    rts

t_read_cmd_status:
    inc t_cmd_calls
    lda t_last_lfn
    cmp #hal_storage_check_file_num
    bne !normal+
    // save_file_exists probe: report NOT_FOUND so overwrite confirm doesn't prompt
    lda #$36
    sta disk_error_dos0
    lda #$32
    sta disk_error_dos1
    rts
!normal:
    lda t_cmd_dos0
    sta disk_error_dos0
    lda t_cmd_dos1
    sta disk_error_dos1
    lda t_cmd_readst
    sta disk_error_readst
    rts

.macro SaveByteRead_ptr0_y() {
    lda (zp_ptr0),y
}
.macro SaveByteWrite_ptr0_y() {
    sta (zp_ptr0),y
}

#import "../../../../core/6502/runtime_ui_strings.s"
#import "../../../shared/save.s"
#import "../../common/disk_swap.s"

t_reset:
    lda #0
    sta t_open_fail
    sta t_open_err
    sta t_open_readst
    sta t_chkin_fail
    sta t_chkin_err
    sta t_magic_readst
    sta t_in_magic
    sta t_cmd_dos0
    sta t_cmd_dos1
    sta t_cmd_readst
    sta t_cmd_calls
    sta t_last_msg
    sta t_detail_calls
    sta t_detail_dos0
    sta t_detail_dos1
    sta t_detail_readst
    sta t_detail_phase
    sta t_dismiss_calls
    sta t_probe_exists
    lda #1
    sta t_marker_present
    sta disk_setup_done
    lda #2
    sta disk_mode
    lda #8
    sta program_device
    lda #9
    sta save_device
    jmp disk_error_clear

test_start:
    sei
    cld
    ldx #$ff
    txs

    // 1. Load early READST ($42) + DOS 74 -> LOAD_RESULT_IOERR + HSTR_SAVE_NOT_READY
    jsr t_reset
    lda #$42
    sta t_magic_readst
    lda #$37
    sta t_cmd_dos0
    lda #$34
    sta t_cmd_dos1
    jsr load_game
    bcc *+5
    jmp test_fail
    lda load_result
    cmp #LOAD_RESULT_IOERR
    beq *+5
    jmp test_fail
    lda t_last_msg
    cmp #HSTR_SAVE_NOT_READY
    beq *+5
    jmp test_fail
    lda t_detail_calls
    beq *+5
    jmp test_fail
    lda disk_error_dos0
    cmp #$37
    beq *+5
    jmp test_fail
    lda disk_error_dos1
    cmp #$34
    beq *+5
    jmp test_fail

    // 2. Load early READST ($42) + DOS 62 -> LOAD_RESULT_NOTFOUND + HSTR_SAVE_NOTFOUND
    jsr t_reset
    lda #$42
    sta t_magic_readst
    lda #$36
    sta t_cmd_dos0
    lda #$32
    sta t_cmd_dos1
    jsr load_game
    bcc *+5
    jmp test_fail
    lda load_result
    cmp #LOAD_RESULT_NOTFOUND
    beq *+5
    jmp test_fail
    lda t_last_msg
    cmp #HSTR_SAVE_NOTFOUND
    beq *+5
    jmp test_fail
    lda t_detail_calls
    beq *+5
    jmp test_fail
    lda disk_error_dos0
    cmp #$36
    beq *+5
    jmp test_fail
    lda disk_error_dos1
    cmp #$32
    beq *+5
    jmp test_fail

    // 3. Load early READST ($42) + DOS 00 -> LOAD_RESULT_NOTFOUND + HSTR_SAVE_NOTFOUND
    jsr t_reset
    lda #$42
    sta t_magic_readst
    lda #$30
    sta t_cmd_dos0
    sta t_cmd_dos1
    jsr load_game
    bcc *+5
    jmp test_fail
    lda load_result
    cmp #LOAD_RESULT_NOTFOUND
    beq *+5
    jmp test_fail
    lda t_last_msg
    cmp #HSTR_SAVE_NOTFOUND
    beq *+5
    jmp test_fail
    lda t_detail_calls
    beq *+5
    jmp test_fail

    // 4. Load early READST ($42) + unmapped DOS 31 -> LOAD_RESULT_IOERR + HSTR_SAVE_IOERR + detail ('3','1')
    jsr t_reset
    lda #$42
    sta t_magic_readst
    lda #$33
    sta t_cmd_dos0
    lda #$31
    sta t_cmd_dos1
    jsr load_game
    bcc *+5
    jmp test_fail
    lda load_result
    cmp #LOAD_RESULT_IOERR
    beq *+5
    jmp test_fail
    lda t_last_msg
    cmp #HSTR_SAVE_IOERR
    beq *+5
    jmp test_fail
    lda t_detail_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda t_detail_dos0
    cmp #$33
    beq *+5
    jmp test_fail
    lda t_detail_dos1
    cmp #$31
    beq *+5
    jmp test_fail

    // 5. Load OPEN fail ($05) + detached ($ff) -> LOAD_RESULT_IOERR + HSTR_SAVE_IOERR + detail ($05/$b1)
    jsr t_reset
    lda #1
    sta t_open_fail
    lda #$05
    sta t_open_err
    lda #$ff
    sta t_cmd_dos0
    sta t_cmd_dos1
    lda #$02                    // command read clobbers readst; save_query_drive_status must restore $05
    sta t_cmd_readst
    jsr load_game
    bcc *+5
    jmp test_fail
    lda load_result
    cmp #LOAD_RESULT_IOERR
    beq *+5
    jmp test_fail
    lda t_last_msg
    cmp #HSTR_SAVE_IOERR
    beq *+5
    jmp test_fail
    lda t_detail_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda t_detail_readst
    cmp #$05
    beq *+5
    jmp test_fail
    lda t_detail_phase
    cmp #DISK_ERR_LOAD_OPEN
    beq *+5
    jmp test_fail

    // 6. Load READST after OPEN ($80) + DOS 74 -> LOAD_RESULT_IOERR + HSTR_SAVE_NOT_READY
    jsr t_reset
    lda #$80
    sta t_open_readst
    lda #$37
    sta t_cmd_dos0
    lda #$34
    sta t_cmd_dos1
    jsr load_game
    bcc *+5
    jmp test_fail
    lda load_result
    cmp #LOAD_RESULT_IOERR
    beq *+5
    jmp test_fail
    lda t_last_msg
    cmp #HSTR_SAVE_NOT_READY
    beq *+5
    jmp test_fail
    lda t_detail_calls
    beq *+5
    jmp test_fail

    // 7. Load READST after OPEN ($80) + detached ($ff) -> HSTR_SAVE_IOERR + detail ($80/$b1)
    jsr t_reset
    lda #$80
    sta t_open_readst
    lda #$ff
    sta t_cmd_dos0
    sta t_cmd_dos1
    jsr load_game
    bcc *+5
    jmp test_fail
    lda load_result
    cmp #LOAD_RESULT_IOERR
    beq *+5
    jmp test_fail
    lda t_last_msg
    cmp #HSTR_SAVE_IOERR
    beq *+5
    jmp test_fail
    lda t_detail_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda t_detail_readst
    cmp #$80
    beq *+5
    jmp test_fail
    lda t_detail_phase
    cmp #DISK_ERR_LOAD_OPEN
    beq *+5
    jmp test_fail

    // 8. Load CHKIN fail ($05) + DOS 74 -> LOAD_RESULT_IOERR + HSTR_SAVE_NOT_READY
    jsr t_reset
    lda #1
    sta t_chkin_fail
    lda #$05
    sta t_chkin_err
    lda #$37
    sta t_cmd_dos0
    lda #$34
    sta t_cmd_dos1
    jsr load_game
    bcc *+5
    jmp test_fail
    lda load_result
    cmp #LOAD_RESULT_IOERR
    beq *+5
    jmp test_fail
    lda t_last_msg
    cmp #HSTR_SAVE_NOT_READY
    beq *+5
    jmp test_fail
    lda t_detail_calls
    beq *+5
    jmp test_fail

    // 9. Refused OPEN ($ff DOS) stops BEFORE CHKIN -> LOAD_RESULT_IOERR + HSTR_SAVE_IOERR + detail ($00/$00)
    jsr t_reset
    lda #1
    sta t_chkin_fail
    lda #$05
    sta t_chkin_err
    lda #$ff
    sta t_cmd_dos0
    sta t_cmd_dos1
    jsr load_game
    bcc *+5
    jmp test_fail
    lda load_result
    cmp #LOAD_RESULT_IOERR
    beq *+5
    jmp test_fail
    lda t_last_msg
    cmp #HSTR_SAVE_IOERR
    beq *+5
    jmp test_fail
    lda t_in_magic
    beq *+5
    jmp test_fail
    lda t_detail_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda t_detail_phase
    beq *+5
    jmp test_fail

    // 9b. Load CHKIN fail ($05) after DOS 00 -> LOAD_RESULT_IOERR + HSTR_SAVE_IOERR + detail ($05/$b2)
    jsr t_reset
    lda #1
    sta t_chkin_fail
    lda #$05
    sta t_chkin_err
    lda #$30
    sta t_cmd_dos0
    sta t_cmd_dos1
    jsr load_game
    bcc *+5
    jmp test_fail
    lda load_result
    cmp #LOAD_RESULT_IOERR
    beq *+5
    jmp test_fail
    lda t_last_msg
    cmp #HSTR_SAVE_IOERR
    beq *+5
    jmp test_fail
    lda t_detail_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda t_detail_readst
    cmp #$05
    beq *+5
    jmp test_fail
    lda t_detail_phase
    cmp #DISK_ERR_LOAD_CHKIN
    beq *+5
    jmp test_fail

    // 10. Save OPEN fail ($05) + detached ($ff) -> HSTR_SAVE_IOERR + detail ($05/$a1)
    jsr t_reset
    lda #1
    sta t_open_fail
    lda #$05
    sta t_open_err
    lda #$ff
    sta t_cmd_dos0
    sta t_cmd_dos1
    jsr save_game
    bcc *+5
    jmp test_fail
    lda t_last_msg
    cmp #HSTR_SAVE_IOERR
    beq *+5
    jmp test_fail
    lda t_detail_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda t_detail_readst
    cmp #$05
    beq *+5
    jmp test_fail
    lda t_detail_phase
    cmp #DISK_ERR_SAVE_OPEN
    beq *+5
    jmp test_fail

    // 11. Plus/4 disk_save_media_status preserves 26/72/74, maps 62 -> WRONG_MEDIA, 31 -> UNKNOWN
    jsr t_reset
    lda #$81
    sta disk_error_phase
    lda #$32
    sta disk_error_dos0
    lda #$36
    sta disk_error_dos1
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_WRITE_PROTECTED
    beq *+5
    jmp test_fail

    lda #$37
    sta disk_error_dos0
    lda #$32
    sta disk_error_dos1
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_DISK_FULL
    beq *+5
    jmp test_fail

    lda #$37
    sta disk_error_dos0
    lda #$34
    sta disk_error_dos1
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    beq *+5
    jmp test_fail

    lda #$36
    sta disk_error_dos0
    lda #$32
    sta disk_error_dos1
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_WRONG_MEDIA
    beq *+5
    jmp test_fail

    lda #$33
    sta disk_error_dos0
    lda #$31
    sta disk_error_dos1
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq *+5
    jmp test_fail

    jsr t_reset
    lda #74
    sta disk_status
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    beq *+5
    jmp test_fail

    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass

.assert "Plus/4 storage error test stays below $7000 dummy buffers", * <= DUMMY_BUF, true
