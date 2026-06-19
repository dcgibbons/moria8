#importonce
// vdc_demo.s — Standalone VDC 80-column demo for C128
//
// Demonstrates VDC rendering pipeline:
//   1. VDC initialization (black background)
//   2. Clear VDC screen
//   3. Centered title text
//   4. All 16 RGBI colors as labeled text
//   5. Mock dungeon viewport with walls, floor, doors, player, monsters
//   6. Mock 2-line status bar in 80-col layout
//   7. Wait for keypress, exit cleanly to BASIC

// ============================================================
// BASIC stub — SYS entry
// C128 native mode: BASIC text starts at $1C01, NOT $0801.
// BasicUpstart2 hardcodes $0801 so we build the stub manually.
//
// Layout at $1C01:
//   $1C01-02: next line ptr → $1C0C
//   $1C03-04: line number 10
//   $1C05:    SYS token ($9E)
//   $1C06:    space
//   $1C07-0A: "7182" (decimal for $1C0E)
//   $1C0B:    end of line ($00)
//   $1C0C-0D: end of program ($00 $00)
//   $1C0E:    entry point
// ============================================================
.pc = $1C01 "BASIC Stub"
    .byte $0c, $1c          // Next line pointer → $1C0C
    .byte $0a, $00          // Line number 10
    .byte $9e, $20          // SYS token + space
    .byte $37, $31, $38, $32  // "7182" (decimal for $1C0E)
    .byte $00               // End of BASIC line
    .byte $00, $00          // End of BASIC program

.pc = $1C0E "VDC Demo"

// ============================================================
// Constants
// ============================================================
.const VDC_ADDR_REG  = $d600    // VDC address/status register
.const VDC_DATA_REG  = $d601    // VDC data register

.const VDC_SCREEN_BASE = $0000  // Screen chars in VDC RAM
.const VDC_ATTRIB_BASE = $0800  // Attributes in VDC RAM
.const VDC_COLS      = 80
.const VDC_ROWS      = 25

// VDC RGBI color constants
.const RGBI_BLACK       = 0
.const RGBI_DARK_BLUE   = 1
.const RGBI_DARK_GREEN  = 2
.const RGBI_DARK_CYAN   = 3
.const RGBI_DARK_RED    = 4
.const RGBI_DARK_MAGENTA = 5
.const RGBI_BROWN       = 6
.const RGBI_LIGHT_GREY  = 7
.const RGBI_DARK_GREY   = 8
.const RGBI_LIGHT_BLUE  = 9
.const RGBI_LIGHT_GREEN = 10
.const RGBI_LIGHT_CYAN  = 11
.const RGBI_LIGHT_RED   = 12
.const RGBI_LIGHT_MAGENTA = 13
.const RGBI_YELLOW      = 14
.const RGBI_WHITE       = 15

// VDC character codes (screen code layout, same as VIC-II — NOT ASCII!)
// Uppercase A-Z = $01-$1A, digits/punct $20-$3F same as ASCII
.const CH_SPACE = $20
.const CH_HASH  = $23
.const CH_PLUS  = $2b
.const CH_DOT   = $2e
.const CH_AT    = $00    // '@' = screen code $00 (not ASCII $40!)

// Zero page temps (safe — BASIC not active after entry)
.label zp_temp0  = $02
.label zp_temp1  = $03
.label zp_temp2  = $04
.label zp_ptr0   = $06
.label zp_ptr0_hi = $07

// ============================================================
// Entry point
// ============================================================
demo_entry:
    sei
    // Set VDC background color to black (register 26, bits 7-4)
    ldx #26
    jsr vdc_read_reg
    and #$0f                // Keep low nibble (unused bits)
    sta zp_temp0
    lda #$00                // Black background (high nibble = 0)
    ora zp_temp0
    ldx #26
    jsr vdc_write_reg

    // Clear the VDC screen
    jsr screen_clear_vdc

    // --- 1. Title text centered on row 3 ---
    lda #3
    sta zp_temp0            // row
    lda #27                 // (80 - 26) / 2 = 27
    sta zp_temp1            // col
    lda #RGBI_WHITE
    sta zp_temp2            // color
    lda #<str_title
    sta zp_ptr0
    lda #>str_title
    sta zp_ptr0_hi
    jsr screen_put_string_vdc

    // --- 2. Color palette display (rows 5-6) ---
    // First 8 colors on row 5
    ldx #0                  // color index
