// boot.s — Chain-loading bootloader for Moria8 Plus/4

.pc = $1001 "BASIC Stub"
.word basic_stub_end
.word 10
.byte $9e
.text "4110"
.byte 0
basic_stub_end:
.word 0

.pc = $100e "Boot"

.const LOGICAL_FILE    = 2
.const DEVICE_NUM      = 8
.const LOAD_USE_HEADER = 1
.const TED_BG          = $ff15
.const TED_BORDER      = $ff19
.const CHAIN_STUB_ADDR = $0500

boot_entry:
    jsr capture_boot_device
    lda #0
    sta TED_BG
    sta TED_BORDER
    lda #$93
    jsr $ffd2

    jsr print_loading_msg

load_main_program:
    ldx #chain_stub_end - chain_stub - 1
!copy_stub:
    lda chain_stub,x
    sta CHAIN_STUB_ADDR,x
    dex
    bpl !copy_stub-

    lda boot_device
    sta chain_boot_device
    jmp chain_entry

print_loading_msg:
    lda #$05            // White color code
    jsr $ffd2
    clc
    ldx #12             // Row 12
    ldy #11             // Column 11
    jsr $fff0           // KERNAL PLOT
    ldx #0
!loop:
    lda loading_msg,x
    beq !done+
    jsr $ffd2           // KERNAL CHROUT
    inx
    jmp !loop-
!done:
    rts

capture_boot_device:
    lda $ae                 // Plus/4 KERNAL current device from LOAD/RUN path
    cmp #8
    bcc !done+
    cmp #31
    bcs !done+
    sta boot_device
!done:
    rts

loading_msg:
    .text "LOADING MORIA8..."
    .byte 0

chain_stub:
.pseudopc CHAIN_STUB_ADDR {
chain_entry:
    lda #chain_game_filename_end - chain_game_filename
    ldx #<chain_game_filename
    ldy #>chain_game_filename
    jsr $ffbd

    lda #LOGICAL_FILE
    ldx chain_boot_device
    ldy #LOAD_USE_HEADER
    jsr $ffba

    lda #0
    jsr $ffd5
    bcs !err+
    jmp $100e
!err:
    lda #$93
    jsr $ffd2
    ldx #0
!msg:
    lda chain_load_error_msg,x
    beq !spin+
    jsr $ffd2
    inx
    bne !msg-
!spin:
    jmp !spin-
chain_game_filename:
    .byte $4d,$4f,$52,$49,$41,$34          // "MORIA4"
chain_game_filename_end:

chain_boot_device:
    .byte DEVICE_NUM

chain_load_error_msg:
    .byte $4c,$4f,$41,$44,$20,$45,$52,$52,$4f,$52
    .byte 0
}
chain_stub_end:

boot_device:
    .byte DEVICE_NUM

.assert "Plus/4 boot chain stub stays in low RAM", CHAIN_STUB_ADDR + (chain_stub_end - chain_stub) <= $0800, true
