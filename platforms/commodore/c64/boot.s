// boot.s - C64 boot-art loader and MORIA64 handoff

#import "hal/memory_bank_consts.s"
#import "../common/bank_port_consts.s"

.const VIC_BANK0_SELECT = $03
.const ART_STAGE        = $a000
.const ART_SCREEN_STAGE = $bf40
.const ART_COLOR_STAGE  = $c328
.const ART_BITMAP_DEST  = $c000
.const ART_SCREEN_DEST  = $e000
.const ART_COLOR_DEST   = $d800
.const ART_BITMAP_SIZE  = 8000
.const ART_ATTR_SIZE    = 1000
.const BITMAP_D011      = $3b
.const BITMAP_D016      = $18
.const BITMAP_D018      = $80
.const TEXT_D016        = $08
.const TEXT_D018        = $14
.const LOGICAL_FILE     = 2
.const DEVICE_NUM       = 8
.const LOAD_USE_HEADER  = 1
.const KRILL_INSTALL_ADDR = $2000
.const KRILL_BOOT_LOADRAW = $0400
.const KRILL_BOOT_UNINSTALL = $04e1
.const CHAIN_STUB_ADDR  = $0500
.const ERROR_TRAMP_ADDR = $0340
.const ZP_SRC_LO        = $fb
.const ZP_SRC_HI        = $fc
.const ZP_DST_LO        = $fd
.const ZP_DST_HI        = $fe
.const KERNAL_MSGFLG    = $9d

.pc = $0801 "BASIC Stub"
:BasicUpstart2(boot_entry)

.pc = $080e "Boot"
boot_entry:
#if C64_TEST_BOOT_HANDOFF
c64_test_boot_wait:
    lda c64_test_boot_gate
    beq c64_test_boot_wait
#endif
    jsr capture_boot_device
    lda KERNAL_MSGFLG
    sta saved_msgflg
    lda #0
    sta KERNAL_MSGFLG
    sta $0334
    sta $0335
    sta $0339
    sta $033a
    sta art_present
    lda #$0b
    sta $d011
    lda #0
    sta $d020
    sta $d021

    jsr krill_install_try
    lda $0334
    cmp #$4b
    bne !kernal_art+
    lda $0335
    cmp #$d2
    bne !kernal_art+
    jsr krill_load_boot_art
    bcs load_main_program
    jsr display_boot_art
    jmp load_main_program
!kernal_art:
    cli
    jsr load_boot_art
#if C64_TEST_BOOT_HANDOFF
c64_test_bootart_call_return:
#endif
    bcs load_main_program
    jsr display_boot_art

load_main_program:
copy_error_trampoline:
    ldx #77
!loop:
    lda error_trampoline_source - 1,x
    sta ERROR_TRAMP_ADDR - 1,x
    dex
    bne !loop-
    lda saved_msgflg
    sta error_saved_msgflg
copy_error_trampoline_end:
    lda art_present
    sta chain_art_present_source
    jsr copy_chain_stub
    lda saved_msgflg
    sta error_saved_msgflg
    sta chain_saved_msgflg
    jsr chain_install_ram_vectors
    jmp chain_entry

capture_boot_device:
    lda $ba
    cmp #8
    bcc !done+
    cmp #31
    bcs !done+
    sta boot_device
!done:
    lda boot_device
    sta $033b
    rts

boot_kernal_load:
    lda #0
    jsr $ffd5
#if C64_TEST_BOOT_HANDOFF
c64_test_boot_kernal_load_return:
#endif
    php
    pha
    lda #LOGICAL_FILE
    jsr $ffc3
    jsr $ffcc
    pla
    plp
    rts

boot_prepare_load:
    jsr $ffbd
    lda #LOGICAL_FILE
    ldx $033b
    ldy #LOAD_USE_HEADER
    jmp $ffba