!color_row1:
    txa
    pha                     // save color index
    // Calculate column: index * 10
    asl
    sta zp_temp0
    asl
    asl
    clc
    adc zp_temp0            // A = index * 10
    clc
    adc #1                  // start col offset
    sta zp_temp1            // col

    lda #5
    sta zp_temp0            // row

    pla
    pha                     // peek at color index
    sta zp_temp2            // color = index itself

    // Get string pointer for this color name
    pla
    pha
    asl                     // *2 for word index
    tax
    lda color_name_ptrs,x
    sta zp_ptr0
    lda color_name_ptrs+1,x
    sta zp_ptr0_hi
    jsr screen_put_string_vdc

    pla
    tax
    inx
    cpx #8
    bcc !color_row1-

    // Colors 8-15 on row 6
    ldx #8
!color_row2:
    txa
    pha
    // col = (index - 8) * 10 + 1
    sec
    sbc #8
    asl
    sta zp_temp0
    asl
    asl
    clc
    adc zp_temp0
    clc
    adc #1
    sta zp_temp1            // col

    lda #6
    sta zp_temp0            // row

    pla
    pha
    sta zp_temp2            // color

    pla
    pha
    asl
    tax
    lda color_name_ptrs,x
    sta zp_ptr0
    lda color_name_ptrs+1,x
    sta zp_ptr0_hi
    jsr screen_put_string_vdc

    pla
    tax
    inx
    cpx #16
    bcc !color_row2-

    // --- 3. Mock dungeon viewport (rows 9-19) ---
    // Render dungeon row by row from data table
    // Data format: pairs of (char, color) bytes per row, $FF terminated
    // Uses $0a=saved char, $0b=saved Y offset, $0c=column counter
    lda #<dungeon_data
    sta zp_ptr0
    lda #>dungeon_data
    sta zp_ptr0_hi

    lda #0
    pha                     // row index on stack

!dungeon_row:
    pla
    pha                     // peek at row index
    clc
    adc #9
    sta zp_temp0            // screen row = 9 + index

    lda #0
    sta $0c                 // column counter
    ldy #0                  // data offset within row

!dungeon_char:
    lda (zp_ptr0),y
    cmp #$ff
    beq !dungeon_next_row+  // $FF = end of row

    sta $0a                 // save char code
    iny
    lda (zp_ptr0),y         // read color
    sta zp_temp2
    iny
    sty $0b                 // save data offset

    lda $0c                 // column counter
    clc
    adc #25                 // base column
    sta zp_temp1
    inc $0c                 // advance column

    lda $0a                 // char code
    jsr screen_put_char_vdc

    ldy $0b                 // restore data offset
    jmp !dungeon_char-

!dungeon_next_row:
    // Advance ptr0 past null terminator to next row
    iny
    tya
    clc
    adc zp_ptr0
    sta zp_ptr0
    lda zp_ptr0_hi
    adc #0
    sta zp_ptr0_hi

    pla                     // row index
    clc
    adc #1
    cmp #11                 // 11 rows of dungeon
    bcs !dungeon_done+
    pha
    jmp !dungeon_row-
!dungeon_done:

    // --- 4. Status bar (rows 23-24) ---
    // Row 23: primary stats
    lda #23
    sta zp_temp0
    lda #0
    sta zp_temp1
    lda #RGBI_LIGHT_CYAN
    sta zp_temp2
    lda #<str_status1
    sta zp_ptr0
    lda #>str_status1
    sta zp_ptr0_hi
    jsr screen_put_string_vdc

    // Row 24: ability scores
    lda #24
    sta zp_temp0
    lda #0
    sta zp_temp1
    lda #RGBI_LIGHT_GREY
    sta zp_temp2
    lda #<str_status2
    sta zp_ptr0
    lda #>str_status2
    sta zp_ptr0_hi
    jsr screen_put_string_vdc

    // --- 5. "Press any key" prompt ---
    lda #21
    sta zp_temp0
    lda #28
    sta zp_temp1
    lda #RGBI_YELLOW
    sta zp_temp2
    lda #<str_presskey
    sta zp_ptr0
    lda #>str_presskey
    sta zp_ptr0_hi
    jsr screen_put_string_vdc

    cli

    // Flush keyboard buffer (may have leftover keys from autostart)
!flush:
    jsr $ffe4               // GETIN
    bne !flush-             // Keep reading until buffer empty

    // Wait for a NEW keypress
!wait_key:
    jsr $ffe4               // GETIN
    beq !wait_key-

    // Exit cleanly back to BASIC
    rts

// ============================================================
// VDC Core Routines
// ============================================================

// vdc_write_reg — Write A to VDC register X
// Polls $D600 bit 7 for ready
vdc_write_reg:
    stx VDC_ADDR_REG
!wait:
    bit VDC_ADDR_REG
    bpl !wait-
    sta VDC_DATA_REG
    rts

// vdc_read_reg — Read VDC register X into A
vdc_read_reg:
    stx VDC_ADDR_REG
!wait:
    bit VDC_ADDR_REG
    bpl !wait-
    lda VDC_DATA_REG
    rts

