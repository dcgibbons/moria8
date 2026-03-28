#importonce
// input_tables.s — shared base PETSCII-to-command mapping entries

.macro EmitBasePetsciiKeyMap() {
    // Vi-keys (movement)
    .byte $4b   // K — north
    .byte $4a   // J — south
    .byte $48   // H — west
    .byte $4c   // L — east
    .byte $59   // Y — northwest
    .byte $55   // U — northeast
    .byte $42   // B — southwest
    .byte $4e   // N — southeast
    // Cursor keys
    .byte $91   // Cursor up — north
    .byte $11   // Cursor down — south
    .byte $9d   // Cursor left — west
    .byte $1d   // Cursor right — east
    // Game commands
    .byte $3e   // > — stairs down
    .byte $3c   // < — stairs up
    .byte $2e   // . — rest
    .byte $53   // S — search
    .byte $4f   // O — open
    .byte $43   // C — close
    .byte $47   // G — pick up
    .byte $2c   // , — pick up (alt)
    .byte $44   // D — drop
    .byte $49   // I — inventory
    .byte $45   // E — equipment / eat
    .byte $57   // W — wear/wield
    .byte $54   // T — take off
    .byte $51   // Q — quaff
    .byte $52   // R — read scroll
    .byte $41   // A — aim wand
    .byte $5a   // Z — use staff
    .byte $4d   // M — cast spell
    .byte $50   // P — pray
    .byte $3f   // ? — help
    // Special
    .byte $58   // X — look / examine
    .byte $46   // F — gain spell from book
    // Shifted keys
    .byte $c3   // SHIFT+C — character info
    .byte $d1   // SHIFT+Q — quit
    .byte $c5   // SHIFT+E — eat
    .byte $d3   // SHIFT+S — save and quit
    .byte $c6   // SHIFT+F — fire ranged weapon
    .byte $d4   // SHIFT+T — throw item
    .byte $d2   // SHIFT+R — refuel lamp
    .byte $c4   // SHIFT+D — bash
    .byte $23   // # — toggle search mode
    .byte $2b   // + — tunnel
    .byte $2f   // / — monster recall
    .byte $17   // CTRL+W — wizard mode
    // Shifted vi-keys (running)
    .byte $cb   // SHIFT+K — run north
    .byte $ca   // SHIFT+J — run south
    .byte $c8   // SHIFT+H — run west
    .byte $cc   // SHIFT+L — run east
    .byte $d9   // SHIFT+Y — run northwest
    .byte $d5   // SHIFT+U — run northeast
    .byte $c2   // SHIFT+B — run southwest
    .byte $ce   // SHIFT+N — run southeast
}

.macro EmitBaseCommandKeyMap() {
    .byte CMD_MOVE_N, CMD_MOVE_S, CMD_MOVE_W, CMD_MOVE_E
    .byte CMD_MOVE_NW, CMD_MOVE_NE, CMD_MOVE_SW, CMD_MOVE_SE
    .byte CMD_MOVE_N, CMD_MOVE_S, CMD_MOVE_W, CMD_MOVE_E
    .byte CMD_STAIRS_DN, CMD_STAIRS_UP, CMD_REST, CMD_SEARCH
    .byte CMD_OPEN, CMD_CLOSE, CMD_PICKUP, CMD_PICKUP
    .byte CMD_DROP, CMD_INVENTORY, CMD_EQUIPMENT, CMD_WEAR
    .byte CMD_TAKEOFF, CMD_QUAFF, CMD_READ, CMD_AIM
    .byte CMD_USE, CMD_CAST, CMD_PRAY, CMD_HELP
    .byte CMD_LOOK, CMD_GAIN
    .byte CMD_CHAR_INFO, CMD_QUIT, CMD_EAT, CMD_SAVE
    .byte CMD_FIRE, CMD_THROW, CMD_REFUEL, CMD_BASH
    .byte CMD_SEARCH_MODE
    .byte CMD_TUNNEL, CMD_RECALL, CMD_WIZARD
    .byte CMD_RUN_N, CMD_RUN_S, CMD_RUN_W, CMD_RUN_E
    .byte CMD_RUN_NW, CMD_RUN_NE, CMD_RUN_SW, CMD_RUN_SE
}