load_boot_art:
#if C64_TEST_BOOT_HANDOFF
c64_test_kinst_failure_continuation:
#endif
    lda #art_filename_end - art_filename
    ldx #<art_filename
    ldy #>art_filename
    jsr boot_prepare_load
    jmp boot_kernal_load

krill_install_try:
    lda #krill_inst_name_end - krill_inst_name
    ldx #<krill_inst_name
    ldy #>krill_inst_name
    jsr boot_prepare_load
    jsr boot_kernal_load
#if C64_TEST_BOOT_HANDOFF
c64_test_kinst_call_return:
#endif
    bcs !failed+
    lda $033b
    sta $ba
#if C64_TEST_BOOT_HANDOFF
c64_test_installer_pre:
#endif
    jsr KRILL_INSTALL_ADDR
#if C64_TEST_BOOT_HANDOFF
c64_test_installer_return:
#endif
    php
    pha
    lda #BANK_ALL_ROM
    sta $01
    lda #$0b
    sta $d011
    lda #VIC_BANK0_SELECT
    sta $dd00
    lda #TEXT_D018
    sta $d018
    lda #TEXT_D016
    sta $d016
    lda #0
    sta $d020
    sta $d021
#if C64_TEST_BOOT_HANDOFF
c64_test_installer_reblanked:
#endif
    pla
    plp
#if C64_TEST_BOOT_HANDOFF
c64_test_installer_result_restored:
#endif
    bcs !failed+
    txa
    and #$f0
    beq !compatible+
    cmp #$10
    bne !incompatible+
!compatible:
    lda #$ff
    bne !store_family+
!incompatible:
    lda #0
!store_family:
    sta $0339
    jsr copy_clean_resident
#if C64_TEST_BOOT_HANDOFF
c64_test_installer_resident_copied:
#endif
    lda #$4b
    sta $0334
    lda #$d2
    sta $0335
    ldx #18
!frame:
!wait:
    lda $d012
    cmp #$ff
    bne !wait-
!wait_clear:
    lda $d012
    cmp #$ff
    beq !wait_clear-
    dex
    bne !frame-
    rts
!failed:
#if C64_TEST_BOOT_HANDOFF
c64_test_installer_failure_continuation:
#endif
    lda #0
    sta $0334
    sta $0335
    sta $0339
    rts

copy_clean_resident:
    ldx #238
!loop:
    lda embedded_kres64 - 1,x
    sta $0400 - 1,x
    dex
    bne !loop-
    rts

krill_load_boot_art:
    sei
    lda #BANK_ALL_ROM
    sta $01
    ldx #<art_filename
    ldy #>art_filename
    jsr KRILL_BOOT_LOADRAW
    bcs !done+
    lda #1
    sta $033a
!done:
    rts

display_boot_art:
    sei
    jsr boot_install_ram_vectors
    jsr copy_color_to_vic_ram
    jsr copy_screen_to_vic_ram
    jsr copy_bitmap_to_vic_ram
    jsr boot_integrity_baseline
#if C64_TEST_BOOT_HANDOFF
c64_test_art_canaries_ready:
#endif
    lda #$00
    sta $dd00
    lda #BITMAP_D018
    sta $d018
    lda #BITMAP_D016
    sta $d016
    lda #BITMAP_D011
    sta $d011
    lda #0
    sta $d020
    sta $d021
    lda #1
    sta art_present
    cli
    rts

copy_color_to_vic_ram:
    lda #BANK_NO_KERNAL
    sta $01
    lda #<ART_COLOR_STAGE
    sta ZP_SRC_LO
    lda #>ART_COLOR_STAGE
    sta ZP_SRC_HI
    lda #<ART_COLOR_DEST
    sta ZP_DST_LO
    lda #>ART_COLOR_DEST
    sta ZP_DST_HI
    jmp copy_attr

copy_screen_to_vic_ram:
    lda #BANK_ALL_RAM
    sta $01
    lda #<ART_SCREEN_STAGE
    sta ZP_SRC_LO
    lda #>ART_SCREEN_STAGE
    sta ZP_SRC_HI
    lda #<ART_SCREEN_DEST
    sta ZP_DST_LO
    lda #>ART_SCREEN_DEST
    sta ZP_DST_HI
