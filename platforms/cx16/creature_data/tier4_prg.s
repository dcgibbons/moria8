// tier4_prg.s - CX16 tier 4 bank-window PRG.
// Loads at $A000 into the currently selected CX16 RAM bank.

.encoding "screencode_mixed"
.pc = $A000 "CX16 Tier 4 Data"

#import "../../commodore/c64/creature_data/tier4.s"
