// test_pristine.s
.pc = $0801 "BASIC Stub"
    .byte $0b, $08, $0a, $00, $9e, $32, $30, $36, $31, $00, $00, $00 // 10 SYS 2061

.pc = $080d "Test Code"
test_start:
    sei
    lda #$01
    sta $0c00
    sta $0c01
test_done:
    jmp test_done