copy_attr:
    ldx #3
!page:
    ldy #0
!byte:
    lda (ZP_SRC_LO),y
    sta (ZP_DST_LO),y
    iny
    bne !byte-
    inc ZP_SRC_HI
    inc ZP_DST_HI
    dex
    bne !page-
    ldy #0
!tail:
    lda (ZP_SRC_LO),y
    sta (ZP_DST_LO),y
    iny
    cpy #$e8
    bne !tail-
    lda #BANK_ALL_ROM
    sta $01
    rts

copy_bitmap_to_vic_ram:
    lda #BANK_ALL_RAM
    sta $01
    lda #<ART_STAGE
    sta ZP_SRC_LO
    lda #>ART_STAGE
    sta ZP_SRC_HI
    lda #<ART_BITMAP_DEST
    sta ZP_DST_LO
    lda #>ART_BITMAP_DEST
    sta ZP_DST_HI
    ldx #$1f
!page:
    ldy #0
!byte:
    lda (ZP_SRC_LO),y
    sta (ZP_DST_LO),y
    iny
    bne !byte-
    inc ZP_SRC_HI
    inc ZP_DST_HI
    dex
    bne !page-
    ldy #0
!tail:
    lda (ZP_SRC_LO),y
    sta (ZP_DST_LO),y
    iny
    cpy #$40
    bne !tail-
    lda #BANK_ALL_ROM
    sta $01
    rts

boot_irq_hidden_rom:
    cld
    pha
    lda $01
    pha
    lda #$35
    sta $01
    lda $dc0d
    lda $dd0d
    lda $d019
    sta $d019
    pla
    sta $01
    pla
    rti
boot_irq_hidden_rom_end:

boot_install_ram_vectors:
    php
    sei
    lda #<boot_irq_hidden_rom
    sta $fffa
    sta $fffe
    lda #>boot_irq_hidden_rom
    sta $fffb
    sta $ffff
    plp
    rts

copy_chain_stub:
    lda #<chain_stub_source
    sta ZP_SRC_LO
    lda #>chain_stub_source
    sta ZP_SRC_HI
    lda #<CHAIN_STUB_ADDR
    sta ZP_DST_LO
    lda #>CHAIN_STUB_ADDR
    sta ZP_DST_HI
    lda #<chain_stub_size
    sta chain_copy_count_lo
    lda #>chain_stub_size
    sta chain_copy_count_hi
!loop:
    lda chain_copy_count_lo
    ora chain_copy_count_hi
    beq !done+
    ldy #0
    lda (ZP_SRC_LO),y
    sta (ZP_DST_LO),y
    inc ZP_SRC_LO
    bne !src_ok+
    inc ZP_SRC_HI
!src_ok:
    inc ZP_DST_LO
    bne !dst_ok+
    inc ZP_DST_HI
!dst_ok:
    lda chain_copy_count_lo
    bne !dec_lo+
    dec chain_copy_count_hi
!dec_lo:
    dec chain_copy_count_lo
    jmp !loop-
!done:
    rts

chain_copy_count_lo: .byte 0
chain_copy_count_hi: .byte 0
saved_msgflg: .byte 0
boot_device: .byte DEVICE_NUM
art_present: .byte 0
#if C64_TEST_BOOT_HANDOFF
c64_test_boot_gate: .byte 0
#endif