// vdc_set_update_addr — Set VDC update address pointer
// Input: A = high byte, X preserved, Y = low byte
vdc_set_update_addr:
    pha
    ldx #18
    pla
    jsr vdc_write_reg       // Reg 18 = addr hi
    tya
    ldx #19
    jsr vdc_write_reg       // Reg 19 = addr lo
    rts

// vdc_write_data — Write A to VDC data register 31 (auto-increments)
vdc_write_data:
    ldx #31
    jsr vdc_write_reg
    rts

// ============================================================
// Screen Routines
// ============================================================

// screen_clear_vdc — Fill screen with spaces, attributes with light grey on black
// NOTE: vdc_write_data clobbers X (sets it to 31), so we use ZP $05
// as the page counter. We also write exactly 2000 bytes (not 2048)
// to avoid overflowing into the VDC character generator at $1000.
screen_clear_vdc:
    // Set update address to screen start ($0000)
    lda #>VDC_SCREEN_BASE
    ldy #<VDC_SCREEN_BASE
    jsr vdc_set_update_addr

    // Fill 2000 bytes with spaces ($20)
    // 2000 = 7 pages (1792) + 208 remaining
    lda #7
    sta $05                 // page counter (ZP — safe from vdc_write_data)
    ldy #0
!fill_screen:
    lda #CH_SPACE
    jsr vdc_write_data
    iny
    bne !fill_screen-
    dec $05
    bne !fill_screen-
    // Remaining 208 bytes
    ldy #0
!fill_screen_tail:
    lda #CH_SPACE
    jsr vdc_write_data
    iny
    cpy #208
    bne !fill_screen_tail-

    // Set update address to attribute start ($0800)
    lda #>VDC_ATTRIB_BASE
    ldy #<VDC_ATTRIB_BASE
    jsr vdc_set_update_addr

    // Fill 2000 bytes with light grey color ($07)
    lda #7
    sta $05
    ldy #0
!fill_attr:
    lda #RGBI_LIGHT_GREY
    jsr vdc_write_data
    iny
    bne !fill_attr-
    dec $05
    bne !fill_attr-
    ldy #0
!fill_attr_tail:
    lda #RGBI_LIGHT_GREY
    jsr vdc_write_data
    iny
    cpy #208
    bne !fill_attr_tail-

    rts

// screen_put_char_vdc — Write one character at (row, col) with color
// Input: A = VDC character code
//        zp_temp0 = row, zp_temp1 = col, zp_temp2 = color
// Preserves: nothing
screen_put_char_vdc:
    pha                     // save character

    // Calculate VDC screen address = row * 80 + col
    ldx zp_temp0            // row
    lda vdc_screen_row_lo,x
    clc
    adc zp_temp1            // + col
    tay                     // Y = addr lo
    lda vdc_screen_row_hi,x
    adc #0                  // + carry
    // A = addr hi, Y = addr lo
    jsr vdc_set_update_addr

    // Write character
    pla
    jsr vdc_write_data

    // Now write attribute at same position + $0800
    ldx zp_temp0
    lda vdc_attrib_row_lo,x
    clc
    adc zp_temp1
    tay
    lda vdc_attrib_row_hi,x
    adc #0
    jsr vdc_set_update_addr

    lda zp_temp2            // color
    jsr vdc_write_data
    rts

// screen_put_string_vdc — Write null-terminated string at (row, col) with color
// Input: zp_ptr0/zp_ptr0_hi = pointer to string (VDC character codes, $00 term)
//        zp_temp0 = row, zp_temp1 = col, zp_temp2 = color
// Preserves: nothing
screen_put_string_vdc:
    // Calculate VDC screen address for starting position
    ldx zp_temp0
    lda vdc_screen_row_lo,x
    clc
    adc zp_temp1
    tay
    lda vdc_screen_row_hi,x
    adc #0
    jsr vdc_set_update_addr

    // Stream characters via register 31 (auto-increment)
    ldy #0
!char_loop:
    lda (zp_ptr0),y
    beq !chars_done+
    jsr vdc_write_data
    iny
    bne !char_loop-         // max 255 chars per string
!chars_done:
    sty zp_temp0 + 3        // save string length in $05 (zp_temp3 area)

    // Now write attributes for the same span
    ldx zp_temp0            // row
    lda vdc_attrib_row_lo,x
    clc
    adc zp_temp1            // + starting col
    tay
    lda vdc_attrib_row_hi,x
    adc #0
    jsr vdc_set_update_addr

    // Write color attribute for each character
    ldy #0
    ldx $05                 // string length saved above
    beq !done+
!attr_loop:
    lda zp_temp2            // color
    jsr vdc_write_data
    iny
    cpy $05
    bcc !attr_loop-
!done:
    rts

// ============================================================
// Row address lookup tables
// ============================================================
vdc_screen_row_lo:
    .fill VDC_ROWS, <(VDC_SCREEN_BASE + i * VDC_COLS)
