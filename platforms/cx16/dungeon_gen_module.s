// dungeon_gen_module.s - CX16 bank-window dungeon-generation module ABI.
//
// This is the first executable module contract, not the final generator body.
// The resident program loads this PRG into a selected CX16 RAM bank at $A000
// and calls the fixed entry point. Future real generation code must preserve
// the load address and entry ABI.

.pc = $a000 "CX16 Dungeon Gen Module"

cx16_dungeon_module_entry:
    clc
    lda #$d6
    ldx #$16
    ldy #$01
    rts

cx16_dungeon_module_end:
.assert "CX16 dungeon module fits one banked-RAM window", cx16_dungeon_module_end <= $c000, true
