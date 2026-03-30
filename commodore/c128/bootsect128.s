// bootsect128.s — Native C128 boot sector for the mixed-platform dual-entry disk
//
// Boot protocol:
// - sector is patched into Track 1 / Sector 0
// - native C128 KERNAL loads it to $0B00 and executes the code there
// - code executes BASIC command: BOOT"BOOT128",U8

.pc = $0b00 "BootSector"
    .text "CBM"
    .word $0000              // no chained sectors from Track 1 / Sector 1
    .byte $00                // bank
    .byte $00                // block count

    .text "MORIA8 C128"
    .byte 0

    .byte 0                  // no implicit filename; custom code runs instead

boot_code:
    ldx #<boot_cmd - 1
    ldy #>boot_cmd
    jmp $afa5                // BASIC execute-a-line

boot_cmd:
    .text "BOOT"
    .byte $22
    .text "BOOT128"
    .byte $22
    .text ",U8"
    .byte 0

.assert "boot sector fits in 256 bytes", * <= $0c00, true