error_trampoline_source:
.pseudopc ERROR_TRAMP_ADDR {
error_trampoline:
    pha
    php
    sei
    pla
    sta error_load_p
    pla
    sta error_load_a
    ldx #$ff
    txs
    lda #$37
    sta $01
#if C64_TEST_BOOT_HANDOFF
c64_test_terminal_rom_vectors_ready:
#endif
    lda #$0b
    sta $d011
    lda #$03
    sta $dd00
    lda #$14
    sta $d018
    lda #$08
    sta $d016
    lda #$00
    sta $d020
    sta $d021
    lda error_saved_msgflg
    sta KERNAL_MSGFLG
    jsr $e544
    lda #$0e
    sta $d020
    lda #$06
    sta $d021
    lda #$1b
    sta $d011
    cld
    cli
    jmp ($a002)
error_trampoline_instructions_end:
error_saved_msgflg: .byte 0
error_load_a: .byte 0
error_load_p: .byte 0
error_trampoline_end:
}
error_trampoline_source_end:

chain_stub_source:
.pseudopc CHAIN_STUB_ADDR {
chain_entry:
    lda $0334
    cmp #$4b
    beq !check_magic_hi+
    jmp chain_kernal
!check_magic_hi:
    lda $0335
    cmp #$d2
    beq !krill+
    jmp chain_kernal
!krill:
    sei
    lda #$37
    sta $01
    ldx #<game_filename
    ldy #>game_filename
#if C64_TEST_BOOT_HANDOFF
c64_test_krill_moria_pre:
#endif
    jsr KRILL_BOOT_LOADRAW
#if C64_TEST_BOOT_HANDOFF
c64_test_krill_moria_return:
#endif
    bcs chain_krill_fail
    jsr chain_wait_18
    ldx #<bank_filename
    ldy #>bank_filename
#if C64_TEST_BOOT_HANDOFF
c64_test_krill_bank_pre:
#endif
    jsr KRILL_BOOT_LOADRAW
#if C64_TEST_BOOT_HANDOFF
c64_test_krill_bank_return:
#endif
    bcs chain_krill_fail
    jsr chain_integrity_checkpoint
    bcs chain_krill_fail
    jsr chain_wait_18
    jsr chain_blank
    ldx #<init_filename
    ldy #>init_filename
#if C64_TEST_BOOT_HANDOFF
c64_test_krill_init_pre:
#endif
    jsr KRILL_BOOT_LOADRAW
#if C64_TEST_BOOT_HANDOFF
c64_test_krill_init_return:
#endif
    bcs chain_krill_fail
    jmp chain_success

chain_krill_fail:
    jsr chain_blank
#if C64_TEST_BOOT_HANDOFF
c64_test_recovery_blanked:
#endif
    lda #$03
    sta $dd02
    and $dd00
    sta $dd00
    jsr KRILL_BOOT_UNINSTALL
    sei
    cld
    lda #$37
    sta $01
    lda #VIC_BANK0_SELECT
    sta $dd00
    lda #TEXT_D018
    sta $d018
    lda #TEXT_D016
    sta $d016
    lda #0
    sta $d020
    sta $d021
    sta $0334
    sta $0335
    sta $0339
    sta $033a
    cli
    jmp chain_kernal_recovery

chain_kernal:
    lda #game_filename_end - game_filename
    ldx #<game_filename
    ldy #>game_filename
#if C64_TEST_BOOT_HANDOFF
c64_test_kernal_moria_pre:
#endif
    jsr chain_kernal_load
#if C64_TEST_BOOT_HANDOFF
c64_test_kernal_moria_return:
#endif
    bcs chain_error
    jsr chain_integrity_checkpoint
    bcs chain_integrity_failure
    jsr chain_blank
    lda #init_filename_end - init_filename
    ldx #<init_filename
    ldy #>init_filename
#if C64_TEST_BOOT_HANDOFF
c64_test_kernal_init_pre:
#endif
    jsr chain_kernal_load
#if C64_TEST_BOOT_HANDOFF
c64_test_kernal_init_return:
#endif
    bcs chain_error
    jmp chain_success

chain_integrity_failure:
    jsr chain_blank
    lda #0
    sta $033a
chain_kernal_recovery:
    lda #game_filename_end - game_filename
    ldx #<game_filename
    ldy #>game_filename
#if C64_TEST_BOOT_HANDOFF
c64_test_recovery_moria_pre:
#endif
    jsr chain_kernal_load
#if C64_TEST_BOOT_HANDOFF
c64_test_recovery_moria_return:
#endif
    bcs chain_error
    lda #init_filename_end - init_filename
    ldx #<init_filename
    ldy #>init_filename
#if C64_TEST_BOOT_HANDOFF
c64_test_recovery_init_pre:
#endif
    jsr chain_kernal_load
#if C64_TEST_BOOT_HANDOFF
c64_test_recovery_init_return:
#endif
    bcs chain_error

chain_success:
    lda chain_saved_msgflg
    sta KERNAL_MSGFLG
    lda #$37
    sta $01
#if C64_TEST_BOOT_HANDOFF
c64_test_chain_rom_vectors_ready:
#endif
    lda #VIC_BANK0_SELECT
    sta $dd00
    lda #TEXT_D018
    sta $d018
    lda #TEXT_D016
    sta $d016
    lda #$0b
    sta $d011
    cli
    jmp $080e

chain_error:
    jmp ERROR_TRAMP_ADDR

chain_kernal_load:
    jsr $ffbd
    lda #LOGICAL_FILE
    ldx $033b
    ldy #LOAD_USE_HEADER
    jsr $ffba
    lda #0
    jsr $ffd5
#if C64_TEST_BOOT_HANDOFF
c64_test_chain_kernal_load_return:
#endif
    php
    pha
    lda #LOGICAL_FILE
    jsr $ffc3
    jsr $ffcc
    pla
    plp
    rts

chain_integrity_checkpoint:
    lda chain_art_present
    beq !no_art+
#if C64_TEST_BOOT_HANDOFF
c64_test_integrity_pre:
#endif
    jsr chain_integrity_verify
    bcs !done+
    lda $033a
    ora #$80
    sta $033a
!no_art:
    clc
!done:
    rts

chain_blank:
    lda #$0b
    sta $d011
    rts

chain_wait_18:
    ldx #18
!frame:
!wait:
    lda $d012
    cmp #$ff
    bne !wait-
!wait_clear:
    lda $d012
    cmp #$ff
    beq !wait_clear-
    dex
    bne !frame-
    rts
chain_control_end:

chain_install_ram_vectors:
    php
    sei
    lda #<chain_irq_hidden_rom
    sta $fffa
    sta $fffe
    lda #>chain_irq_hidden_rom
    sta $fffb
    sta $ffff
    plp
    rts

chain_irq_hidden_rom:
    cld
    pha
    lda $01
    pha
    lda #$35
    sta $01
    lda $dc0d
    lda $dd0d
    lda $d019
    sta $d019
    pla
    sta $01
    pla
    rti
chain_irq_hidden_rom_end:

chain_integrity_verify:
    ldy #0
!next:
    lda chain_integrity_addr_lo,y
    sta !read+ + 1
    lda chain_integrity_addr_hi,y
    sta !read+ + 2
    lda #$ff
    sta !mask+ + 1
    cpy #4
    bcc !bitmap+
    lda #BANK_NO_KERNAL
    sta $01
    cpy #6
    bcc !read+
    lda #$0f
    sta !mask+ + 1
    bne !read+
!bitmap:
    lda #BANK_NO_ROMS
    sta $01
!read:
    lda $ffff
!mask:
    and #$ff
    cmp chain_integrity_baselines,y
    bne !failed+
    iny
    cpy #8
    bne !next-
    lda #$37
    sta $01
    clc
    rts
!failed:
    lda #$37
    sta $01
    sec
    rts
chain_integrity_code_end:

chain_saved_msgflg: .byte 0
chain_art_present: .byte 0
chain_names_state_start:
chain_integrity_baselines: .fill 8, 0

game_filename: .text "MORIA64"
game_filename_end: .byte 0
bank_filename: .text "64.BANK"; .byte 0
init_filename: .text "64.INIT"
init_filename_end: .byte 0
// Boundary canaries cover the bitmap's I/O-hole crossing plus both ends of
// each visible attribute span. The runtime harness compares every display byte.
chain_integrity_addr_lo:
    .byte <$c000, <$cfff, <$d000, <$df3f, <$e000, <$e3e7, <$d800, <$dbe7
chain_integrity_addr_hi:
    .byte >$c000, >$cfff, >$d000, >$df3f, >$e000, >$e3e7, >$d800, >$dbe7
chain_names_state_end:
chain_growth_start:
chain_growth_end:
chain_stub_end:
}
.label chain_stub_size = chain_stub_end - CHAIN_STUB_ADDR
.label chain_integrity_baselines_source = chain_stub_source + (chain_integrity_baselines - CHAIN_STUB_ADDR)
.label chain_art_present_source = chain_stub_source + (chain_art_present - CHAIN_STUB_ADDR)
.label chain_integrity_addr_lo_source = chain_stub_source + (chain_integrity_addr_lo - CHAIN_STUB_ADDR)
.label chain_integrity_addr_hi_source = chain_stub_source + (chain_integrity_addr_hi - CHAIN_STUB_ADDR)
chain_stub_source_end:

