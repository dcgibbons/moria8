.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_exit_trampoline:
    ldx #2
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0830 "Main"

.encoding "screencode_mixed"

#import "../../common/zeropage.s"
#import "../memory.s"

.const SCREEN_COLS = 40
.const STATUS_ROW = 21
.const COL_WHITE = $01
.const hal_storage_cmd_channel = 15

.const KERNAL_SETNAM = kernal_setnam
.const KERNAL_SETLFS = kernal_setlfs
.const KERNAL_OPEN   = kernal_open
.const KERNAL_CLOSE  = kernal_close
.const KERNAL_CLRCHN = kernal_clrchn
.const KERNAL_READST = kernal_readst
.const KERNAL_CHKIN  = kernal_chkin
.const KERNAL_CHKOUT = kernal_chkout
.const KERNAL_CHRIN  = kernal_chrin
.const KERNAL_CHROUT = kernal_chrout

.label hal_storage_setnam = kernal_setnam
.label hal_storage_setlfs = kernal_setlfs
.label hal_storage_open = kernal_open
.label hal_storage_close = kernal_close
.label hal_storage_chkin = kernal_chkin
.label hal_storage_chkout = kernal_chkout
.label hal_storage_chrin = kernal_chrin
.label hal_storage_chrout = kernal_chrout
.label hal_storage_clrchn = kernal_clrchn
.label hal_storage_readst = kernal_readst

.const REU_COMMAND   = $df01
.const REU_C64LO     = $df02
.const REU_C64HI     = $df03
.const REU_REULO     = $df04
.const REU_REUHI     = $df05
.const REU_BANK      = $df06
.const REU_LENLO     = $df07
.const REU_LENHI     = $df08
.const REU_CONTROL   = $df0a
.const REU_CMD_FETCH = $91

.const KERNAL_HIDDEN_STUB = $ff80

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

#import "../../common/runtime_ui_strings.s"

tc_results: .fill 3, $ff

reu_overlays_stashed: .byte 0
ti_calls:            .byte 0
hidden_kernal_hits:  .byte 0
load_calls:          .byte 0
load_seen_bank:      .byte 0
ui_seen_bank:        .byte 0
ui_seen_p:           .byte 0
sp_before:           .byte 0
sp_after_ui:         .byte 0
sp_after_disk:       .byte 0
zp_save_ptr0:        .byte 0
zp_save_ptr0_hi:     .byte 0
zp_save_cursor_row:  .byte 0
zp_save_text_color:  .byte 0

screen_put_string:
screen_put_char:
screen_clear_row:
screen_put_decimal_rj2:
input_get_key:
    rts

tier_invalidate_state:
    inc ti_calls
    rts

.macro AssetLoad() {
    jsr kernal_load
}

kernal_load:
    inc load_calls
    lda $01
    sta load_seen_bank
    clc
    rts

kernal_setnam:
kernal_setlfs:
kernal_open:
kernal_close:
kernal_clrchn:
    clc
    rts

kernal_readst:
    lda #0
    rts

kernal_chkin:
kernal_chkout:
    clc
    rts

kernal_chrin:
    lda #0
    rts

kernal_chrout:
    rts

.label c64_disk_setnam = kernal_setnam
.label c64_disk_setlfs = kernal_setlfs
.label c64_disk_open   = kernal_open
.label c64_disk_close  = kernal_close
.label c64_disk_clrchn = kernal_clrchn
.label c64_disk_readst = kernal_readst
.label c64_disk_chkin  = kernal_chkin
.label c64_disk_chkout = kernal_chkout
.label c64_disk_chrin  = kernal_chrin
.label c64_disk_chrout = kernal_chrout
c64_disk_marker_init:
    clc
    rts
c64_disk_marker_present:
    sec
    rts

ui_disk_setup_dispatch:
    lda $01
    sta ui_seen_bank
    php
    pla
    sta ui_seen_p
    lda #5
    sta disk_ui_result
    rts

#import "../../common/overlay.s"
#import "../../common/disk_swap.s"

banked_payload:
.pseudopc $F000 {
    #import "../../common/disk_setup_banked.s"
banked_code_end:
}
banked_payload_end:

copy_banked_payload:
    sei
    lda #BANK_NO_ROMS
    sta $01
    lda #<banked_payload
    sta zp_ptr0
    lda #>banked_payload
    sta zp_ptr0_hi
    lda #$00
    sta zp_ptr1
    lda #$F0
    sta zp_ptr1_hi
    ldx #((banked_payload_end - banked_payload + 255) / 256)
    ldy #0
