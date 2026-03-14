#importonce
// color.s — Color palette definitions and color RAM management
//
// Defines the game's color scheme for map tiles, UI elements,
// and monster threat levels. Colors are written to color RAM
// ($D800+) alongside screen codes by the rendering routines.

// ============================================================
// Tile colors — indexed by tile type (bits 7–4 of map byte)
// ============================================================
tile_colors:
    .byte COL_DGREY     // 0: Floor
    .byte COL_LGREY     // 1: Wall (horizontal)
    .byte COL_LGREY     // 2: Wall (vertical)
    .byte COL_LGREY     // 3: Wall (corner TL)
    .byte COL_LGREY     // 4: Wall (corner TR)
    .byte COL_LGREY     // 5: Wall (corner BL)
    .byte COL_LGREY     // 6: Wall (corner BR)
    .byte COL_BROWN     // 7: Door (open)
    .byte COL_BROWN     // 8: Door (closed)
    .byte COL_WHITE     // 9: Stairs down
    .byte COL_WHITE     // 10: Stairs up
    .byte COL_GREY      // 11: Rubble
    .byte COL_RED       // 12: Magma stream
    .byte COL_WHITE     // 13: Quartz vein
    .byte COL_RED       // 14: Trap (visible)
    .byte COL_LGREY     // 15: Secret door (looks like wall)

// ============================================================
// Tile screen codes — indexed by tile type
// ============================================================
tile_screen_codes:
    .byte $2e           // 0: Floor '.'
    .byte $23           // 1: Wall horizontal '#'
    .byte $23           // 2: Wall vertical '#'
    .byte $23           // 3: Corner TL '#'
    .byte $23           // 4: Corner TR '#'
    .byte $23           // 5: Corner BL '#'
    .byte $23           // 6: Corner BR '#'
    .byte $27           // 7: Door open "'"
    .byte $2b           // 8: Door closed '+'
    .byte $3e           // 9: Stairs down '>'
    .byte $3c           // 10: Stairs up '<'
    .byte $3a           // 11: Rubble ':'
    .byte $23           // 12: Magma '#'
    .byte $25           // 13: Quartz '%'
    .byte $1e           // 14: Trap '^' (up arrow)
    .byte $23           // 15: Secret door (same as wall '#')

// ============================================================
// Special entity screen codes and colors
// ============================================================
.const SC_PLAYER    = $00   // '@' in screen codes
.const COL_PLAYER   = COL_WHITE
.const SC_GOLD      = $24   // '$'
.const COL_GOLD     = COL_YELLOW
.const SC_STORE_1   = $31   // '1'
.const COL_STORE    = COL_YELLOW

// Monster threat colors (relative to player level)
.const COL_THREAT_LOW    = COL_GREEN
.const COL_THREAT_MED    = COL_YELLOW
.const COL_THREAT_HIGH   = COL_RED
.const COL_THREAT_DEADLY = COL_LRED

// UI colors
.const COL_MSG_TEXT  = COL_LGREY    // Message line text
.const COL_STATUS    = COL_CYAN     // Status bar text
.const COL_PROMPT    = COL_WHITE    // Input prompt
.const COL_HP_OK     = COL_GREEN    // HP when >50%
.const COL_HP_WARN   = COL_YELLOW   // HP when 25-50%
.const COL_HP_CRIT   = COL_RED      // HP when <25%

// ============================================================
// Compile-time validation
// ============================================================
.assert "Tile color table = 16 entries", * - tile_screen_codes, 16