boot_integrity_baseline:
    ldy #0
!next:
    lda chain_integrity_addr_lo_source,y
    sta !read+ + 1
    lda chain_integrity_addr_hi_source,y
    sta !read+ + 2
    lda #$ff
    sta !mask+ + 1
    cpy #4
    bcc !bitmap+
    lda #BANK_NO_KERNAL
    sta $01
    cpy #6
    bcc !read+
    lda #$0f
    sta !mask+ + 1
    bne !read+
!bitmap:
    lda #BANK_NO_ROMS
    sta $01
!read:
    lda $ffff
!mask:
    and #$ff
    sta chain_integrity_baselines_source,y
    iny
    cpy #8
    bne !next-
!boot_done:
    lda #$37
    sta $01
    rts

art_filename: .text "BOOTART64"
art_filename_end: .byte 0
krill_inst_name: .text "KINST64"
krill_inst_name_end:

embedded_kres64_prg:
    .import binary "../../../build/c64/kres64.prg"
embedded_kres64_prg_end:
.label embedded_kres64 = embedded_kres64_prg + 2
.label embedded_kres64_end = embedded_kres64_prg_end
.var kinst64_prg = LoadBinary("../../../build/c64/kinst64.prg")
boot_end:

.print "C64 boot chain: " + chain_stub_size + " bytes at $0500-$" + toHexString(CHAIN_STUB_ADDR + chain_stub_size)
.print "C64 chain control: " + (chain_kernal_load - chain_entry)
.print "C64 chain load helper: " + (chain_blank - chain_kernal_load)
.print "C64 chain waits/vectors/integrity: " + (chain_saved_msgflg - chain_blank)
.print "C64 chain state/names: " + (chain_stub_end - chain_saved_msgflg)
.print "C64 chain integrity code: " + (chain_integrity_code_end - chain_integrity_verify)
.print "C64 boot embedded end: $" + toHexString(boot_end)
.assert "bitmap size is 8000", ART_BITMAP_SIZE, 8000
.assert "matrix and color size is 1000", ART_ATTR_SIZE, 1000
.assert "D018 selects matrix $E000 and bitmap $C000", BITMAP_D018, $80
.assert "boot NMI handler is 26 bytes", boot_irq_hidden_rom_end - boot_irq_hidden_rom, 26
.assert "chain NMI handler is 26 bytes", chain_irq_hidden_rom_end - chain_irq_hidden_rom, 26
.assert "terminal trampoline starts at $0340", error_trampoline, ERROR_TRAMP_ADDR
.assert "terminal trampoline instructions are 74 bytes", error_trampoline_instructions_end - error_trampoline, 74
.assert "terminal trampoline state starts at $038a", error_saved_msgflg, $038a
.assert "terminal trampoline A evidence is $038b", error_load_a, $038b
.assert "terminal trampoline P evidence is $038c", error_load_p, $038c
.assert "terminal trampoline is 77 bytes", error_trampoline_end - error_trampoline, 77
.assert "terminal trampoline ends at $038d", error_trampoline_end, $038d
.assert "terminal trampoline stays below KRES64", error_trampoline_end <= $0400, true
.assert "terminal trampoline source and destination are disjoint", error_trampoline_source >= error_trampoline_end || error_trampoline_source_end <= ERROR_TRAMP_ADDR, true
.assert "terminal trampoline source stays below KINST64", error_trampoline_source_end < KRILL_INSTALL_ADDR, true
.assert "terminal trampoline copier is 17 bytes", copy_error_trampoline_end - copy_error_trampoline, 17
.assert "chain starts at $0500", chain_entry, CHAIN_STUB_ADDR
.assert "chain control and waits fit 256-byte budget", (chain_kernal_load - chain_entry) + (chain_control_end - chain_blank) <= 256, true
.assert "chain KERNAL setup/cleanup and vector installer fit 112-byte budget", (chain_blank - chain_kernal_load) + (chain_irq_hidden_rom - chain_install_ram_vectors) <= 112, true
.assert "chain integrity and NMI handler fit 160-byte budget", (chain_integrity_code_end - chain_integrity_verify) + (chain_irq_hidden_rom_end - chain_irq_hidden_rom) <= 160, true
.assert "chain names and integrity/device state fit 48-byte budget", chain_names_state_end - chain_names_state_start <= 48, true
.assert "chain growth reserve fits 192-byte budget", chain_growth_end - chain_growth_start <= 192, true
.assert "chain fits fixed $0500-$07ff owner", CHAIN_STUB_ADDR + chain_stub_size <= $0800, true
.assert "chain source and destination are disjoint", chain_stub_source >= $0800 || chain_stub_source_end <= CHAIN_STUB_ADDR, true
.assert "embedded KRES64 PRG is 240 bytes", embedded_kres64_prg_end - embedded_kres64_prg, 240
.assert "embedded KRES64 content is 238 bytes", embedded_kres64_end - embedded_kres64, 238
.assert "KINST64 PRG header is $2000", kinst64_prg.get(0) + 256 * kinst64_prg.get(1), KRILL_INSTALL_ADDR
.assert "KINST64 content is 6984 bytes", kinst64_prg.getSize() - 2, 6984
.assert "KINST64 destination ends at $3b48", KRILL_INSTALL_ADDR + kinst64_prg.getSize() - 2, $3b48
.assert "boot embedded sources stay below KINST64", boot_end < KRILL_INSTALL_ADDR, true
.assert "handoff bytes stay below dungeon scratch", $033b < $033c, true
.assert "display bitmap is disjoint from 64.BANK", ART_BITMAP_DEST + ART_BITMAP_SIZE <= $e000, true
.assert "display matrix is disjoint from 64.BANK", ART_SCREEN_DEST + ART_ATTR_SIZE <= $f000, true

#if C64_TEST_BOOT_HANDOFF
.label c64_test_bootart_failure_continuation = load_main_program
.label c64_test_krill_recovery = chain_krill_fail
.label c64_test_kernal_recovery = chain_kernal_recovery
.label c64_test_terminal_before_warm_start = ERROR_TRAMP_ADDR + (error_trampoline_instructions_end - error_trampoline) - 3
.label c64_test_error_saved_msgflg = ERROR_TRAMP_ADDR + (error_saved_msgflg - error_trampoline)
.label c64_test_error_load_a = ERROR_TRAMP_ADDR + (error_load_a - error_trampoline)
.label c64_test_error_load_p = ERROR_TRAMP_ADDR + (error_load_p - error_trampoline)
.label c64_test_kernal_file_count = $98
.label c64_test_kernal_default_input = $99
.label c64_test_kernal_default_output = $9a
#endif