!copy:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    bne !copy-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dex
    bne !copy-
    lda #BANK_NO_BASIC
    sta $01
    cli
    rts

install_hidden_kernal_stub:
    sei
    lda #BANK_NO_ROMS
    sta $01

    lda #$ee                    // INC abs
    sta KERNAL_HIDDEN_STUB + 0
    lda #<hidden_kernal_hits
    sta KERNAL_HIDDEN_STUB + 1
    lda #>hidden_kernal_hits
    sta KERNAL_HIDDEN_STUB + 2
    lda #$18                    // CLC
    sta KERNAL_HIDDEN_STUB + 3
    lda #$60                    // RTS
    sta KERNAL_HIDDEN_STUB + 4

    lda #$4c                    // JMP $FF80
    sta $ffba
    sta $ffbd
    sta $ffc3
    sta $ffcc
    lda #<KERNAL_HIDDEN_STUB
    sta $ffbb
    sta $ffbe
    sta $ffc4
    sta $ffcd
    lda #>KERNAL_HIDDEN_STUB
    sta $ffbc
    sta $ffbf
    sta $ffc5
    sta $ffce

    lda #BANK_NO_BASIC
    sta $01
    cli
    rts

test_start:
    sei
    cld
    ldx #$ff
    txs

    ldx #2
    lda #$ff
!init:
    sta tc_results,x
    dex
    bpl !init-

    jsr copy_banked_payload
    jsr install_hidden_kernal_stub

    lda #$12
    sta zp_ptr0
    lda #$34
    sta zp_ptr0_hi
    lda #$05
    sta zp_cursor_row
    lda #$07
    sta zp_text_color

    sei
    lda #BANK_NO_ROMS
    sta $01
    ldx #$ff
    txs
    tsx
    stx sp_before

    lda #DISK_UI_ACT_CONFIRM_DRIVE9
    jsr disk_setup_call_ui
    tsx
    stx sp_after_ui

    // Test 1: round-trip invariants around actual banked UI call
    bcs !t1_fail+
    lda $01
    cmp #BANK_NO_ROMS
    bne !t1_fail+
    php
    pla
    and #%00000100
    beq !t1_fail+
    lda sp_after_ui
    cmp sp_before
    bne !t1_fail+
    lda zp_ptr0
    cmp #$12
    bne !t1_fail+
    lda zp_ptr0_hi
    cmp #$34
    bne !t1_fail+
    lda zp_cursor_row
    cmp #$05
    bne !t1_fail+
    lda zp_text_color
    cmp #$07
    bne !t1_fail+
    lda current_overlay
    cmp #OVL_HELP
    bne !t1_fail+
    lda ui_seen_bank
    cmp #BANK_NO_KERNAL
    bne !t1_fail+
    lda ui_seen_p
    and #%00000100
    beq !t1_fail+
    lda #1
    bne !t1_store+
!t1_fail:
    lda #0
!t1_store:
    sta tc_results + 0

    // Test 2: shipping ABI proof — overlay_load from banked `$34` must not
    // execute hidden KERNAL RAM or run LOAD with KERNAL still banked out.
    lda hidden_kernal_hits
    bne !t2_fail+
    lda load_calls
    cmp #1
    bne !t2_fail+
    lda load_seen_bank
    cmp #BANK_NO_BASIC
    bne !t2_fail+
    lda #1
    bne !t2_store+
!t2_fail:
    lda #0
!t2_store:
    sta tc_results + 1

    // Test 3: resident disk helper still round-trips back to banked `$34`
    lda #9
    sta save_device
    jsr disk_init_drive
    tsx
    stx sp_after_disk
    lda $01
    cmp #BANK_NO_ROMS
    bne !t3_fail+
    php
    pla
    and #%00000100
    beq !t3_fail+
    lda sp_after_disk
    cmp sp_before
    bne !t3_fail+
    lda zp_ptr0
    cmp #$12
    bne !t3_fail+
    lda zp_ptr0_hi
    cmp #$34
    bne !t3_fail+
    lda zp_cursor_row
    cmp #$05
    bne !t3_fail+
    lda zp_text_color
    cmp #$07
    bne !t3_fail+
    lda #1
    bne !t3_store+
!t3_fail:
    lda #0
!t3_store:
    sta tc_results + 2

    jmp test_exit_trampoline