vdc_screen_row_hi:
    .fill VDC_ROWS, >(VDC_SCREEN_BASE + i * VDC_COLS)
vdc_attrib_row_lo:
    .fill VDC_ROWS, <(VDC_ATTRIB_BASE + i * VDC_COLS)
vdc_attrib_row_hi:
    .fill VDC_ROWS, >(VDC_ATTRIB_BASE + i * VDC_COLS)

// ============================================================
// String Data — VDC uses screen code layout (same as VIC-II),
// NOT ASCII! Use screencode_upper: 'A'-'Z' → $01-$1A.
// ============================================================
.encoding "screencode_upper"

str_title:
    .text "MORIA8 C128 80-COLUMN MODE"
    .byte 0

str_presskey:
    .text "PRESS ANY KEY TO EXIT"
    .byte 0

// Color name strings
str_c0:  .text "BLACK"
         .byte 0
str_c1:  .text "DK BLUE"
         .byte 0
str_c2:  .text "DK GREEN"
         .byte 0
str_c3:  .text "DK CYAN"
         .byte 0
str_c4:  .text "DK RED"
         .byte 0
str_c5:  .text "DK MGNTA"
         .byte 0
str_c6:  .text "BROWN"
         .byte 0
str_c7:  .text "LT GREY"
         .byte 0
str_c8:  .text "DK GREY"
         .byte 0
str_c9:  .text "LT BLUE"
         .byte 0
str_c10: .text "LT GREEN"
         .byte 0
str_c11: .text "LT CYAN"
         .byte 0
str_c12: .text "LT RED"
         .byte 0
str_c13: .text "LT MGNTA"
         .byte 0
str_c14: .text "YELLOW"
         .byte 0
str_c15: .text "WHITE"
         .byte 0

color_name_ptrs:
    .word str_c0, str_c1, str_c2, str_c3
    .word str_c4, str_c5, str_c6, str_c7
    .word str_c8, str_c9, str_c10, str_c11
    .word str_c12, str_c13, str_c14, str_c15

// Status bar strings (VDC ASCII)
str_status1:
    .text " GANDALF  HUMAN  LV:12  DL:25  HP:145/145  MP:32/40  AC:15  AU:12345  FULL    "
    .byte 0
str_status2:
    .text " ST:18 IN:14 WI:16 DX:17 CO:15 CH:12  EXP:125000                              "
    .byte 0

// ============================================================
// Dungeon viewport data
// Each row: pairs of (char_code, color), terminated by $FF
// Renders a small mock dungeon scene
// ============================================================
dungeon_data:
    // Row 0: top wall
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte $ff
    // Row 1: wall with door
    .byte CH_HASH, RGBI_BROWN
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_HASH, RGBI_BROWN
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_HASH, RGBI_BROWN
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_HASH, RGBI_BROWN
    .byte $ff
    // Row 2: room interior with player
    .byte CH_HASH, RGBI_BROWN
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_HASH, RGBI_BROWN
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_AT, RGBI_WHITE            // Player @
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_HASH, RGBI_BROWN
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_HASH, RGBI_BROWN
    .byte $ff
    // Row 3: room with kobold (k)
    .byte CH_HASH, RGBI_BROWN
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_PLUS, RGBI_LIGHT_GREY     // Door +
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte $0b, RGBI_LIGHT_GREEN        // 'K' kobold (screen code $0B)
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_HASH, RGBI_BROWN
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte $14, RGBI_LIGHT_RED          // 'T' troll (screen code $14)
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_HASH, RGBI_BROWN
    .byte $ff
    // Row 4: wall with corridor
    .byte CH_HASH, RGBI_BROWN
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_HASH, RGBI_BROWN
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_PLUS, RGBI_LIGHT_GREY     // Door
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_HASH, RGBI_BROWN
    .byte $ff
    // Row 5: bottom wall of top room + corridor
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_PLUS, RGBI_LIGHT_GREY     // Door
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte $ff
    // Row 6: corridor
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_DOT, RGBI_DARK_GREY       // corridor floor
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte $ff
    // Row 7: corridor continues
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte CH_SPACE, RGBI_BLACK
    .byte $ff
    // Row 8: second room top wall
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_PLUS, RGBI_LIGHT_GREY     // Door
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte $ff
    // Row 9: second room with dragon (D)
    .byte CH_HASH, RGBI_BROWN
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte $04, RGBI_LIGHT_RED          // 'D' dragon (screen code $04)
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte $0f, RGBI_YELLOW             // 'O' ooze (screen code $0F)
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_DOT, RGBI_DARK_GREY
    .byte CH_HASH, RGBI_BROWN
    .byte $ff
    // Row 10: bottom wall of second room
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte CH_HASH, RGBI_BROWN
    .byte $ff
